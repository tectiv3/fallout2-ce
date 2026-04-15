#include "paths.h"

#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

#include <SDL.h>

#include "../../settings.h"
#include "../../sfall_config.h"

// Modelled after SDL_AndroidGetExternalStoragePath.
const char* iOSGetDocumentsPath()
{
    static char* s_iOSDocumentsPath = nullptr;

    if (s_iOSDocumentsPath == nullptr) {
        @autoreleasepool {
            NSArray* array = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);

            if ([array count] > 0) {
                NSString* str = [array objectAtIndex:0];
                const char* base = [str fileSystemRepresentation];
                if (base) {
                    const size_t len = SDL_strlen(base) + 2;
                    s_iOSDocumentsPath = (char*)SDL_malloc(len);
                    if (s_iOSDocumentsPath == nullptr) {
                        SDL_OutOfMemory();
                    } else {
                        SDL_snprintf(s_iOSDocumentsPath, len, "%s/", base);
                    }
                }
            }
        }
    }

    return s_iOSDocumentsPath;
}

const char* iOSGetBundlePath()
{
    static char* s_iOSBundlePath = nullptr;

    if (s_iOSBundlePath == nullptr) {
        @autoreleasepool {
            NSString* str = [[NSBundle mainBundle] bundlePath];
            const char* base = [str fileSystemRepresentation];
            if (base) {
                const size_t len = SDL_strlen(base) + 2;
                s_iOSBundlePath = (char*)SDL_malloc(len);
                if (s_iOSBundlePath == nullptr) {
                    SDL_OutOfMemory();
                } else {
                    SDL_snprintf(s_iOSBundlePath, len, "%s/", base);
                }
            }
        }
    }

    return s_iOSBundlePath;
}

static void iOSEnsureDir(const char* path)
{
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        SDL_Log("iOSSeedDocumentsFromBundle: mkdir(%s) failed: %s", path, strerror(errno));
    }
}

// Refresh symlinks each launch so app-update bundle path changes propagate.
// Skip silently when the bundle source doesn't exist (slim build mode —
// user supplies the file in Documents themselves).
static void iOSRefreshSymlink(const char* srcPath, const char* dstPath)
{
    if (access(srcPath, F_OK) != 0) {
        return;
    }

    struct stat st;
    if (lstat(dstPath, &st) == 0) {
        if (S_ISLNK(st.st_mode)) {
            if (unlink(dstPath) != 0 && errno != ENOENT) {
                SDL_Log("iOSSeedDocumentsFromBundle: unlink(%s) failed: %s", dstPath, strerror(errno));
                return;
            }
        } else {
            return;
        }
    }

    if (symlink(srcPath, dstPath) != 0) {
        SDL_Log("iOSSeedDocumentsFromBundle: symlink(%s -> %s) failed: %s", dstPath, srcPath, strerror(errno));
    }
}

static void iOSCopyIfMissing(const char* srcPath, const char* dstPath)
{
    if (access(dstPath, F_OK) == 0) {
        return;
    }

    @autoreleasepool {
        NSString* src = [NSString stringWithUTF8String:srcPath];
        NSString* dst = [NSString stringWithUTF8String:dstPath];
        NSError* error = nil;
        if (![[NSFileManager defaultManager] copyItemAtPath:src toPath:dst error:&error]) {
            SDL_Log("iOSSeedDocumentsFromBundle: copy(%s -> %s) failed: %s",
                srcPath, dstPath, [[error localizedDescription] UTF8String]);
        }
    }
}

