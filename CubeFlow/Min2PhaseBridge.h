#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Min2PhaseBridge : NSObject
#if DEBUG
+ (NSArray<NSNumber *> *)debugSearchTiming;
#endif
+ (void)initializeTables;
+ (NSString *)randomStateFacelets;
+ (NSString *)solveFacelets:(NSString *)facelets;
+ (NSString *)movesFromFacelets:(NSString *)sourceFacelets toFacelets:(NSString *)targetFacelets;
+ (NSString *)searchFromFacelets:(NSString *)sourceFacelets toFacelets:(NSString *)targetFacelets
                   maximumDepth:(NSInteger)maximumDepth probeLimit:(NSInteger)probeLimit
                  minimumProbes:(NSInteger)minimumProbes optimal:(BOOL)optimal
    NS_SWIFT_NAME(search(from:to:maximumDepth:probeLimit:minimumProbes:optimal:));
+ (NSString *)searchFromFacelets:(NSString *)sourceFacelets toFacelets:(NSString *)targetFacelets
                   maximumDepth:(NSInteger)maximumDepth probeLimit:(NSInteger)probeLimit
                  minimumProbes:(NSInteger)minimumProbes optimal:(BOOL)optimal
            maximumMilliseconds:(NSInteger)maximumMilliseconds cancelled:(BOOL (NS_NOESCAPE ^ _Nullable)(void))cancelled
    NS_SWIFT_NAME(search(from:to:maximumDepth:probeLimit:minimumProbes:optimal:maximumMilliseconds:cancelled:));
@end

NS_ASSUME_NONNULL_END
