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

// Shadowgram: icon packs. Each pack is a folder under Documents/SGIconPacks whose PNG
// files mirror bundle image names, e.g. "Settings/Menu/Proxy.png" (or the same name with
// "/" replaced by "_"). @2x/@3x variants are picked up by UIImage automatically.
// Enabled packs are searched in order (first wins), then the base pack, then the app's
// own icons. Resolved once per launch, so changes need a restart.
static NSArray<NSString *> * _Nonnull sgIconPackDirectories(void) {
    static NSArray<NSString *> *directories = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableArray<NSString *> *names = [[NSMutableArray alloc] init];
        NSArray *enabled = [defaults arrayForKey:@"SG.iconPacks.enabled"];
        for (id name in enabled) {
            if ([name isKindOfClass:[NSString class]]) {
                [names addObject:name];
            }
        }
        NSString *base = [defaults stringForKey:@"SG.iconPacks.base"];
        if (base.length != 0 && ![names containsObject:base]) {
            [names addObject:base];
        }
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SGIconPacks"];
        NSMutableArray<NSString *> *result = [[NSMutableArray alloc] init];
        for (NSString *name in names) {
            NSString *path = [root stringByAppendingPathComponent:name];
            BOOL isDirectory = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
                [result addObject:path];
            }
        }
        directories = result;
    });
    return directories;
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
    NSArray<NSString *> *directories = sgIconPackDirectories();
    if (directories.count == 0) {
        return nil;
    }
    NSArray<NSString *> *candidates = @[
        bundleImageName,
        [bundleImageName stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
    ];
    for (NSString *directory in directories) {
        for (NSString *candidate in candidates) {
            NSString *path = [[directory stringByAppendingPathComponent:candidate] stringByAppendingPathExtension:@"png"];
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            if (image != nil) {
                return image;
            }
        }
    }
    return nil;
}

UIImage * _Nullable sgOriginalBundleImage(NSString * _Nonnull bundleImageName) {
    return [UIImage imageNamed:bundleImageName inBundle:getAppBundle() compatibleWithTraitCollection:nil];
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
