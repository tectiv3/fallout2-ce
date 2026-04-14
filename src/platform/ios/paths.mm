#include "paths.h"

#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

#include <SDL.h>

#include "../../settings.h"

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
static void iOSRefreshSymlink(const char* srcPath, const char* dstPath)
{
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

        const char* topLevelDats[] = { "master.dat", "critter.dat", "f2_res.dat" };
        for (size_t i = 0; i < SDL_arraysize(topLevelDats); ++i) {
            char srcPath[PATH_MAX];
            char dstPath[PATH_MAX];
            SDL_snprintf(srcPath, sizeof(srcPath), "%s%s", bundlePath, topLevelDats[i]);
            SDL_snprintf(dstPath, sizeof(dstPath), "%s%s", documentsPath, topLevelDats[i]);
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

void iOSApplyUserDefaultsToSettings()
{
    @autoreleasepool {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{
            @"resolution_preset" : @"native",
            @"resolution_scale" : @1,
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
    }
}