void iOSSeedDocumentsFromBundle()
{
    const char* bundlePath = iOSGetBundlePath();
    const char* documentsPath = iOSGetDocumentsPath();
    if (bundlePath == nullptr || documentsPath == nullptr) {
        SDL_Log("iOSSeedDocumentsFromBundle: missing bundle or documents path");
        return;
    }

    @autoreleasepool {
        char pathBuf[PATH_MAX];

        SDL_snprintf(pathBuf, sizeof(pathBuf), "%smods", documentsPath);
        iOSEnsureDir(pathBuf);

        // sfall's mods_order.txt is auto-generated only if absent. An empty
        // file left behind from a previously-broken seed would suppress that.
        SDL_snprintf(pathBuf, sizeof(pathBuf), "%smods/mods_order.txt", documentsPath);
        struct stat modsOrderStat;
        if (stat(pathBuf, &modsOrderStat) == 0 && modsOrderStat.st_size == 0) {
            unlink(pathBuf);
        }

        SDL_snprintf(pathBuf, sizeof(pathBuf), "%sdata", documentsPath);
        iOSEnsureDir(pathBuf);

        SDL_snprintf(pathBuf, sizeof(pathBuf), "%sdata/savegame", documentsPath);
        iOSEnsureDir(pathBuf);

        // Read-only game data lives in the bundle; refresh symlinks each
        // launch so the bundle path (changes on app updates) stays current.
        const char* bundleSymlinks[] = { "master.dat", "critter.dat", "f2_res.dat", "data/sound" };
        for (size_t i = 0; i < SDL_arraysize(bundleSymlinks); ++i) {
            char srcPath[PATH_MAX];
            char dstPath[PATH_MAX];
            SDL_snprintf(srcPath, sizeof(srcPath), "%s%s", bundlePath, bundleSymlinks[i]);
            SDL_snprintf(dstPath, sizeof(dstPath), "%s%s", documentsPath, bundleSymlinks[i]);
            iOSRefreshSymlink(srcPath, dstPath);
        }

        const char* topLevelConfigs[] = { "fallout2.cfg", "ddraw.ini", "f2_res.ini" };
        for (size_t i = 0; i < SDL_arraysize(topLevelConfigs); ++i) {
            char srcPath[PATH_MAX];
            char dstPath[PATH_MAX];
            SDL_snprintf(srcPath, sizeof(srcPath), "%s%s", bundlePath, topLevelConfigs[i]);
            SDL_snprintf(dstPath, sizeof(dstPath), "%s%s", documentsPath, topLevelConfigs[i]);
            iOSCopyIfMissing(srcPath, dstPath);
        }

        NSString* bundleModsDir = [NSString stringWithFormat:@"%smods", bundlePath];
        NSFileManager* fm = [NSFileManager defaultManager];
        NSArray<NSString*>* entries = [fm contentsOfDirectoryAtPath:bundleModsDir error:nil];
        for (NSString* name in entries) {
            NSString* ext = [[name pathExtension] lowercaseString];
            const char* nameCStr = [name fileSystemRepresentation];
            if (nameCStr == nullptr) {
                continue;
            }

            char srcPath[PATH_MAX];
            char dstPath[PATH_MAX];
            SDL_snprintf(srcPath, sizeof(srcPath), "%smods/%s", bundlePath, nameCStr);
            SDL_snprintf(dstPath, sizeof(dstPath), "%smods/%s", documentsPath, nameCStr);

            if ([ext isEqualToString:@"dat"]) {
                iOSRefreshSymlink(srcPath, dstPath);
            } else if ([ext isEqualToString:@"ini"] || [name isEqualToString:@"mods_order.txt"]) {
                iOSCopyIfMissing(srcPath, dstPath);
            }
        }
    }
}

#pragma mark - iCloud savegame sync

// The sync is a directory mirror keyed on per-file mtime — newer wins.
// This gives reasonable single-device backup behavior and "good enough"
// cross-device sync without requiring NSMetadataQuery, CKRecord, or conflict UI.
// The tradeoffs: a save in progress when the app is backgrounded may push a
// half-written slot (next successful save heals it); two devices writing the
// same slot concurrently lose one side silently.

static id s_iOSICloudBackgroundObserver = nil;

// Ubiquity container's Documents/savegame URL. Returns nil if iCloud Drive
// isn't available (user signed out, entitlement missing, container not yet
// provisioned on first launch — URLForUbiquityContainerIdentifier can block
// briefly and then return nil until the daemon catches up).
static NSURL* iOSICloudSavegamesURL()
{
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* container = [fm URLForUbiquityContainerIdentifier:nil];
    if (container == nil) {
        return nil;
    }
    NSURL* saves = [[container URLByAppendingPathComponent:@"Documents"]
                    URLByAppendingPathComponent:@"savegame"];
    [fm createDirectoryAtURL:saves
 withIntermediateDirectories:YES
                  attributes:nil
                       error:nil];
    return saves;
}

