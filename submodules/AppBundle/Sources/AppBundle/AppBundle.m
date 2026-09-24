#import <AppBundle/AppBundle.h>

NSBundle * _Nonnull getAppBundle() {
    static NSBundle *appBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle mainBundle];
        if ([[bundle.bundleURL pathExtension] isEqualToString:@"appex"]) {
            bundle = [NSBundle bundleWithURL:[[bundle.bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([[bundle.bundleURL pathExtension] isEqualToString:@"framework"]) {
            bundle = [NSBundle bundleWithURL:[[bundle.bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent]];
        } else if ([[bundle.bundleURL pathExtension] isEqualToString:@"Frameworks"]) {
            bundle = [NSBundle bundleWithURL:[bundle.bundleURL URLByDeletingLastPathComponent]];
        }
        appBundle = bundle;
    });

    return appBundle;
}

// Shadowgram: icon packs. The active pack is a folder under Documents/SGIconPacks whose
// PNG files mirror bundle image names, e.g. "Settings/Menu/Proxy.png" (or the same name
// with "/" replaced by "_"). @2x/@3x variants are picked up by UIImage automatically.
// The pack is resolved once per launch, so switching packs needs a restart.
static NSString * _Nullable sgActiveIconPackDirectory(void) {
    static NSString *directory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *packName = [[NSUserDefaults standardUserDefaults] stringForKey:@"SG.iconPack"];
        if (packName.length != 0) {
            NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SGIconPacks"] stringByAppendingPathComponent:packName];
            BOOL isDirectory = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
                directory = path;
            }
        }
    });
    return directory;
}

static NSMutableSet<NSString *> *sgRequestedNames(void) {
    static NSMutableSet<NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = [[NSMutableSet alloc] init];
    });
    return names;
}

NSArray<NSString *> * _Nonnull sgRequestedBundleImageNames(void) {
    NSMutableSet<NSString *> *names = sgRequestedNames();
    @synchronized (names) {
        return [[names allObjects] sortedArrayUsingSelector:@selector(compare:)];
    }
}

static UIImage * _Nullable sgIconPackImage(NSString * _Nonnull bundleImageName) {
    NSString *directory = sgActiveIconPackDirectory();
    if (directory == nil) {
        return nil;
    }
    NSArray<NSString *> *candidates = @[
        bundleImageName,
        [bundleImageName stringByReplacingOccurrencesOfString:@"/" withString:@"_"],
        [bundleImageName lastPathComponent]
    ];
    for (NSString *candidate in candidates) {
        NSString *path = [[directory stringByAppendingPathComponent:candidate] stringByAppendingPathExtension:@"png"];
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (image != nil) {
            return image;
        }
    }
    return nil;
}

@implementation UIImage (AppBundle)

- (instancetype _Nullable)initWithBundleImageName:(NSString * _Nonnull)bundleImageName {
    NSMutableSet<NSString *> *names = sgRequestedNames();
    @synchronized (names) {
        [names addObject:bundleImageName];
    }
    UIImage *packImage = sgIconPackImage(bundleImageName);
    if (packImage != nil) {
        return packImage;
    }
    return [UIImage imageNamed:bundleImageName inBundle:getAppBundle() compatibleWithTraitCollection:nil];
}

@end
