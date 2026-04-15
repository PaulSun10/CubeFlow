#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TNoodleNativeBridge : NSObject
+ (nullable NSString *)scrambleForEventIndex:(NSInteger)eventIndex;
+ (nullable NSString *)initializationErrorDescription;
+ (void)prewarm;
@end

NS_ASSUME_NONNULL_END
