# Runs RouteNote's end-to-end integration tests (integration_test/app_test.dart).
#
# Integration tests build, install and drive the real app, so they need a
# connected Android device or a running emulator (unlike `flutter test`, which
# runs the unit/widget tests on the host). The test stubs the external platform
# channels (Google sign-in, biometrics, geolocator) so the flows are repeatable.
#
# Usage from the project root:
#   .\scripts\run_integration_tests.ps1                     # only connected device
#   .\scripts\run_integration_tests.ps1 -Device emulator-5554
#   .\scripts\run_integration_tests.ps1 -Device <device-id>

param(
  [string]$Device
)

$testPath = 'integration_test/app_test.dart'

if ($Device) {
  & flutter test $testPath -d $Device
} else {
  & flutter test $testPath
}

exit $LASTEXITCODE
