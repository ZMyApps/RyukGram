#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "SCIExcludedThreads.h"
#import <objc/runtime.h>
#import <substrate.h>

// Keep-deleted messages.
// Each iris delta carries a threadId; we stash it in TLS while orig runs so the
// IGDirectMessageUpdate alloc hook can stamp the new update. At apply time we
// neuter remote-unsend updates in-place by clearing _removeMessages_messageKeys,
// letting IG run its apply call without actually removing anything.
//
// _removeMessages_reason: 0 = unsend, 2 = delete-for-you. Delete-for-you fires
// reason=2 then a reason=0 follow-up; we track the keys for 10s so the follow-up
// passes through.

static NSString * const kSCIDeltaTidTLSKey = @"SCI.currentDeltaTid";
static const void *kSCIUpdateThreadIdKey = &kSCIUpdateThreadIdKey;

static NSString *sciGetCurrentDeltaTid(void) {
    return [NSThread currentThread].threadDictionary[kSCIDeltaTidTLSKey];
}
static void sciSetCurrentDeltaTid(NSString *tid) {
    NSMutableDictionary *td = [NSThread currentThread].threadDictionary;
    if (tid) td[kSCIDeltaTidTLSKey] = tid;
    else     [td removeObjectForKey:kSCIDeltaTidTLSKey];
}

static BOOL sciKeepDeletedEnabled() {
    return [SCIUtils getBoolPref:@"keep_deleted_message"];
}

static BOOL sciIndicateUnsentEnabled() {
    return [SCIUtils getBoolPref:@"indicate_unsent_messages"];
}

static void sciUpdateCellIndicator(id cell);
static BOOL sciLocalDeleteInProgress = NO;
static NSMutableArray *sciPendingUpdates = nil;
static NSMutableDictionary<NSString *, NSDate *> *sciDeleteForYouKeys = nil;
static NSMutableSet *sciPreservedIds = nil;
// serverId -> message content class name; populated when messages are inserted
// so we can recognize reaction/action-log records and never preserve them.
static NSMutableDictionary<NSString *, NSString *> *sciMessageContentClasses = nil;
#define SCI_CONTENT_CLASSES_MAX 4000
#define SCI_PENDING_MAX 500

#define SCI_PRESERVED_IDS_KEY @"SCIPreservedMsgIds"
#define SCI_PRESERVED_MAX 200
#define SCI_PRESERVED_TAG 1399

NSMutableSet *sciGetPreservedIds() {
    if (!sciPreservedIds) {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:SCI_PRESERVED_IDS_KEY];
        sciPreservedIds = saved ? [NSMutableSet setWithArray:saved] : [NSMutableSet set];
    }
    return sciPreservedIds;
}

static void sciSavePreservedIds() {
    NSMutableSet *ids = sciGetPreservedIds();
    while (ids.count > SCI_PRESERVED_MAX)
        [ids removeObject:[ids anyObject]];
    [[NSUserDefaults standardUserDefaults] setObject:[ids allObjects] forKey:SCI_PRESERVED_IDS_KEY];
}

void sciClearPreservedIds() {
    [sciGetPreservedIds() removeAllObjects];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:SCI_PRESERVED_IDS_KEY];
}

static NSMutableDictionary<NSString *, NSString *> *sciGetContentClasses() {
    if (!sciMessageContentClasses) sciMessageContentClasses = [NSMutableDictionary dictionary];
    return sciMessageContentClasses;
}

static void sciTrackInsertedMessage(NSString *sid, NSString *className) {
    if (!sid.length || !className.length) return;
    NSMutableDictionary *map = sciGetContentClasses();
    map[sid] = className;
    if (map.count > SCI_CONTENT_CLASSES_MAX) {
        NSArray *keys = [map allKeys];
        for (NSUInteger i = 0; i < keys.count / 10; i++) [map removeObjectForKey:keys[i]];
    }
}

static BOOL sciIsReactionRelatedMessage(NSString *sid) {
    if (!sid.length) return NO;
    NSString *className = sciGetContentClasses()[sid];
    if (!className.length) return NO;
    return [className containsString:@"Reaction"] ||
           [className containsString:@"ActionLog"] ||
           [className containsString:@"reaction"] ||
           [className containsString:@"actionLog"];
}

// ============ IRIS DELTA STAMPING ============

