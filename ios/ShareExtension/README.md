# iOS Share Extension (MapNote)

MapNote already handles shared text/links on the Dart side (see
`lib/src/services/share_intent_service.dart`) and its `ios/Runner/Info.plist`
declares the `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` URL scheme. iOS,
however, requires a real **Share Extension target** for the app to appear in the
system share sheet. That target can only be created from Xcode, so the files in
this folder are ready-to-use templates.

The extension code comes from the [`receive_sharing_intent`](https://pub.dev/packages/receive_sharing_intent)
package. Follow its guide for the current version if anything below drifts.

## One-time Xcode setup

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Share Extension**, name it **Share Extension**,
   and set its deployment target to match `Runner`.
3. Replace the generated files with the ones in this folder:
   - `Share Extension/Info.plist` ← `ios/ShareExtension/Info.plist`
   - `Share Extension/ShareViewController.swift` ← `ios/ShareExtension/ShareViewController.swift`
   - `Share Extension/Base.lproj/MainInterface.storyboard` ← `ios/ShareExtension/Base.lproj/MainInterface.storyboard`
4. Add an **App Groups** capability to **both** the `Runner` and `Share Extension`
   targets, using the container `group.com.routenote.routenote`, and point the
   extension's entitlements at `ios/ShareExtension/ShareExtension.entitlements`.
5. Add a user-defined build setting `CUSTOM_GROUP_ID` = `group.com.routenote.routenote`
   to **both** targets.
6. In `ios/Podfile`, add the extension target so it can import the plugin:

   ```ruby
   target 'Share Extension' do
     inherit! :search_paths
     use_frameworks!
   end
   ```

   Then run `pod install` from `ios/`.
7. Make sure the extension's `ShareViewController` inherits from
   `RSIShareViewController` (already done in the template).

## Notes

- Only text and web URLs are activated, which is all MapNote needs for
  "share a location".
- The `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` scheme in `Runner/Info.plist`
  is what lets the extension hand the payload back to the main app.
- Android needs no extra steps: the share filters live in
  `android/app/src/main/AndroidManifest.xml`.