static NSURL* iOSLocalSavegamesURL()
{
    const char* docs = iOSGetDocumentsPath();
    if (docs == nullptr) {
        return nil;
    }
    NSString* path = [NSString stringWithFormat:@"%sdata/savegame", docs];
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

static NSDate* iOSMtime(NSURL* url)
{
    NSDictionary* attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:url.path error:nil];
    return attrs[NSFileModificationDate];
}

// True if this iCloud item is a placeholder whose content hasn't been
// downloaded yet. For non-ubiquity items, always NO.
static BOOL iOSIsUndownloadedPlaceholder(NSURL* url)
{
    NSString* status = nil;
    [url getResourceValue:&status
                   forKey:NSURLUbiquitousItemDownloadingStatusKey
                    error:nil];
    if (status == nil) {
        return NO;
    }
    return ![status isEqualToString:NSURLUbiquitousItemDownloadingStatusCurrent]
        && ![status isEqualToString:NSURLUbiquitousItemDownloadingStatusDownloaded];
}

// Copy src over dst (replacing), creating intermediate dst dirs. Uses
// NSFileCoordinator because either endpoint may be inside the ubiquity
// container.
static BOOL iOSCopyCoordinated(NSURL* src, NSURL* dst)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:[dst URLByDeletingLastPathComponent]
 withIntermediateDirectories:YES
                  attributes:nil
                       error:nil];

    NSFileCoordinator* coord = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block BOOL ok = NO;
    __block NSError* copyErr = nil;
    NSError* coordErr = nil;
    [coord coordinateReadingItemAtURL:src
                              options:NSFileCoordinatorReadingWithoutChanges
                     writingItemAtURL:dst
                              options:NSFileCoordinatorWritingForReplacing
                                error:&coordErr
                           byAccessor:^(NSURL* s, NSURL* d) {
        [fm removeItemAtURL:d error:nil];
        ok = [fm copyItemAtURL:s toURL:d error:&copyErr];
    }];
    if (coordErr != nil || !ok) {
        NSError* e = copyErr ?: coordErr;
        SDL_Log("iCloud sync: copy %s -> %s failed: %s",
            src.path.UTF8String, dst.path.UTF8String,
            e.localizedDescription.UTF8String);
        return NO;
    }
    return YES;
}

// Recursively mirror srcRoot into dstRoot, copying files whose src mtime is
// strictly newer than dst mtime (or where dst doesn't exist). Placeholders on
// the cloud side are kicked off for download and skipped this run.
static void iOSMirrorNewer(NSURL* srcRoot, NSURL* dstRoot, BOOL srcIsCloud)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray<NSURLResourceKey>* keys = @[
        NSURLIsDirectoryKey,
        NSURLContentModificationDateKey,
        NSURLUbiquitousItemDownloadingStatusKey,
    ];
    NSDirectoryEnumerator<NSURL*>* en = [fm enumeratorAtURL:srcRoot
                                 includingPropertiesForKeys:keys
                                                    options:0
                                               errorHandler:^BOOL(NSURL* url, NSError* err) {
        SDL_Log("iCloud sync: enum %s: %s",
            url.path.UTF8String, err.localizedDescription.UTF8String);
        return YES;
    }];

    NSString* srcBase = srcRoot.path;
    NSUInteger copied = 0;
    NSUInteger skipped = 0;
    for (NSURL* srcURL in en) {
        NSNumber* isDir = nil;
        [srcURL getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            continue;
        }

        if (srcIsCloud && iOSIsUndownloadedPlaceholder(srcURL)) {
            [fm startDownloadingUbiquitousItemAtURL:srcURL error:nil];
            skipped++;
            continue;
        }

        NSString* rel = [srcURL.path substringFromIndex:srcBase.length + 1];
        NSURL* dstURL = [dstRoot URLByAppendingPathComponent:rel];

        NSDate* srcDate = iOSMtime(srcURL);
        NSDate* dstDate = iOSMtime(dstURL);
        if (dstDate != nil && srcDate != nil
            && [srcDate compare:dstDate] != NSOrderedDescending) {
            continue;
        }

        if (iOSCopyCoordinated(srcURL, dstURL)) {
            copied++;
        }
    }
    SDL_Log("iCloud sync: %s mirror done — %lu copied, %lu placeholders pending",
        srcIsCloud ? "pull" : "push",
        (unsigned long)copied, (unsigned long)skipped);
}

