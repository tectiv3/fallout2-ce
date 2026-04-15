#ifndef FALLOUT_PLATFORM_IOS_PATHS_H_
#define FALLOUT_PLATFORM_IOS_PATHS_H_

const char* iOSGetDocumentsPath();
const char* iOSGetBundlePath();
void iOSSeedDocumentsFromBundle();
void iOSApplyUserDefaultsToSettings();

// Mirrors Documents/data/savegame ↔ iCloud Drive ubiquity container. Pull is
// driven by a long-lived NSMetadataQuery (slot-atomic, tracks placeholder
// downloads); push is registered as a UIApplicationDidEnterBackground observer.
// Safe to call when iCloud is unavailable (becomes a no-op).
void iOSInitICloudSync();

// True if the metadata query knows about cloud files for this slot but at least
// one of them is still a placeholder. Slot index is 0-based to match the
// load/save menu's _LSstatus[] indexing. Returns false on any error or when
// iCloud is unavailable.
bool iOSICloudSlotIsDownloading(int slotIndex);

// One-shot dirty flag. Returns true if iOSPullReadySlots has copied any slot
// into local storage since the last call (and clears the flag). Polled by the
// load/save menu's frame loop to refresh slot status as cloud downloads land
// without requiring the user to close and reopen the menu.
bool iOSICloudConsumeSavesDirty();

#endif /* FALLOUT_PLATFORM_IOS_PATHS_H_ */
