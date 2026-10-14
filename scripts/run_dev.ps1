# Runs MapNote with the real Google OAuth client IDs (routenote-app project).
# Client IDs are public identifiers, not secrets.
#
# Usage from the project root:
#   .\scripts\run_dev.ps1            # any connected device / emulator
#   .\scripts\run_dev.ps1 -d android # or: -d <device-id>
#
# iOS builds require a Mac with Xcode; run the equivalent command there.

param(
  [string]$Device
)

$serverClientId = '679774190551-ojvh4k0r769c77osa7n0v3a3itlvsfr4.apps.googleusercontent.com'
$iosClientId    = '679774190551-79f3eefd6ncu34appi5rie8lo2use8i9.apps.googleusercontent.com'

$commonArgs = @(
  '--dart-define=GOOGLE_SERVER_CLIENT_ID=' + $serverClientId,
  '--dart-define=GOOGLE_IOS_CLIENT_ID=' + $iosClientId
)

if ($Device) {
  & flutter run @commonArgs -d $Device
} else {
  & flutter run @commonArgs
}