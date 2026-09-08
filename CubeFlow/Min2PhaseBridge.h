#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Min2PhaseBridge : NSObject
+ (void)initializeTables;
+ (NSString *)randomStateFacelets;
+ (NSString *)solveFacelets:(NSString *)facelets;
+ (NSString *)movesFromFacelets:(NSString *)sourceFacelets toFacelets:(NSString *)targetFacelets;
@end

NS_ASSUME_NONNULL_END
