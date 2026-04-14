# Copy this to ios-signing.cmake (which is gitignored) and fill in your values.
# Picked up automatically by CMakeLists.txt for both iOS and macOS builds.

set(IOS_BUNDLE_IDENTIFIER "com.setemares.fallout2-ce")
set(IOS_DEVELOPMENT_TEAM "69223SG96S")

# macOS: stable codesigning so TCC grants (e.g. iCloud Drive access) persist
# across rebuilds. Identity must match an entry from
#   security find-identity -v -p codesigning
# Developer ID Application is the natural choice for local personal builds.
# Leave unset to skip signing entirely.
set(MAC_SIGNING_IDENTITY "Developer ID Application: KINCHAKU INC. (69223SG96S)")
set(MAC_BUNDLE_IDENTIFIER "com.setemares.fallout2-ce")
