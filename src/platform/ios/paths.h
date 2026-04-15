#ifndef FALLOUT_PLATFORM_IOS_PATHS_H_
#define FALLOUT_PLATFORM_IOS_PATHS_H_

const char* iOSGetDocumentsPath();
const char* iOSGetBundlePath();
void iOSSeedDocumentsFromBundle();
void iOSApplyUserDefaultsToSettings();

// Mirrors Documents/data/savegame ↔ iCloud Drive ubiquity container. Pull runs
// synchronously; push is registered as a UIApplicationDidEnterBackground
// observer. Safe to call when iCloud is unavailable (becomes a no-op).
void iOSInitICloudSync();

#endif /* FALLOUT_PLATFORM_IOS_PATHS_H_ */