static NSString *sciDeltaThreadId(id delta) {
    @try {
        id payload = [delta valueForKey:@"payload"];
        if (!payload) return nil;
        Ivar tdIvar = class_getInstanceVariable([payload class], "_threadDeltaPayload");
        id threadDelta = tdIvar ? object_getIvar(payload, tdIvar) : nil;
        if (!threadDelta) return nil;
        return [threadDelta valueForKey:@"threadId"];
    } @catch (__unused id e) { return nil; }
}

// Iterate per-delta so the alloc hook can attribute each new IGDirectMessageUpdate
// to its source thread via TLS. Live delivery comes through here.
static void (*orig_handleIrisDeltas)(id self, SEL _cmd, NSArray *deltas);
static void new_handleIrisDeltas(id self, SEL _cmd, NSArray *deltas) {
    if (!deltas || deltas.count == 0) { orig_handleIrisDeltas(self, _cmd, deltas); return; }
    for (id delta in deltas) {
        sciSetCurrentDeltaTid(sciDeltaThreadId(delta));
        @try { orig_handleIrisDeltas(self, _cmd, @[delta]); } @catch (__unused id e) {}
        sciSetCurrentDeltaTid(nil);
    }
}

// Some internal IG paths bypass the top-level handler and call the per-thread
// grouped variant directly. All deltas in one call belong to the same thread.
static void (*orig_handleIrisDeltasGrouped)(id self, SEL _cmd, NSArray *deltas);
static void new_handleIrisDeltasGrouped(id self, SEL _cmd, NSArray *deltas) {
    if (!deltas || deltas.count == 0) { orig_handleIrisDeltasGrouped(self, _cmd, deltas); return; }
    sciSetCurrentDeltaTid(sciDeltaThreadId(deltas.firstObject));
    @try { orig_handleIrisDeltasGrouped(self, _cmd, deltas); } @catch (__unused id e) {}
    sciSetCurrentDeltaTid(nil);
}

// ============ ALLOC TRACKING ============

