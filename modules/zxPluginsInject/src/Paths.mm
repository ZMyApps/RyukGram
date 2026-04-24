#import <objc/runtime.h>

#import "Header.h"

BOOL createDirectoryIfNotExists(NSString *path) {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:path]) return YES;

	NSError *error = nil;
	[fileManager createDirectoryAtPath:path
		   withIntermediateDirectories:YES
							attributes:nil
								 error:&error];
	return error == nil;
}

NSURL *getAppGroupPathIfExists() {
	static NSURL *cachedAppGroupPath = nil;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		LSBundleProxy *bundleProxy = [objc_getClass("LSBundleProxy") bundleProxyForCurrentProcess];
		if (!bundleProxy) return;

		NSDictionary *entitlements = bundleProxy.entitlements;
		if (![entitlements isKindOfClass:[NSDictionary class]]) return;

		NSArray *appGroups = entitlements[@"com.apple.security.application-groups"];
		if (appGroups.count == 0) return;

		NSDictionary *appGroupsPaths = bundleProxy.groupContainerURLs;
		if (![appGroupsPaths isKindOfClass:[NSDictionary class]]) return;

		cachedAppGroupPath = appGroupsPaths[[appGroups firstObject]];
	});

	return cachedAppGroupPath;
}
