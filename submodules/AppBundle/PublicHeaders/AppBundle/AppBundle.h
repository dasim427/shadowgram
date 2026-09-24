#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSBundle * _Nonnull getAppBundle(void);

// Shadowgram: bundle image names requested since launch, sorted. Used to export a
// template listing for building a custom icon pack.
NSArray<NSString *> * _Nonnull sgRequestedBundleImageNames(void);

@interface UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName;

@end