static id (*orig_msgUpdate_alloc)(id self, SEL _cmd);
static id new_msgUpdate_alloc(id self, SEL _cmd) {
    id instance = orig_msgUpdate_alloc(self, _cmd);
    if ([SCIUtils getBoolPref:@"keep_deleted_message"] && instance) {
        NSString *tid = sciGetCurrentDeltaTid();
        if (tid) {
            objc_setAssociatedObject(instance, kSCIUpdateThreadIdKey, tid,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        if (!sciPendingUpdates) sciPendingUpdates = [NSMutableArray array];
        @synchronized(sciPendingUpdates) {
            [sciPendingUpdates addObject:instance];
            while (sciPendingUpdates.count > SCI_PENDING_MAX)
                [sciPendingUpdates removeObjectAtIndex:0];
        }
    }
    return instance;
}


// ============ REMOTE UNSEND DETECTION ============

static NSString *sciExtractServerId(id key) {
    @try {
        Ivar sidIvar = class_getInstanceVariable([key class], "_messageServerId");
        if (sidIvar) {
            NSString *sid = object_getIvar(key, sidIvar);
            if ([sid isKindOfClass:[NSString class]] && sid.length > 0) return sid;
        }
    } @catch(id e) {}
    return nil;
}

static void sciPruneStaleDeleteForYouKeys() {
    if (!sciDeleteForYouKeys) return;
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-10.0];
    NSArray *allKeys = [sciDeleteForYouKeys allKeys];
    for (NSString *k in allKeys) {
        if ([sciDeleteForYouKeys[k] compare:cutoff] == NSOrderedAscending)
            [sciDeleteForYouKeys removeObjectForKey:k];
    }
}

// Clear the remove-keys ivar in place. IG's later apply iterates an empty
// list, so the cache-removal becomes a no-op without disturbing call ordering.
static void sciNeuterRemoveUpdate(id update) {
    @try {
        Ivar ivar = class_getInstanceVariable([update class], "_removeMessages_messageKeys");
        if (ivar) object_setIvar(update, ivar, nil);
    } @catch (__unused id e) {}
}

// Classify a single update and append any real-unsend server ids to `preserved`.
// Returns silently for inserts, delete-for-you initiators, follow-ups, and reactions.
static void sciProcessOneUpdate(id update, NSMutableSet<NSString *> *preserved) {
    @try {
        Ivar removeIvar = class_getInstanceVariable([update class], "_removeMessages_messageKeys");
        if (!removeIvar) return;
        NSArray *keys = object_getIvar(update, removeIvar);
        if (!keys || keys.count == 0) return;

        long long reason = -1;
        Ivar reasonIvar = class_getInstanceVariable([update class], "_removeMessages_reason");
        if (reasonIvar) {
            ptrdiff_t off = ivar_getOffset(reasonIvar);
            reason = *(long long *)((char *)(__bridge void *)update + off);
        }

        // Delete-for-you initiator — remember keys for the follow-up.
        if (reason == 2) {
            NSDate *now = [NSDate date];
            for (id key in keys) {
                NSString *sid = sciExtractServerId(key);
                if (sid) sciDeleteForYouKeys[sid] = now;
            }
            return;
        }

        if (reason != 0 || sciLocalDeleteInProgress) return;

        // Delete-for-you follow-up: every key already tracked → let through.
        BOOL allMatched = YES;
        for (id key in keys) {
            NSString *sid = sciExtractServerId(key);
            if (!sid || !sciDeleteForYouKeys[sid]) { allMatched = NO; break; }
        }
        if (allMatched) {
            for (id key in keys) {
                NSString *sid = sciExtractServerId(key);
                if (sid) [sciDeleteForYouKeys removeObjectForKey:sid];
            }
            return;
        }

        // Real remote unsend — preserve, skipping reaction/action-log records.
        for (id key in keys) {
            NSString *sid = sciExtractServerId(key);
            if (!sid) continue;
            if (sciIsReactionRelatedMessage(sid)) continue;
            [sciGetPreservedIds() addObject:sid];
            [preserved addObject:sid];
        }
    } @catch (__unused id e) {}
}

// For every pending update stamped with `tid`: classify it, preserve the ids
// if it's a real unsend, and neuter the update so the upcoming apply runs but
// doesn't remove anything. Excluded threads are dropped untouched.
static NSSet<NSString *> *sciNeuterAndPreserveForThread(NSString *tid) {
    NSMutableSet<NSString *> *preserved = [NSMutableSet set];
    if (!sciPendingUpdates || tid.length == 0) return preserved;
    if (!sciDeleteForYouKeys) sciDeleteForYouKeys = [NSMutableDictionary dictionary];
    sciPruneStaleDeleteForYouKeys();

    BOOL excluded = [SCIExcludedThreads shouldKeepDeletedBeBlockedForThreadId:tid];

    @synchronized(sciPendingUpdates) {
        NSMutableArray *remaining = [NSMutableArray array];
        for (id update in sciPendingUpdates) {
            NSString *stamp = objc_getAssociatedObject(update, kSCIUpdateThreadIdKey);
            if (![stamp isEqualToString:tid]) {
                [remaining addObject:update];
                continue;
            }
            if (excluded) continue;
            NSUInteger before = preserved.count;
            sciProcessOneUpdate(update, preserved);
            if (preserved.count > before) sciNeuterRemoveUpdate(update);
        }
        [sciPendingUpdates setArray:remaining];
    }
    if (preserved.count > 0) sciSavePreservedIds();
    return preserved;
}

// ============ CACHE UPDATE HOOK ============

static void (*orig_applyUpdates)(id self, SEL _cmd, id updates, id completion, id userAccess);
static void new_applyUpdates(id self, SEL _cmd, id updates, id completion, id userAccess) {
    if (!sciKeepDeletedEnabled()) {
        orig_applyUpdates(self, _cmd, updates, completion, userAccess);
        return;
    }

    // Neuter remote-unsend updates for the threads in this batch, then hand
    // off to IG. Apply call sequencing is preserved exactly as IG expects.
    NSMutableSet<NSString *> *preserved = [NSMutableSet set];
    if ([updates isKindOfClass:[NSArray class]]) {
        for (id tu in (NSArray *)updates) {
            NSString *tid = nil;
            @try { tid = [tu valueForKey:@"threadId"]; } @catch (__unused id e) {}
            if (tid.length == 0) continue;
            NSSet *p = sciNeuterAndPreserveForThread(tid);
            if (p.count > 0) [preserved unionSet:p];
        }
    }

    // Hand off to IG — every update applies, neutered ones become no-ops.
    orig_applyUpdates(self, _cmd, updates, completion, userAccess);

    if (preserved.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Refresh visible cells so the "Unsent" indicator shows immediately.
            Class cellClass = NSClassFromString(@"IGDirectMessageCell");
            if (cellClass) {
                UIWindow *window = [UIApplication sharedApplication].keyWindow;
                NSMutableArray *stack = [NSMutableArray arrayWithObject:window];
                while (stack.count > 0) {
                    UIView *v = stack.lastObject;
                    [stack removeLastObject];
                    if ([v isKindOfClass:cellClass]) {
                        sciUpdateCellIndicator(v);
                        continue;
                    }
                    for (UIView *sub in v.subviews)
                        [stack addObject:sub];
                }
            }

            if ([SCIUtils getBoolPref:@"unsent_message_toast"]) {
                UIView *hostView = [UIApplication sharedApplication].keyWindow;
                if (hostView) {
                    UIView *pill = [[UIView alloc] init];
                    pill.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:0.95];
                    pill.layer.cornerRadius = 18;
                    pill.layer.shadowColor = [UIColor blackColor].CGColor;
                    pill.layer.shadowOpacity = 0.4;
                    pill.layer.shadowOffset = CGSizeMake(0, 2);
                    pill.layer.shadowRadius = 8;
                    pill.translatesAutoresizingMaskIntoConstraints = NO;
                    pill.alpha = 0;

                    UILabel *label = [[UILabel alloc] init];
                    label.text = @"A message was unsent";
                    label.textColor = [UIColor whiteColor];
                    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
                    label.textAlignment = NSTextAlignmentCenter;
                    label.translatesAutoresizingMaskIntoConstraints = NO;
                    [pill addSubview:label];

                    [hostView addSubview:pill];

                    [NSLayoutConstraint activateConstraints:@[
                        [pill.topAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.topAnchor constant:8],
                        [pill.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
                        [pill.heightAnchor constraintEqualToConstant:36],
                        [label.centerXAnchor constraintEqualToAnchor:pill.centerXAnchor],
                        [label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
                        [label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:20],
                        [label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-20],
                    ]];

                    [UIView animateWithDuration:0.3 animations:^{ pill.alpha = 1; }];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [UIView animateWithDuration:0.3 animations:^{ pill.alpha = 0; } completion:^(BOOL f) {
                            [pill removeFromSuperview];
                        }];
                    });
                }
            }
        });
    }
}

