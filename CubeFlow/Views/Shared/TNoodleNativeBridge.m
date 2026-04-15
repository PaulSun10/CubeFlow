#import "TNoodleNativeBridge.h"

#import <TargetConditionals.h>

#if TARGET_OS_SIMULATOR

@implementation TNoodleNativeBridge

+ (nullable NSString *)scrambleForEventIndex:(NSInteger)eventIndex {
    (void)eventIndex;
    return nil;
}

+ (nullable NSString *)initializationErrorDescription {
    return @"TNoodle is unavailable on Simulator.";
}

+ (void)prewarm {
}

@end

#else

#import <dlfcn.h>

#if __has_include("graal_isolate.h")
#include "graal_isolate.h"
#elif __has_include("../../../Vendor/TNoodleLibNative.xcframework/ios-arm64/Headers/graal_isolate.h")
#include "../../../Vendor/TNoodleLibNative.xcframework/ios-arm64/Headers/graal_isolate.h"
#endif

#if __has_include("org.worldcubeassociation.tnoodle.scrambles.main.h")
#include "org.worldcubeassociation.tnoodle.scrambles.main.h"
#elif __has_include("../../../Vendor/TNoodleLibNative.xcframework/ios-arm64/Headers/org.worldcubeassociation.tnoodle.scrambles.main.h")
#include "../../../Vendor/TNoodleLibNative.xcframework/ios-arm64/Headers/org.worldcubeassociation.tnoodle.scrambles.main.h"
#endif

typedef int (*TNoodleCreateIsolateFunction)(graal_create_isolate_params_t *, graal_isolate_t **, graal_isolatethread_t **);
typedef int (*TNoodleAttachThreadFunction)(graal_isolate_t *, graal_isolatethread_t **);
typedef int (*TNoodleDetachThreadFunction)(graal_isolatethread_t *);
typedef int (*TNoodleTearDownFunction)(graal_isolatethread_t *);
typedef char *(*TNoodleScrambleFunction)(graal_isolatethread_t *, int);

static void *tnoodleLibraryHandle = NULL;
static graal_isolate_t *tnoodleIsolate = NULL;
static TNoodleCreateIsolateFunction tnoodleCreateIsolate = NULL;
static TNoodleAttachThreadFunction tnoodleAttachThread = NULL;
static TNoodleDetachThreadFunction tnoodleDetachThread = NULL;
static TNoodleTearDownFunction tnoodleTearDownIsolate = NULL;
static TNoodleScrambleFunction tnoodleScramble = NULL;
static NSString *tnoodleInitializationError = nil;

@implementation TNoodleNativeBridge

+ (nullable NSString *)scrambleForEventIndex:(NSInteger)eventIndex {
    if (![self ensureInitialized]) {
        return nil;
    }

    @synchronized(self) {
        graal_isolatethread_t *currentThread = NULL;
        int attachResult = tnoodleAttachThread(tnoodleIsolate, &currentThread);
        if (attachResult != 0 || currentThread == NULL) {
            return nil;
        }

        char *result = tnoodleScramble(currentThread, (int)eventIndex);
        if (result == NULL) {
            tnoodleDetachThread(currentThread);
            return nil;
        }

        NSString *scramble = [NSString stringWithUTF8String:result];
        tnoodleDetachThread(currentThread);
        return scramble;
    }
}

+ (nullable NSString *)initializationErrorDescription {
    [self ensureInitialized];
    return tnoodleInitializationError;
}

+ (void)prewarm {
    [self ensureInitialized];
}

+ (BOOL)ensureInitialized {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
        NSURL *frameworksURL = NSBundle.mainBundle.privateFrameworksURL;
        NSURL *resourceURL = NSBundle.mainBundle.resourceURL;
        NSArray<NSURL *> *candidateURLs = @[
            [bundleURL URLByAppendingPathComponent:@"Frameworks/lib-scrambles.dylib"],
            [frameworksURL URLByAppendingPathComponent:@"lib-scrambles.dylib"],
            [resourceURL URLByAppendingPathComponent:@"lib-scrambles.dylib"],
        ];

        NSURL *libraryURL = nil;
        for (NSURL *candidateURL in candidateURLs) {
            if (candidateURL != nil && [[NSFileManager defaultManager] fileExistsAtPath:candidateURL.path]) {
                libraryURL = candidateURL;
                break;
            }
        }

        if (libraryURL == nil) {
            tnoodleInitializationError = @"TNoodle dylib was not embedded in the app bundle.";
            return;
        }

        tnoodleLibraryHandle = dlopen(libraryURL.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        if (tnoodleLibraryHandle == NULL) {
            tnoodleLibraryHandle = dlopen("lib-scrambles.dylib", RTLD_NOW | RTLD_GLOBAL);
            if (tnoodleLibraryHandle == NULL) {
                const char *errorMessage = dlerror();
                tnoodleInitializationError = errorMessage != NULL ? [NSString stringWithUTF8String:errorMessage] : @"Failed to load TNoodle dylib.";
                return;
            }
        }

        tnoodleCreateIsolate = (TNoodleCreateIsolateFunction)dlsym(tnoodleLibraryHandle, "graal_create_isolate");
        tnoodleAttachThread = (TNoodleAttachThreadFunction)dlsym(tnoodleLibraryHandle, "graal_attach_thread");
        tnoodleDetachThread = (TNoodleDetachThreadFunction)dlsym(tnoodleLibraryHandle, "graal_detach_thread");
        tnoodleTearDownIsolate = (TNoodleTearDownFunction)dlsym(tnoodleLibraryHandle, "graal_tear_down_isolate");
        tnoodleScramble = (TNoodleScrambleFunction)dlsym(tnoodleLibraryHandle, "tnoodle_lib_scramble");

        if (tnoodleCreateIsolate == NULL || tnoodleAttachThread == NULL || tnoodleDetachThread == NULL || tnoodleTearDownIsolate == NULL || tnoodleScramble == NULL) {
            tnoodleInitializationError = @"TNoodle dylib is missing required exported symbols.";
            return;
        }

        graal_isolate_t *isolate = NULL;
        graal_isolatethread_t *initialThread = NULL;
        int createIsolateResult = tnoodleCreateIsolate(NULL, &isolate, &initialThread);
        if (createIsolateResult != 0 || isolate == NULL || initialThread == NULL) {
            tnoodleInitializationError = @"Failed to initialize TNoodle runtime.";
            return;
        }

        tnoodleIsolate = isolate;

        if (tnoodleDetachThread(initialThread) != 0) {
            tnoodleInitializationError = @"Failed to detach TNoodle initialization thread.";
        }
    });

    return tnoodleInitializationError == nil && tnoodleIsolate != NULL;
}

+ (void)tearDownIfNeeded {
    if (tnoodleIsolate != NULL && tnoodleAttachThread != NULL && tnoodleTearDownIsolate != NULL) {
        graal_isolatethread_t *currentThread = NULL;
        if (tnoodleAttachThread(tnoodleIsolate, &currentThread) == 0 && currentThread != NULL) {
            tnoodleTearDownIsolate(currentThread);
        }
        tnoodleIsolate = NULL;
    }
    if (tnoodleLibraryHandle != NULL) {
        dlclose(tnoodleLibraryHandle);
        tnoodleLibraryHandle = NULL;
    }
}

@end

#endif