static void iOSPushSavesToICloud()
{
    @autoreleasepool {
        NSURL* local = iOSLocalSavegamesURL();
        NSURL* cloud = iOSICloudSavegamesURL();
        if (local == nil || cloud == nil) {
            return;
        }
        UIApplication* app = [UIApplication sharedApplication];
        __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
        task = [app beginBackgroundTaskWithName:@"iCloudSavesPush"
                              expirationHandler:^{
            SDL_Log("iCloud sync: push background task expired");
            [app endBackgroundTask:task];
            task = UIBackgroundTaskInvalid;
        }];
        iOSMirrorNewer(local, cloud, /*srcIsCloud=*/NO);
        if (task != UIBackgroundTaskInvalid) {
            [app endBackgroundTask:task];
        }
    }
}

void iOSInitICloudSync()
{
    @autoreleasepool {
        NSURL* cloud = iOSICloudSavegamesURL();
        NSURL* local = iOSLocalSavegamesURL();
        if (cloud == nil || local == nil) {
            SDL_Log("iCloud sync: unavailable (no ubiquity container)");
            return;
        }

        [[NSFileManager defaultManager] createDirectoryAtURL:local
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:nil];

        SDL_Log("iCloud sync: pulling saves from %s", cloud.path.UTF8String);
        iOSMirrorNewer(cloud, local, /*srcIsCloud=*/YES);

        if (s_iOSICloudBackgroundObserver == nil) {
            s_iOSICloudBackgroundObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidEnterBackgroundNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification*) {
                iOSPushSavesToICloud();
            }];
        }
    }
}

void iOSApplyUserDefaultsToSettings()
{
    @autoreleasepool {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{
            @"resolution_preset" : @"native",
            @"resolution_scale" : @1,
            @"skip_intro_movies" : @NO,
        }];

        NSString* preset = [defaults stringForKey:@"resolution_preset"];
        int width = 0;
        int height = 0;

        if (preset == nil || [preset isEqualToString:@"native"]) {
            SDL_Rect rect;
            if (SDL_GetDisplayBounds(0, &rect) == 0) {
                width = rect.w;
                height = rect.h;
            } else {
                SDL_Log("iOSApplyUserDefaultsToSettings: SDL_GetDisplayBounds failed: %s", SDL_GetError());
                CGRect bounds = [[UIScreen mainScreen] nativeBounds];
                // UIScreen.nativeBounds reports pixels in portrait orientation regardless of device orientation.
                width = (int)bounds.size.height;
                height = (int)bounds.size.width;
            }
        } else {
            NSArray<NSString*>* parts = [preset componentsSeparatedByString:@"x"];
            if ([parts count] == 2) {
                width = [parts[0] intValue];
                height = [parts[1] intValue];
            }
        }

        if (width < 640) width = 640;
        if (width > 7680) width = 7680;
        if (height < 480) height = 480;
        if (height > 4320) height = 4320;

        int scale = (int)[defaults integerForKey:@"resolution_scale"];
        if (scale < 1) scale = 1;
        if (scale > 4) scale = 4;

        fallout::settings.screen.resolution_x = width;
        fallout::settings.screen.resolution_y = height;
        fallout::settings.screen.scale = scale;

        // SkipOpeningMovies: 0=play intros, 1=skip intros, 2=also skip splash.
        // Map the toggle to 0/2 so the splash is also skipped when the user
        // opts out of intros (the common "just boot me in" expectation).
        int skipIntros = [defaults boolForKey:@"skip_intro_movies"] ? 2 : 0;
        fallout::configSetInt(&fallout::gSfallConfig,
            SFALL_CONFIG_MISC_KEY,
            SFALL_CONFIG_SKIP_OPENING_MOVIES_KEY,
            skipIntros);
    }
}