// ============ LOCAL DELETE TRACKING ============

static void (*orig_removeMutation_execute)(id self, SEL _cmd, id handler, id pkg);
static void new_removeMutation_execute(id self, SEL _cmd, id handler, id pkg) {
    sciLocalDeleteInProgress = YES;
    orig_removeMutation_execute(self, _cmd, handler, pkg);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciLocalDeleteInProgress = NO;
    });
}

// ============ VISUAL INDICATOR ============

static NSString * _Nullable sciGetCellServerId(id cell) {
    @try {
        Ivar vmIvar = class_getInstanceVariable([cell class], "_viewModel");
        if (!vmIvar) return nil;
        id vm = object_getIvar(cell, vmIvar);
        if (!vm) return nil;

        SEL metaSel = NSSelectorFromString(@"messageMetadata");
        if (![vm respondsToSelector:metaSel]) return nil;
        id meta = ((id(*)(id,SEL))objc_msgSend)(vm, metaSel);
        if (!meta) return nil;

        Ivar keyIvar = class_getInstanceVariable([meta class], "_key");
        if (!keyIvar) return nil;
        id keyObj = object_getIvar(meta, keyIvar);
        if (!keyObj) return nil;

        Ivar sidIvar = class_getInstanceVariable([keyObj class], "_serverId");
        if (!sidIvar) return nil;
        NSString *serverId = object_getIvar(keyObj, sidIvar);
        return [serverId isKindOfClass:[NSString class]] ? serverId : nil;
    } @catch(id e) {}
    return nil;
}

// Hide trailing action buttons (forward, share, AI, etc.) on preserved cells —
// they don't work on preserved messages and overlap the "Unsent" label.
// _tappableAccessoryViews holds the inner tap targets; their visible wrapper
// (gray circle) is the closest squarish ancestor.

static BOOL sciCellIsPreserved(id cell) {
    NSString *sid = sciGetCellServerId(cell);
    return sid && [sciGetPreservedIds() containsObject:sid];
}

