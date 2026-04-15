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

// Pull side is slot-atomic: a Fallout 2 save is a directory (SLOT01/) with
// multiple files (SAVE.DAT, AUTOMAP.DB, *.SAV). Pulling individual files as
// they land would let the load menu observe half-hydrated slots and corrupt.
// An NSMetadataQuery watches the cloud savegame scope; whenever a file's
// download status changes, we re-evaluate every slot and only copy slots
// where ALL files are Current/Downloaded. Newest-mtime-wins at slot level.
//
// Push side is per-file (iOSPushMirror): local files are always fully
// materialized, so file-level comparison is fine and avoids a whole-slot
// recopy when only one file changed.

static id s_iOSICloudBackgroundObserver = nil;
static NSMetadataQuery* s_iOSICloudQuery = nil;
static id s_iOSICloudGatherObserver = nil;
static id s_iOSICloudUpdateObserver = nil;
// Slot indices (0-based) currently observed in cloud with at least one
// placeholder file. Updated by iOSPullReadySlots whenever the metadata query
// reports gather/update. Read by iOSICloudSlotIsDownloading.
static NSMutableSet<NSNumber*>* s_iOSICloudDownloadingSlots = nil;
// Set true by iOSPullReadySlots after a successful slot copy; consumed by the
// load/save menu's frame loop via iOSICloudConsumeSavesDirty.
static volatile bool s_iOSICloudSavesDirty = false;

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
// strictly newer than dst mtime (or where dst doesn't exist). Used for
// local -> cloud push only; the pull direction is slot-atomic and driven by
// the metadata query (iOSPullReadySlots).
static void iOSPushMirror(NSURL* srcRoot, NSURL* dstRoot)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    NSArray<NSURLResourceKey>* keys = @[
        NSURLIsDirectoryKey,
        NSURLContentModificationDateKey,
    ];
    NSDirectoryEnumerator<NSURL*>* en = [fm enumeratorAtURL:srcRoot
                                 includingPropertiesForKeys:keys
                                                    options:0
                                               errorHandler:^BOOL(NSURL* url, NSError* err) {
        SDL_Log("iCloud sync: enum %s: %s",
            url.path.UTF8String, err.localizedDescription.UTF8String);
        return YES;
    }];

    // On iOS /var is a symlink to /private/var. NSDirectoryEnumerator sometimes
    // yields canonical /private/var paths even when the root URL uses /var,
    // making naive substringFromIndex slice mid-segment (e.g. "savegame" →
    // "avegame" because /private is 8 chars). Canonicalize both sides and use
    // an explicit slash-terminated prefix check so a partial match can't slip.
    NSURL* resolvedRoot = srcRoot.URLByResolvingSymlinksInPath ?: srcRoot;
    NSString* srcBase = resolvedRoot.path;
    while ([srcBase hasSuffix:@"/"] && srcBase.length > 1) {
        srcBase = [srcBase substringToIndex:srcBase.length - 1];
    }
    NSString* srcPrefix = [srcBase stringByAppendingString:@"/"];

    NSUInteger copied = 0;
    for (NSURL* srcURL in en) {
        NSNumber* isDir = nil;
        [srcURL getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            continue;
        }

        NSURL* resolved = srcURL.URLByResolvingSymlinksInPath ?: srcURL;
        NSString* resolvedPath = resolved.path;
        if (![resolvedPath hasPrefix:srcPrefix]) {
            SDL_Log("iCloud sync: push skipping %s (outside %s)",
                resolvedPath.UTF8String, srcPrefix.UTF8String);
            continue;
        }
        NSString* rel = [resolvedPath substringFromIndex:srcPrefix.length];
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
    SDL_Log("iCloud sync: push done — %lu files copied", (unsigned long)copied);
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
        iOSPushMirror(local, cloud);
        if (task != UIBackgroundTaskInvalid) {
            [app endBackgroundTask:task];
        }
    }
}

// Newest content-modification date found in any file (recursive) under dir.
// Returns nil if dir doesn't exist or is empty.
static NSDate* iOSNewestMtimeInDir(NSURL* dir)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSURL*>* en = [fm enumeratorAtURL:dir
                                 includingPropertiesForKeys:@[
                                     NSURLIsDirectoryKey,
                                     NSURLContentModificationDateKey,
                                 ]
                                                    options:0
                                               errorHandler:nil];
    if (en == nil) {
        return nil;
    }
    NSDate* newest = nil;
    for (NSURL* u in en) {
        NSNumber* isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            continue;
        }
        NSDate* mt = nil;
        [u getResourceValue:&mt forKey:NSURLContentModificationDateKey error:nil];
        if (mt == nil) {
            continue;
        }
        if (newest == nil || [mt compare:newest] == NSOrderedDescending) {
            newest = mt;
        }
    }
    return newest;
}

