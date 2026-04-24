#import "Header.h"

%hook CKContainer
- (id)_setupWithContainerID:(id)a options:(id)b { return nil; }
- (id)_initWithContainerIdentifier:(id)a { return nil; }
%end

%hook CKEntitlements
- (id)initWithEntitlementsDict:(NSDictionary *)entitlements {
	NSMutableDictionary *mutEntitlements = [entitlements mutableCopy];
	[mutEntitlements removeObjectForKey:@"com.apple.developer.icloud-container-environment"];
	[mutEntitlements removeObjectForKey:@"com.apple.developer.icloud-services"];
	return %orig([mutEntitlements copy]);
}
%end

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
	if (NSURL *ourAppGroupURL = getAppGroupPathIfExists()) {
		NSURL *fakeAppGroupURL = [ourAppGroupURL URLByAppendingPathComponent:groupIdentifier];
		createDirectoryIfNotExists(fakeAppGroupURL.path);
		return fakeAppGroupURL;
	}

	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *fakePath = [[paths lastObject] stringByAppendingPathComponent:groupIdentifier];
	createDirectoryIfNotExists(fakePath);
	return [NSURL fileURLWithPath:fakePath];
}
%end

// Scoped to app-extension processes only. Appex needs the suite redirect so
// it reads the group.* defaults the main app wrote (rich push previews depend
// on it). Applying it in the main process breaks UI-dismiss flag persistence
// on IG 423+ (Friends Map "Not now" reappears every launch).
static BOOL sciIsAppExtensionProcess(void) {
	static BOOL cached = NO;
	static dispatch_once_t token;
	dispatch_once(&token, ^{
		cached = ([[NSBundle mainBundle] infoDictionary][@"NSExtension"] != nil);
	});
	return cached;
}

%hook NSUserDefaults
- (id)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container {
	if (!sciIsAppExtensionProcess()) return %orig(suiteName, container);

	NSURL *appGroupURL = getAppGroupPathIfExists();
	if (!appGroupURL || ![suiteName hasPrefix:@"group"]) return %orig(suiteName, container);

	if (NSURL *customContainerURL = [appGroupURL URLByAppendingPathComponent:suiteName]) {
		return %orig(suiteName, customContainerURL);
	}
	return %orig(suiteName, container);
}
%end