// Returns the closest squarish ancestor (32-60 pt, roughly equal width/height),
// which is the visible button wrapper. Falls back to the view itself.
static UIView *sciFindAccessoryWrapper(UIView *view) {
    UIView *cur = view;
    while (cur && cur.superview) {
        CGRect f = cur.frame;
        if (f.size.width >= 32 && f.size.width <= 60 &&
            fabs(f.size.width - f.size.height) < 4) {
            return cur;
        }
        cur = cur.superview;
    }
    return view;
}

static void sciSetTrailingButtonsHidden(UIView *cell, BOOL hidden) {
    if (!cell) return;
    Ivar accIvar = class_getInstanceVariable([cell class], "_tappableAccessoryViews");
    if (!accIvar) return;
    id accViews = object_getIvar(cell, accIvar);
    if (![accViews isKindOfClass:[NSArray class]]) return;
    for (UIView *v in (NSArray *)accViews) {
        if (![v isKindOfClass:[UIView class]]) continue;
        UIView *wrapper = sciFindAccessoryWrapper(v);
        wrapper.hidden = hidden;
        if (wrapper != v) v.hidden = hidden;
    }
}

static void (*orig_addTappableAccessoryView)(id self, SEL _cmd, id view);
static void new_addTappableAccessoryView(id self, SEL _cmd, id view) {
    orig_addTappableAccessoryView(self, _cmd, view);
    if (sciIndicateUnsentEnabled() && sciCellIsPreserved(self)) {
        if ([view isKindOfClass:[UIView class]]) {
            UIView *wrapper = sciFindAccessoryWrapper((UIView *)view);
            wrapper.hidden = YES;
            if (wrapper != view) ((UIView *)view).hidden = YES;
        }
    }
}

static void sciUpdateCellIndicator(id cell) {
    UIView *view = (UIView *)cell;
    UIView *oldIndicator = [view viewWithTag:SCI_PRESERVED_TAG];
    Ivar bubbleIvar = class_getInstanceVariable([cell class], "_messageContentContainerView");
    UIView *bubble = bubbleIvar ? object_getIvar(cell, bubbleIvar) : nil;

    if (!sciIndicateUnsentEnabled()) {
        if (oldIndicator) [oldIndicator removeFromSuperview];
        sciSetTrailingButtonsHidden(view, NO);
        return;
    }

    NSString *serverId = sciGetCellServerId(cell);
    BOOL isPreserved = serverId && [sciGetPreservedIds() containsObject:serverId];

    if (!isPreserved) {
        if (oldIndicator) [oldIndicator removeFromSuperview];
        sciSetTrailingButtonsHidden(view, NO);
        return;
    }

    sciSetTrailingButtonsHidden(view, YES);

    if (oldIndicator) return;

    UIView *parent = bubble ?: view;
    UILabel *label = [[UILabel alloc] init];
    label.tag = SCI_PRESERVED_TAG;
    label.text = @"Unsent";
    label.font = [UIFont italicSystemFontOfSize:10];
    label.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:4],
        [label.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
    ]];
}

static void (*orig_configureCell)(id self, SEL _cmd, id vm, id ringSpec, id launcherSet);
static void new_configureCell(id self, SEL _cmd, id vm, id ringSpec, id launcherSet) {
    orig_configureCell(self, _cmd, vm, ringSpec, launcherSet);
    sciUpdateCellIndicator(self);
}

static void (*orig_cellLayoutSubviews)(id self, SEL _cmd);
static void new_cellLayoutSubviews(id self, SEL _cmd) {
    orig_cellLayoutSubviews(self, _cmd);
    sciUpdateCellIndicator(self);
}

// ============ ACTION LOG TRACKING ============
//
// IGDirectThreadActionLog is the local data-model class for "X liked a
// message" thread entries. IG instantiates one whenever an action log row
// is created — reaction add/remove, theme change, etc. We hook its full
// init, grab the message ID via the messageId getter, and store the class
// name in our content-class map. Later when a remove for that ID arrives,
// the consume path recognizes it as bookkeeping and skips preserving it.
static id (*orig_actionLogFullInit)(id, SEL, id, id, id, id, id, BOOL, BOOL, id);
static id new_actionLogFullInit(id self, SEL _cmd,
                                 id message, id title, id textAttributes, id textParts,
                                 id actionLogType, BOOL collapsible, BOOL hidden, id genAIMetadata) {
    id result = orig_actionLogFullInit(self, _cmd, message, title, textAttributes, textParts,
                                        actionLogType, collapsible, hidden, genAIMetadata);
    @try {
        SEL midSel = @selector(messageId);
        if ([result respondsToSelector:midSel]) {
            id mid = ((id(*)(id, SEL))objc_msgSend)(result, midSel);
            if ([mid isKindOfClass:[NSString class]]) {
                sciTrackInsertedMessage(mid, @"IGDirectThreadActionLog");
            }
        }
    } @catch(id e) {}
    return result;
}

