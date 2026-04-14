#ifndef FALLOUT_PLATFORM_IOS_PATHS_H_
#define FALLOUT_PLATFORM_IOS_PATHS_H_

const char* iOSGetDocumentsPath();
const char* iOSGetBundlePath();
void iOSSeedDocumentsFromBundle();
void iOSApplyUserDefaultsToSettings();

#endif /* FALLOUT_PLATFORM_IOS_PATHS_H_ */
