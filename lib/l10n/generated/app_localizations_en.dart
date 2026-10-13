// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MapNote';

  @override
  String get placesTitle => 'My Places';

  @override
  String get searchHint => 'Search by name or notes';

  @override
  String get addPlace => 'Save current location';

  @override
  String get addPlaceTitle => 'Save Location';

  @override
  String get editPlaceTitle => 'Edit Location';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldNameHint => 'e.g. John\'s House';

  @override
  String get fieldNotes => 'Notes';

  @override
  String get fieldNotesHint => 'e.g. Gate 3, second floor';

  @override
  String get locationCoordinates => 'Coordinates';

  @override
  String get latitude => 'Latitude';

  @override
  String get longitude => 'Longitude';

  @override
  String get currentLocation => 'Current location';

  @override
  String get fetchingLocation => 'Getting your location…';

  @override
  String get nameRequired => 'Please enter a name';

  @override
  String get pasteFromClipboard => 'Paste location from clipboard';

  @override
  String get clipboardNoLocation => 'No coordinates found in the clipboard';

  @override
  String get clipboardPasted => 'Location pasted from clipboard';

  @override
  String get locationModeCurrentGps => 'Current GPS location';

  @override
  String get locationModeManual => 'Custom coordinates';

  @override
  String get customCoordinates => 'Custom coordinates';

  @override
  String get coordinateRequired => 'Please enter a value';

  @override
  String get coordinateInvalid => 'Enter a valid number';

  @override
  String get latitudeRange => 'Latitude must be between -90 and 90';

  @override
  String get longitudeRange => 'Longitude must be between -180 and 180';

  @override
  String get plusCode => 'Plus Code';

  @override
  String get plusCodeHint => 'e.g. 8FVC9G8F+6W';

  @override
  String get shareNoLocation => 'No location found in the shared text';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Retry';

  @override
  String get navigate => 'Navigate';

  @override
  String get openInGoogleMaps => 'Open in Google Maps';

  @override
  String get openInWaze => 'Open in Waze';

  @override
  String get copyCoordinates => 'Copy coordinates';

  @override
  String get coordinatesCopied => 'Coordinates copied to clipboard';

  @override
  String get placeSaved => 'Location saved';

  @override
  String get placeDeleted => 'Location deleted';

  @override
  String get placeDetailsTitle => 'Place details';

  @override
  String get deletePlaceTitle => 'Delete place?';

  @override
  String deletePlaceMessage(String name) {
    return '\"$name\" will be removed from this device and from your next backup.';
  }

  @override
  String createdAt(String date) {
    return 'Saved $date';
  }

  @override
  String get emptyPlacesTitle => 'No saved places yet';

  @override
  String get emptyPlacesMessage =>
      'Tap + in the top bar to save your current location.';

  @override
  String get noSearchResults => 'No places match your search.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionLanguage => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get selectLanguage => 'Select language';

  @override
  String get preferredNavApp => 'Preferred navigation app';

  @override
  String get preferredNavAppSubtitle => 'Which app opens when you tap Navigate';

  @override
  String get navAppSystem => 'System default';

  @override
  String get navAppGoogleMaps => 'Google Maps';

  @override
  String get navAppWaze => 'Waze';

  @override
  String get sectionLocationServices => 'Location services';

  @override
  String get sectionPreferences => 'Preferences';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get sectionAccount => 'Account';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signOut => 'Sign out';

  @override
  String signedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get notSignedIn => 'Not signed in';

  @override
  String get syncSignInRequired => 'Sign in with Google to sync';

  @override
  String get sectionSync => 'Sync & backup';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncInProgress => 'Syncing…';

  @override
  String get syncComplete => 'Sync complete';

  @override
  String get syncSkipped => 'Sign in to sync';

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String signInFailed(String error) {
    return 'Sign-in failed: $error';
  }

  @override
  String lastSynced(String date) {
    return 'Last synced: $date';
  }

  @override
  String get neverSynced => 'Never synced';

  @override
  String get localOverridesCloud =>
      'Your device data always overwrites the Google Drive backup.';

  @override
  String get restoreFromDrive => 'Restore from Google Drive';

  @override
  String get restoreConfirmTitle => 'Restore from Google Drive?';

  @override
  String get restoreConfirmMessage =>
      'This replaces all places on this device with the backup from your Google Drive.';

  @override
  String get restoreComplete => 'Restore complete';

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get locationPermissionTitle => 'Location permission needed';

  @override
  String get locationPermissionMessage =>
      'MapNote needs access to your location to save places.';

  @override
  String get locationServicesDisabled =>
      'Please enable location services on your device.';

  @override
  String get locationUnavailable =>
      'Could not determine your location. Please try again.';

  @override
  String get openAppSettings => 'Open settings';

  @override
  String get locationStatusGps => 'GPS';

  @override
  String get locationStatusPermission => 'Permission';

  @override
  String get locationGpsOn => 'On';

  @override
  String get locationGpsOff => 'Off';

  @override
  String get locationPermissionGranted => 'Allowed';

  @override
  String get locationPermissionDenied => 'Denied';

  @override
  String get locationPermissionDeniedForever => 'Blocked';

  @override
  String get locationPermissionUnknown => 'Not requested';

  @override
  String get manageLocation => 'Manage location';

  @override
  String get dailyGpsSection => 'Daily GPS tracking';

  @override
  String get dailyGpsToggle => 'Enable daily GPS tracking';

  @override
  String get dailyGpsToggleSubtitle =>
      'Records distance and max speed while the app is open';

  @override
  String get dailyGpsPermissionHint =>
      'Location access is needed for tracking. Turn on GPS and allow location access, then re-enable tracking.';

  @override
  String get dailyDistance => 'Distance today';

  @override
  String get dailyMaxSpeed => 'Max speed';

  @override
  String get dailyTrackingActive => 'Tracking';

  @override
  String get dailyTrackingPaused => 'Paused';

  @override
  String get dailyGpsUnavailable => 'GPS unavailable — check location settings';

  @override
  String get kmUnit => 'km';

  @override
  String get kmhUnit => 'km/h';

  @override
  String get autoMotionSection => 'AutoMotion';

  @override
  String get autoMotionToggle => 'Enable AutoMotion';

  @override
  String get autoMotionToggleSubtitle =>
      'Automatically records distance and max speed while the app is open';

  @override
  String get autoMotionPermissionHint =>
      'Location access is needed for AutoMotion. Turn on GPS and allow location access, then re-enable AutoMotion.';

  @override
  String get autoMotionDistance => 'Today\'s distance';

  @override
  String get autoMotionMaxSpeed => 'Max speed today';

  @override
  String get autoMotionActive => 'Active';

  @override
  String get autoMotionPaused => 'Paused';

  @override
  String get locationChipServiceOff => 'Location off — tap to enable';

  @override
  String get locationChipPermissionDenied =>
      'Location permission needed — tap to allow';

  @override
  String get locationChipDeniedForever =>
      'Location blocked — tap to open settings';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get aboutDescription =>
      'MapNote saves your favourite places offline and syncs them to your private Google Drive. Navigation opens in the maps app you already use.';

  @override
  String get addLocation => 'Add location';

  @override
  String get addCurrentLocation => 'Current Location';

  @override
  String get addCurrentLocationSubtitle => 'Use your device\'s GPS position';

  @override
  String get aiSmartPaste => 'AI Smart Paste';

  @override
  String get aiSmartPasteSubtitle => 'Paste a Google Maps link or coordinates';

  @override
  String get enterCoordinates => 'Enter Coordinates';

  @override
  String get enterCoordinatesSubtitle => 'Type latitude and longitude manually';

  @override
  String get pinnedLabel => 'Pinned';

  @override
  String get lockedLabel => 'Locked';

  @override
  String get pinToTop => 'Pin to top';

  @override
  String get unpinFromTop => 'Unpin from top';

  @override
  String get pinnedToTop => 'Pinned to top';

  @override
  String get unpinnedFromTop => 'Removed from top';

  @override
  String get shareQr => 'Share QR code';

  @override
  String get addToHomeScreen => 'Add shortcut to home screen';

  @override
  String get lockLocation => 'Lock location';

  @override
  String get unlockLocation => 'Unlock location';

  @override
  String get locationLocked => 'Location locked';

  @override
  String get locationUnlocked => 'Location unlocked';

  @override
  String get hideLocation => 'Hide location';

  @override
  String get unhideLocation => 'Unhide location';

  @override
  String get locationHidden => 'Location hidden';

  @override
  String get locationUnhidden => 'Location unhidden';

  @override
  String get unlockToContinue => 'Verify your identity to continue';

  @override
  String get unlockToNavigate => 'Verify your identity to navigate';

  @override
  String get unlockToEdit => 'Verify your identity to edit';

  @override
  String get unlockToUnlock => 'Verify your identity to unlock';

  @override
  String get unlockToShareQr => 'Verify your identity to share';

  @override
  String get unlockToOpenVault =>
      'Verify your identity to open the Hidden Vault';

  @override
  String get authenticationFailed => 'Authentication failed';

  @override
  String get biometricsUnavailable =>
      'Biometric authentication isn\'t available on this device';

  @override
  String get noDeviceSecurityWarning =>
      'No lock screen or biometrics on this device, so verification was skipped.';

  @override
  String get sectionPrivacy => 'Privacy & security';

  @override
  String get hiddenVault => 'Hidden Vault';

  @override
  String hiddenVaultSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hidden locations',
      one: '1 hidden location',
      zero: 'No hidden locations',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVaultEmpty => 'No hidden locations';

  @override
  String get hiddenVaultEmptyMessage =>
      'Locations you hide will appear here, protected by your device lock.';

  @override
  String get qrCodeTitle => 'Share via QR code';

  @override
  String get qrCodeHint => 'Scan to open this location in a maps app';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied to clipboard';

  @override
  String get close => 'Close';

  @override
  String get shortcutRequested =>
      'Follow the on-screen prompt to add the shortcut';

  @override
  String get shortcutUnsupported =>
      'Home screen shortcuts aren\'t supported on this device';

  @override
  String get shortcutUnavailable => 'Couldn\'t add the shortcut';

  @override
  String get sectionSmartInsights => 'Smart insights';

  @override
  String get smartInsightsTitle => 'Smart Insights';

  @override
  String get smartInsightsRefresh => 'Refresh suggestions';

  @override
  String get smartInsightsDismiss => 'Dismiss';

  @override
  String get smartInsightsEmpty =>
      'Everything looks good — no suggestions right now.';

  @override
  String get smartInsightsEmptyHint =>
      'Add more places to generate smart insights and suggestions.';

  @override
  String get smartInsightsEnable => 'Enable Smart Insights';

  @override
  String get smartInsightsEnableSubtitle =>
      'Show suggestions on the Home screen';

  @override
  String get smartInsightsCloudAi => 'Cloud AI suggestions';

  @override
  String get smartInsightsCloudAiSubtitle =>
      'Let Google Gemini add optional tips. Only anonymous counts are sent — never your places, notes or coordinates.';

  @override
  String get insightWelcomeTitle => 'Save your first place';

  @override
  String get insightWelcomeBody =>
      'Tap the + button to save where you are right now.';

  @override
  String get insightNearbyDuplicatesTitle => 'Group nearby places';

  @override
  String insightNearbyDuplicatesBody(int count) {
    return '$count saved places are clustered within a few metres of each other. Consider grouping or renaming them.';
  }

  @override
  String get insightUnorganizedTitle => 'Add details to your places';

  @override
  String insightUnorganizedBody(int count) {
    return '$count places have no notes. Add a note so you can recognise them later.';
  }

  @override
  String get insightSyncIssuesTitle => 'A sync didn\'t finish';

  @override
  String insightSyncIssuesBody(int count) {
    return '$count recent syncs didn\'t complete. Check your connection and try again.';
  }

  @override
  String get insightNetworkWarningTitle => 'Possible weak network';

  @override
  String get insightNetworkWarningBody =>
      'Sync has failed several times recently. Wait for a stable connection before the next backup.';

  @override
  String get insightParseIssuesTitle => 'Some locations couldn\'t be read';

  @override
  String insightParseIssuesBody(int count) {
    return '$count pasted locations couldn\'t be parsed. Try pasting the full Google Maps link.';
  }

  @override
  String get insightStaleBackupTitle => 'Back up your places';

  @override
  String insightStaleBackupBody(int days) {
    return 'Your last backup was $days days ago. Sync now to keep your places safe.';
  }

  @override
  String get insightStaleBackupNeverBody =>
      'You haven\'t backed up yet. Sync now to keep your places safe.';

  @override
  String get insightPinFavoritesTitle => 'Pin your favourites';

  @override
  String insightPinFavoritesBody(int count) {
    return 'You have $count saved places and none pinned. Long-press a place to pin it to the top.';
  }

  @override
  String get insightOptimizationTitle => 'Keep MapNote tidy';

  @override
  String get insightOptimizationBody =>
      'A large list loads slower. Review duplicate or unused places and remove what you no longer need.';

  @override
  String get insightActionSyncNow => 'Sync now';
}