// ============ RUNTIME HOOKS ============

%ctor {
    // Action log entries (e.g. "X liked a message") — record their message IDs
    // when IG creates them so we can later recognize a remove for those IDs as
    // action-log bookkeeping rather than a real unsend.
    Class actionLogCls = NSClassFromString(@"IGDirectThreadActionLog");
    if (actionLogCls) {
        SEL fullInit = NSSelectorFromString(@"initWithMessage:title:textAttributes:textParts:actionLogType:collapsible:hidden:genAIMetadata:");
        if (class_getInstanceMethod(actionLogCls, fullInit))
            MSHookMessageEx(actionLogCls, fullInit, (IMP)new_actionLogFullInit, (IMP *)&orig_actionLogFullInit);
    }

    Class msgUpdateClass = NSClassFromString(@"IGDirectMessageUpdate");
    if (msgUpdateClass) {
        MSHookMessageEx(object_getClass(msgUpdateClass), @selector(alloc),
                        (IMP)new_msgUpdate_alloc, (IMP *)&orig_msgUpdate_alloc);
    }


    Class cacheClass = NSClassFromString(@"IGDirectCacheUpdatesApplicator");
    if (cacheClass) {
        SEL sel = NSSelectorFromString(@"_applyThreadUpdates:completion:userAccess:");
        if (class_getInstanceMethod(cacheClass, sel))
            MSHookMessageEx(cacheClass, sel, (IMP)new_applyUpdates, (IMP *)&orig_applyUpdates);
    }

    Class irisClass = NSClassFromString(@"IGDirectRealtimeIrisDeltaHandler");
    if (irisClass) {
        SEL sel1 = NSSelectorFromString(@"handleIrisDeltas:");
        if (class_getInstanceMethod(irisClass, sel1))
            MSHookMessageEx(irisClass, sel1,
                            (IMP)new_handleIrisDeltas,
                            (IMP *)&orig_handleIrisDeltas);

        SEL sel2 = NSSelectorFromString(@"_handleIrisDeltasGroupedByThread:");
        if (class_getInstanceMethod(irisClass, sel2))
            MSHookMessageEx(irisClass, sel2,
                            (IMP)new_handleIrisDeltasGrouped,
                            (IMP *)&orig_handleIrisDeltasGrouped);
    }

    Class cellClass = NSClassFromString(@"IGDirectMessageCell");
    if (cellClass) {
        SEL configSel = NSSelectorFromString(@"configureWithViewModel:ringViewSpecFactory:launcherSet:");
        if (class_getInstanceMethod(cellClass, configSel))
            MSHookMessageEx(cellClass, configSel,
                            (IMP)new_configureCell, (IMP *)&orig_configureCell);

        SEL layoutSel = @selector(layoutSubviews);
        MSHookMessageEx(cellClass, layoutSel,
                        (IMP)new_cellLayoutSubviews, (IMP *)&orig_cellLayoutSubviews);

        SEL addAccSel = NSSelectorFromString(@"_addTappableAccessoryView:");
        if (class_getInstanceMethod(cellClass, addAccSel))
            MSHookMessageEx(cellClass, addAccSel,
                            (IMP)new_addTappableAccessoryView, (IMP *)&orig_addTappableAccessoryView);
    }

    Class removeMutationClass = NSClassFromString(@"IGDirectMessageOutgoingUpdateRemoveMessagesMutationProcessor");
    if (removeMutationClass) {
        SEL execSel = NSSelectorFromString(@"executeWithResultHandler:accessoryPackage:");
        if (class_getInstanceMethod(removeMutationClass, execSel))
            MSHookMessageEx(removeMutationClass, execSel,
                            (IMP)new_removeMutation_execute, (IMP *)&orig_removeMutation_execute);
    }

    if (![SCIUtils getBoolPref:@"indicate_unsent_messages"]) {
        sciClearPreservedIds();
    }
}
