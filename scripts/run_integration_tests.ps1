# Runs RouteNote's end-to-end integration tests (integration_test/app_test.dart).
#
# Integration tests build, install and drive the real app, so they need a
# connected Android device or a running emulator (unlike `flutter test`, which
# runs the unit/widget tests on the host). The test stubs the external platform
# channels (Google sign-in, biometrics, geolocator) so the flows are repeatable.
#
# NOTE: RouteNote's launcher role lives on an <activity-alias> (the dynamic
# light/dark icon). `flutter test` only scans <activity> elements of the *source*
# manifest and would fail with "package identifier or launch activity not
# found"; when the debug APK already exists it reads the launch activity from
# the APK (aapt) instead. So build the debug APK before invoking the tests.
#
# Usage from the project root:
#   .\scripts\run_integration_tests.ps1                     # only connected device
#   .\scripts\run_integration_tests.ps1 -Device emulator-5554
#   .\scripts\run_integration_tests.ps1 -Device <device-id>

param(
  [string]$Device
)

$testPath = 'integration_test/app_test.dart'

# Pre-build so the activity-alias launcher can be resolved (see NOTE above).
& flutter build apk --debug
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Device) {
  & flutter test $testPath -d $Device
} else {
  & flutter test $testPath
}

exit $LASTEXITCODE