// Atomic slot-directory replace: remove dst, copy src -> dst under a replacing
// file coordinator. Safe even if dst doesn't exist yet.
static BOOL iOSReplaceSlotAtomic(NSURL* src, NSURL* dst)
{
    NSFileManager* fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:[dst URLByDeletingLastPathComponent]
 withIntermediateDirectories:YES
                  attributes:nil
                       error:nil];

    NSFileCoordinator* coord = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block BOOL ok = NO;
    __block NSError* opErr = nil;
    NSError* coordErr = nil;
    [coord coordinateReadingItemAtURL:src
                              options:NSFileCoordinatorReadingWithoutChanges
                     writingItemAtURL:dst
                              options:NSFileCoordinatorWritingForReplacing
                                error:&coordErr
                           byAccessor:^(NSURL* s, NSURL* d) {
        [fm removeItemAtURL:d error:nil];
        ok = [fm copyItemAtURL:s toURL:d error:&opErr];
    }];
    if (coordErr != nil || !ok) {
        NSError* e = opErr ?: coordErr;
        SDL_Log("iCloud sync: slot replace %s -> %s failed: %s",
            src.path.UTF8String, dst.path.UTF8String,
            e.localizedDescription.UTF8String);
        return NO;
    }
    return YES;
}

// Called whenever the metadata query reports gather/update. Groups current
// query results by slot dir, kicks off downloads for any placeholder, and
// atomically pulls slots whose files are all present and whose cloud copy
// is strictly newer than the local copy.
static void iOSPullReadySlots()
{
    if (s_iOSICloudQuery == nil) {
        return;
    }
    NSURL* cloud = iOSICloudSavegamesURL();
    NSURL* local = iOSLocalSavegamesURL();
    if (cloud == nil || local == nil) {
        return;
    }

    [s_iOSICloudQuery disableUpdates];
    NSArray* snapshot = [s_iOSICloudQuery.results copy];
    [s_iOSICloudQuery enableUpdates];

    NSFileManager* fm = [NSFileManager defaultManager];
    // Canonicalize + slash-terminated prefix for the same reason as iOSPushMirror:
    // /var vs /private/var mismatches would otherwise silently skip every item.
    NSURL* resolvedCloud = cloud.URLByResolvingSymlinksInPath ?: cloud;
    NSString* rootPath = resolvedCloud.path;
    while ([rootPath hasSuffix:@"/"] && rootPath.length > 1) {
        rootPath = [rootPath substringToIndex:rootPath.length - 1];
    }
    NSString* rootPrefix = [rootPath stringByAppendingString:@"/"];
    NSMutableDictionary<NSString*, NSMutableArray<NSMetadataItem*>*>* bySlot
        = [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber*>* downloading = [NSMutableSet set];

    for (NSMetadataItem* item in snapshot) {
        NSURL* url = [item valueForAttribute:NSMetadataItemURLKey];
        if (url == nil) {
            continue;
        }
        NSURL* resolvedUrl = url.URLByResolvingSymlinksInPath ?: url;
        NSString* resolvedPath = resolvedUrl.path;
        if (![resolvedPath hasPrefix:rootPrefix]) {
            continue;
        }
        NSString* rel = [resolvedPath substringFromIndex:rootPrefix.length];
        NSArray<NSString*>* parts = [rel pathComponents];
        if (parts.count < 2) {
            // File directly under savegame/ — not inside a slot dir. Ignore;
            // Fallout 2's layout only writes into SLOT<nn>/.
            continue;
        }
        NSString* slot = parts[0];
        NSMutableArray* arr = bySlot[slot];
        if (arr == nil) {
            arr = [NSMutableArray array];
            bySlot[slot] = arr;
        }
        [arr addObject:item];
    }

    for (NSString* slotName in bySlot) {
        NSArray<NSMetadataItem*>* items = bySlot[slotName];
        BOOL allReady = YES;
        NSDate* newestCloud = nil;

        for (NSMetadataItem* item in items) {
            NSString* status = [item valueForAttribute:NSMetadataUbiquitousItemDownloadingStatusKey];
            BOOL ready = [status isEqualToString:NSMetadataUbiquitousItemDownloadingStatusCurrent]
                || [status isEqualToString:NSMetadataUbiquitousItemDownloadingStatusDownloaded];
            if (!ready) {
                allReady = NO;
                NSURL* url = [item valueForAttribute:NSMetadataItemURLKey];
                if (url != nil) {
                    [fm startDownloadingUbiquitousItemAtURL:url error:nil];
                }
                continue;
            }
            NSDate* mt = [item valueForAttribute:NSMetadataItemFSContentChangeDateKey];
            if (mt != nil && (newestCloud == nil
                    || [mt compare:newestCloud] == NSOrderedDescending)) {
                newestCloud = mt;
            }
        }

        // Slot dirs are SLOT01..SLOT10. Anything else (sfall extras, custom
        // names) is left out of the per-slot UI tracking but still gets pulled.
        NSNumber* slotIdx = nil;
        if ([slotName length] == 6 && [[slotName substringToIndex:4] isEqualToString:@"SLOT"]) {
            int n = [[slotName substringFromIndex:4] intValue];
            if (n >= 1 && n <= 99) {
                slotIdx = @(n - 1);
            }
        }

        if (!allReady) {
            if (slotIdx != nil) {
                [downloading addObject:slotIdx];
            }
            continue;
        }

        NSURL* cloudSlot = [cloud URLByAppendingPathComponent:slotName];
        NSURL* localSlot = [local URLByAppendingPathComponent:slotName];
        NSDate* newestLocal = iOSNewestMtimeInDir(localSlot);

        if (newestLocal != nil && newestCloud != nil
            && [newestCloud compare:newestLocal] != NSOrderedDescending) {
            continue;
        }

        if (iOSReplaceSlotAtomic(cloudSlot, localSlot)) {
            SDL_Log("iCloud sync: pulled slot %s", slotName.UTF8String);
            s_iOSICloudSavesDirty = true;
        }
    }

    // Replace the downloading-slots set atomically (single-threaded — both
    // the writer here and the reader in iOSICloudSlotIsDownloading run on the
    // main thread).
    s_iOSICloudDownloadingSlots = downloading;
}

bool iOSICloudSlotIsDownloading(int slotIndex)
{
    NSMutableSet<NSNumber*>* set = s_iOSICloudDownloadingSlots;
    if (set == nil) {
        return false;
    }
    return [set containsObject:@(slotIndex)];
}

bool iOSICloudConsumeSavesDirty()
{
    if (!s_iOSICloudSavesDirty) {
        return false;
    }
    s_iOSICloudSavesDirty = false;
    return true;
}

// Kicks off a long-lived NSMetadataQuery watching the cloud savegame subtree.
// Stays alive for the process lifetime — it's how we learn about placeholder
// downloads completing and about saves written by the other device while
// we're running.
static void iOSStartCloudQuery()
{
    if (s_iOSICloudQuery != nil) {
        return;
    }
    NSURL* cloud = iOSICloudSavegamesURL();
    if (cloud == nil) {
        return;
    }

    NSMetadataQuery* q = [[NSMetadataQuery alloc] init];
    q.searchScopes = @[ NSMetadataQueryUbiquitousDocumentsScope ];
    // BEGINSWITH on the full cloud savegame path scopes results to our subtree
    // even though the scope covers the whole ubiquity Documents/.
    NSString* prefix = [cloud.path stringByAppendingString:@"/"];
    q.predicate = [NSPredicate predicateWithFormat:@"%K BEGINSWITH %@",
        NSMetadataItemPathKey, prefix];
    q.valueListAttributes = @[
        NSMetadataUbiquitousItemDownloadingStatusKey,
        NSMetadataItemFSContentChangeDateKey,
    ];

    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    s_iOSICloudGatherObserver = [nc addObserverForName:NSMetadataQueryDidFinishGatheringNotification
                                                object:q
                                                 queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification*) {
        SDL_Log("iCloud sync: initial gather complete — %lu items",
            (unsigned long)[q resultCount]);
        iOSPullReadySlots();
    }];
    s_iOSICloudUpdateObserver = [nc addObserverForName:NSMetadataQueryDidUpdateNotification
                                                object:q
                                                 queue:[NSOperationQueue mainQueue]
                                            usingBlock:^(NSNotification*) {
        iOSPullReadySlots();
    }];

    s_iOSICloudQuery = q;
    [q startQuery];
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

        SDL_Log("iCloud sync: watching %s", cloud.path.UTF8String);
        iOSStartCloudQuery();

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
