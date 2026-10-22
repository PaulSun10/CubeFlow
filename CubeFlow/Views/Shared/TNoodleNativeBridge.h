#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TNoodleNativeBridge : NSObject
+ (nullable NSString *)scrambleForEventIndex:(NSInteger)eventIndex;
+ (nullable NSString *)initializationErrorDescription;
+ (void)prewarm;
@end

@interface TNoodleNativeBridge (FrameworkLocation)
+ (nullable NSURL *)runtimeLibraryURLInBundle:(NSBundle *)bundle NS_SWIFT_NAME(runtimeLibraryURL(in:));
@end

NS_ASSUME_NONNULL_END
