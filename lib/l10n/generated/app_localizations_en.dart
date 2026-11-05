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
  String get languageArabic => 'Arabic';

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
  String get fontScale => 'Font size';

  @override
  String get fontScaleSmall => 'Small';

  @override
  String get fontScaleStandard => 'Standard';

  @override
  String get fontScaleLarge => 'Large';

  @override
  String get fontScaleExtraLarge => 'Extra large';

  @override
  String get hapticFeedback => 'Haptic feedback';

  @override
  String get uiDensityCompact => 'Compact UI density';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get sectionAccount => 'Account';

  @override
  String get sectionSecurityVault => 'Security Vault';

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
  String get contactsPermissionTitle => 'Contacts permission needed';

  @override
  String get contactsPermissionNeeded =>
      'MapNote needs access to your contacts to let you link them to saved places.';

  @override
  String get contactsPermissionDeniedPermanently =>
      'Contacts permission was permanently denied. You can change this in your device settings.';

  @override
  String get contactPickerFeatureNotReady =>
      'Contact picker feature is not ready yet.';

  @override
  String get unlinkContactFeatureNotReady =>
      'Unlink contact feature is not ready yet.';

  @override
  String get allow => 'Allow';

  @override
  String get settings => 'Settings';

  @override
  String linkedContact(String name) {
    return 'Linked contact: $name';
  }

  @override
  String get unlinkContact => 'Unlink';

  @override
  String get linkContact => 'Link contact';

  @override
  String get smartBatterySaver => 'Smart Battery Saver';

  @override
  String get smartBatterySaverDesc => 'Reduce GPS updates when stationary.';

  @override
  String get exportMotionData => 'Export motion data';

  @override
  String tileCacheSize(Object size) {
    return 'Tile cache size: $size';
  }

  @override
  String get clearTileCache => 'Clear tile cache';

  @override
  String get preloadOfflineMaps => 'Preload offline maps';

  @override
  String get offlineMapDownloaded => 'Offline map downloaded';

  @override
  String get offlineMapRegionSelection => 'Offline Map Region';

  @override
  String get minLatitude => 'Min Latitude';

  @override
  String get maxLatitude => 'Max Latitude';

  @override
  String get latitudeHint => 'Min latitude (e.g. 30.05)';

  @override
  String get minLongitude => 'Min Longitude';

  @override
  String get maxLongitude => 'Max Longitude';

  @override
  String get longitudeHint => 'Min longitude (e.g. 31.22)';

  @override
  String get minZoom => 'Min Zoom';

  @override
  String get maxZoom => 'Max Zoom';

  @override
  String get zoomHint => 'Zoom level (0-20)';

  @override
  String get startDownload => 'Start Download';

  @override
  String get autoMotionExport => 'Export';

  @override
  String get autoMotionCustomRange => 'Custom range';

  @override
  String autoMotionRangeLabel(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String get autoMotionSelectRange => 'Custom range';

  @override
  String get autoMotionExportCopied => 'Exported to clipboard';

  @override
  String get zeroCoordinatesNotice =>
      'Export does not contain location coordinates';

  @override
  String get autoMotionExportCsv => 'CSV';

  @override
  String get autoMotionExportJson => 'JSON';

  @override
  String get autoMotionExportCopy => 'Copy';

  @override
  String get savedPlacesVaultLock => 'Vault lock';

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
  String get autoMotionDashboardTitle => 'AutoMotion Dashboard';

  @override
  String get autoMotionDriverMode => 'Driver mode';

  @override
  String get autoMotionCurrentSpeed => 'Current speed';

  @override
  String get autoMotionToday => 'Today';

  @override
  String get autoMotionHistory => 'Trip history';

  @override
  String get autoMotionHistoryEmpty => 'No motion recorded yet';

  @override
  String get autoMotionHistoryEmptyHint =>
      'Days with recorded motion will appear here.';

  @override
  String get autoMotionActivityBreakdown => 'Activity breakdown';

  @override
  String get autoMotionActivityBreakdownToday => 'Today\'s activity';

  @override
  String get autoMotionActivityBreakdownEmpty => 'No mode data recorded yet.';

  @override
  String get autoMotionModeWalk => 'Walk';

  @override
  String get autoMotionModeRun => 'Run';

  @override
  String get autoMotionModeVehicle => 'Vehicle';

  @override
  String get autoMotionAggregates => 'Period aggregates';

  @override
  String get autoMotionLast7Days => 'Last 7 days';

  @override
  String get autoMotionLast30Days => 'Last 30 days';

  @override
  String autoMotionDaysRecorded(int count) {
    return '$count days recorded';
  }

  @override
  String get autoMotionViewDetails => 'View details';

  @override
  String get autoMotionRoute => 'Today\'s route';

  @override
  String get autoMotionRouteEmpty =>
      'No route recorded yet — turn on tracking and drive or walk to see it drawn here.';

  @override
  String get routeMapAttribution => '© OpenStreetMap contributors';

  @override
  String get routeMilestonesTitle => 'Route milestones';

  @override
  String get routeMilestonesEmpty =>
      'No timed milestones on this route yet — timed stops appear here as the trip is recorded.';

  @override
  String get milestoneTripStart => 'Trip start';

  @override
  String get milestoneStop => 'Stop';

  @override
  String get milestoneTripEnd => 'Trip end';

  @override
  String get autoMotionEvents => 'Driving events';

  @override
  String get autoMotionEventsEmpty =>
      'No harsh maneuvers detected on this trip.';

  @override
  String autoMotionEventsMore(int count) {
    return '$count more';
  }

  @override
  String get harshAcceleration => 'Harsh acceleration';

  @override
  String get harshBraking => 'Hard braking';

  @override
  String get sharpTurn => 'Sharp turn';

  @override
  String get speedBump => 'Speed bump';

  @override
  String get pothole => 'Pothole';

  @override
  String get mps2Unit => 'm/s²';

  @override
  String get autoMotionEventMarkers => 'Event markers on route';

  @override
  String get motionSummaryTitle => 'Trip driving score';

  @override
  String motionSummaryScore(int score) {
    return '$score / 100';
  }

  @override
  String motionSummaryEvents(int count) {
    return '$count events';
  }

  @override
  String get motionSummaryClean => 'Clean trip — no harsh maneuvers.';

  @override
  String get motionSummaryExpand => 'Show motion summary';

  @override
  String get motionSummaryCollapse => 'Hide motion summary';

  @override
  String get scoreExcellent => 'Excellent';

  @override
  String get scoreGood => 'Good';

  @override
  String get scoreFair => 'Fair';

  @override
  String get scorePoor => 'Poor';

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
  String get shareViaWhatsApp => 'Send via WhatsApp';

  @override
  String get searchContact => 'Search Contact';

  @override
  String get proposeManagerUpdateTitle => 'Propose Manager Update';

  @override
  String get proposeManagerUpdate => 'Propose Manager Update';

  @override
  String get updateProposalSubmitted => 'Update proposal submitted';

  @override
  String get managerName => 'Manager Name';

  @override
  String get managerPhone => 'Manager Phone';

  @override
  String get confirm => 'Confirm';

  @override
  String get currentUserName => 'Current User';

  @override
  String get shareViaSystem => 'Share via system';

  @override
  String get sendToDriver => 'Send to driver';

  @override
  String get submitStationUpdate =>
      'Submit Station Update / إرسال تعديل المحطة';

  @override
  String get submittingUpdate => 'Submitting update...';

  @override
  String get updateSuccess => 'Update proposal submitted successfully';

  @override
  String get updateFailed => 'Failed to submit update proposal';

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
  String get vaultProtectionTitle => 'Vault protection';

  @override
  String get vaultProtectionSubtitle =>
      'How long the Hidden Vault stays unlocked, and whether it locks when the screen does.';

  @override
  String get sessionTimeoutTitle => 'Auto-lock after inactivity';

  @override
  String get sessionTimeoutSubtitle =>
      'The vault re-locks after this long without use.';

  @override
  String sessionTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get lockOnDeviceLockTitle => 'Lock when the device locks';

  @override
  String get lockOnDeviceLockSubtitle =>
      'Ends the vault session as soon as the screen locks, with no grace period.';

  @override
  String get vaultDimmingNotice =>
      'For your privacy, the screen dims while the device is resting unattended.';

  @override
  String get sessionTimeoutUpdated => 'Auto-lock timeout updated';

  @override
  String get lockOnDeviceLockUpdated => 'Device-lock protection updated';

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
  String get insightMotionSummaryTitle => 'Your motion today';

  @override
  String insightMotionSummaryBody(
    String walking,
    String running,
    String vehicle,
  ) {
    return 'You covered $walking walking and $running running, plus $vehicle by vehicle.';
  }

  @override
  String insightMotionSummaryBodySteps(
    String walking,
    String running,
    String vehicle,
    int steps,
  ) {
    return 'You covered $walking walking and $running running, plus $vehicle by vehicle, on $steps counted steps.';
  }

  @override
  String get insightActionSyncNow => 'Sync now';

  @override
  String get coordinateDetails => 'Latitude & longitude';

  @override
  String get aiSmartPasteTooltip => 'AI Smart Paste';

  @override
  String get categoryWork => 'Work';

  @override
  String get categoryHome => 'Home';

  @override
  String get categorySchool => 'School';

  @override
  String get categoryPersonal => 'Personal';

  @override
  String get plusCodeDetected => 'Plus Code detected in the clipboard';

  @override
  String get plusCodeImport => 'Import';

  @override
  String get plusCodeInvalid => 'Enter a valid Plus Code';

  @override
  String get plusCodeOrCoordinatesRequired =>
      'Enter a Plus Code, or latitude and longitude';

  @override
  String get plusCodeShortNeedsReference =>
      'This short Plus Code needs a nearby location. Enable GPS, or paste the full code.';

  @override
  String foundPlace(String name) {
    return 'Found: $name';
  }

  @override
  String get autoFillNameNotes => 'Auto-fill Name & Notes';

  @override
  String get dismissSuggestion => 'Dismiss suggestion';

  @override
  String get suggestionTitle => 'Nearby place';

  @override
  String get routePreview => 'Route preview';

  @override
  String get currentLocationMarker => 'Current location';

  @override
  String get savedLocationMarker => 'Saved place';

  @override
  String distanceAway(String distance) {
    return '$distance away';
  }

  @override
  String get accountAndBackup => 'Account & Cloud Backup';

  @override
  String get sectionLocationTracking => 'Location & Tracking';

  @override
  String get aboutTitle => 'About MapNote';

  @override
  String get bousla => 'Compass';

  @override
  String get smartAutoMotionTitle => 'Enable Smart AutoMotion';

  @override
  String get smartAutoMotionSubtitle =>
      'Fuses GPS and motion sensors to track distance & speed while saving battery';

  @override
  String get compassTitle => 'Compass';

  @override
  String get mapPreview => 'Map preview';

  @override
  String get enableLocationForRoute => 'Turn on location to see your distance';

  @override
  String get qiblaUnavailable => 'No GPS fix available';

  @override
  String get qiblaDirectionAbbrev => 'e.g. SE';

  @override
  String get qiblaAligned => 'Aligned with Qibla';

  @override
  String get compassNorth => 'North';

  @override
  String get headingInstruction => 'Adjust phone direction to see Qibla';

  @override
  String get compassCalculating => 'Calculating...';

  @override
  String get savedPlacesVault => 'Encrypted Vault';

  @override
  String get savedPlacesVaultSubtitle =>
      'Biometric-protected places, encrypted with AES-256';

  @override
  String get savedPlacesVaultLocked => 'Vault locked';

  @override
  String get savedPlacesVaultLockedMessage =>
      'Verify your identity to read the places kept in the encrypted vault.';

  @override
  String get savedPlacesVaultUnlock => 'Unlock vault';

  @override
  String get savedPlacesVaultEmpty => 'No encrypted places yet';

  @override
  String get savedPlacesVaultEmptyMessage =>
      'Move a saved place into the vault to protect it behind your device lock.';

  @override
  String get savedPlacesVaultUnlocked => 'Vault unlocked';

  @override
  String get savedPlacesVaultUnavailable =>
      'This device can\'t verify your identity';

  @override
  String get moveToEncryptedVault => 'Move to encrypted vault';

  @override
  String get moveToEncryptedVaultDone => 'Moved to the encrypted vault';

  @override
  String get restoreFromEncryptedVault => 'Move back to saved places';

  @override
  String get restoreFromEncryptedVaultDone => 'Moved back to saved places';

  @override
  String get unlockToOpenSavedPlacesVault =>
      'Verify to open the encrypted vault';

  @override
  String get unlockToMoveToEncryptedVault =>
      'Verify to move the place into the encrypted vault';

  @override
  String get enterPin => 'Enter PIN';

  @override
  String get vaultPinLabel => 'PIN';

  @override
  String get vaultPinConfirmLabel => 'Confirm PIN';

  @override
  String get vaultPinHint =>
      'Use 4 to 12 digits. The PIN unlocks the encrypted vault when biometrics are not available.';

  @override
  String get vaultPinTooShort => 'Use at least 4 digits.';

  @override
  String get vaultPinMismatch => 'The two PINs don\'t match.';

  @override
  String get vaultPinRejected => 'Wrong PIN.';

  @override
  String get vaultPinLockedOut =>
      'Too many attempts. Try again in a few minutes.';

  @override
  String get vaultPinSet => 'Vault PIN set.';

  @override
  String get vaultPinChanged => 'Vault PIN changed.';

  @override
  String get vaultPinRemoved => 'Vault PIN removed.';

  @override
  String get vaultPinNotSet => 'No PIN set';

  @override
  String get usePinInstead => 'Use PIN';

  @override
  String get changeVaultPin => 'Vault PIN';

  @override
  String get changeVaultPinSubtitle =>
      'Set a PIN to open the encrypted vault when biometrics are not available.';

  @override
  String get removeVaultPin => 'Remove PIN';

  @override
  String get biometricVaultEnabled => 'Biometric vault';

  @override
  String get biometricVaultEnabledSubtitle =>
      'Keep places in an AES-256 encrypted vault, behind your biometrics or a PIN.';

  @override
  String get suggestedPlaceLinks => 'Places you may want to link';

  @override
  String get suggestedPlaceLinksSubtitle => 'Based on today\'s stops';

  @override
  String get suggestedPlaceOpenAction => 'Open';

  @override
  String get suggestedPlaceSaveAction => 'Save';

  @override
  String suggestedPlaceStopDetails(int minutes) {
    return 'Stopped for $minutes min';
  }

  @override
  String suggestedPlaceNearSaved(String name, int distance) {
    return '\"$name\" is $distance m away';
  }

  @override
  String get suggestedPlaceNoMatch => 'No saved place nearby';

  @override
  String suggestedPlaceLinked(String name) {
    return 'Linked to $name';
  }

  @override
  String get suggestedPlaceSaved => 'Saved to your places';

  @override
  String get suggestedPlaceLinkFailed => 'Couldn\'t link the place';

  @override
  String get motionHistoryTitle => 'Motion history';

  @override
  String get motionHistorySubtitle =>
      'Trips, walks, runs and stops recorded for this day';

  @override
  String get motionTypeDrive => 'Drive';

  @override
  String get motionTypeWalk => 'Walk';

  @override
  String get motionTypeRun => 'Run';

  @override
  String get motionTypeStopover => 'Stopover';

  @override
  String get motionHistoryToday => 'Today';

  @override
  String get motionHistoryYesterday => 'Yesterday';

  @override
  String get motionHistoryPickDate => 'Pick a day';

  @override
  String get motionHistoryPreviousDay => 'Previous day';

  @override
  String get motionHistoryNextDay => 'Next day';

  @override
  String get motionHistoryViewTimeline => 'Timeline';

  @override
  String get motionHistoryViewMap => 'Map';

  @override
  String get motionHistoryTotalDistance => 'Distance';

  @override
  String get motionHistoryDriveTime => 'Drive time';

  @override
  String get motionHistoryStopoverTime => 'Idle time';

  @override
  String get motionHistoryEmptyTitle => 'No motion recorded';

  @override
  String get motionHistoryEmptyBody =>
      'Nothing was recorded for this day. Turn on AutoMotion, then drive or walk to build a timeline.';

  @override
  String get motionHistoryNoRoute => 'No route to draw for this day.';

  @override
  String get motionHistoryShowOnMap => 'Show on map';

  @override
  String motionHistoryDriveStats(String distance, String duration) {
    return '$distance km · $duration';
  }

  @override
  String motionHistoryAverageSpeed(String speed) {
    return 'Avg $speed km/h';
  }

  @override
  String motionHistoryStepStats(String distance, int steps) {
    return '$distance m · $steps steps';
  }

  @override
  String get motionHistorySteps => 'Steps';

  @override
  String get motionHistoryModeBreakdownHint =>
      'Walk and run distances are measured by the step counter; vehicle distance comes from GPS.';

  @override
  String motionHistoryStopoverStats(String duration) {
    return 'Stopped for $duration';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get durationZero => '0 min';

  @override
  String get durationLessThanMinute => 'less than a minute';

  @override
  String get stationManagersTitle => 'Station manager';

  @override
  String get callManager => 'Call manager';

  @override
  String get messageManagerOnWhatsApp => 'Message on WhatsApp';

  @override
  String get managerPhoneMissing => 'No phone number on file yet';

  @override
  String get managerContactUnavailable =>
      'No app on this device can handle that';

  @override
  String managerWhatsAppMessage(String name, String station) {
    return 'Hello $name, regarding $station.';
  }

  @override
  String get adminApprovalTitle => 'Admin Approval';

  @override
  String get noPendingUpdates => 'No pending updates';

  @override
  String proposalForStation(Object stationId) {
    return 'Proposal for Station $stationId';
  }

  @override
  String currentManager(Object name) {
    return 'Current Manager: $name';
  }

  @override
  String currentManagerPhone(Object phone) {
    return 'Phone: $phone';
  }

  @override
  String proposedManager(Object name) {
    return 'Proposed Manager: $name';
  }

  @override
  String proposedManagerPhone(Object phone) {
    return 'Phone: $phone';
  }

  @override
  String submittedBy(Object name) {
    return 'Submitted by: $name';
  }

  @override
  String submittedAt(Object date) {
    return 'Submitted on: $date';
  }

  @override
  String get adminPinRequired => 'Admin PIN required';

  @override
  String get pin => 'PIN';

  @override
  String get incorrectPin => 'Incorrect PIN';

  @override
  String get incorrectPinAttempt =>
      'The PIN you entered is incorrect. Please try again.';

  @override
  String get logout => 'Log out';

  @override
  String get wrongPin => 'Wrong PIN.';

  @override
  String get unlock => 'Unlock';

  @override
  String get unknownManager => 'No manager';

  @override
  String get unknownPhone => 'No phone';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get resetPin => 'Reset PIN';

  @override
  String get incompleteProposal => 'Incomplete proposal';

  @override
  String get dismissProposal => 'Dismiss';

  @override
  String get proposalDismissed => 'Proposal dismissed';

  @override
  String get dismissFailed => 'Failed to dismiss proposal';

  @override
  String get incompleteNewStation => 'Incomplete new station proposal';

  @override
  String get missingStation => 'Missing station reference';

  @override
  String get proposalApproved => 'Proposal approved successfully';

  @override
  String get proposalRejected => 'Proposal rejected';

  @override
  String get approveFailed => 'Failed to approve proposal';

  @override
  String get rejectFailed => 'Failed to reject proposal';

  @override
  String get newStationApproved => 'New station approved successfully';

  @override
  String get adminPinHint => '1991';

  @override
  String newStationTitle(String name) {
    return 'New station: $name';
  }

  @override
  String proposalIdLabel(String id) {
    return 'Proposal ID: $id';
  }

  @override
  String proposalRole(String role) {
    return 'Role: $role';
  }

  @override
  String proposalLocation(String lat, String lng) {
    return 'Location: $lat, $lng';
  }

  @override
  String proposalCity(String city) {
    return 'City: $city';
  }

  @override
  String get unknownStation => 'Unknown station';

  @override
  String get roleManager => 'Manager';

  @override
  String get roleSupervisor => 'Supervisor';

  @override
  String get roleSupport => 'Support';

  @override
  String get roleStaff => 'Staff';

  @override
  String workInsightsStations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stations',
      one: '1 station',
      zero: 'No stations',
    );
    return '$_temp0';
  }

  @override
  String workInsightsManagers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count manager contacts on file',
      one: '1 manager contact on file',
      zero: 'No manager contacts on file',
    );
    return '$_temp0';
  }

  @override
  String workInsightsMissingContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stations missing a phone number',
      one: '1 station missing a phone number',
      zero: 'All stations have a phone number',
    );
    return '$_temp0';
  }

  @override
  String workInsightsWorkTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count #work-tagged places',
      one: '1 #work-tagged place',
      zero: 'No #work-tagged places',
    );
    return '$_temp0';
  }

  @override
  String get workInsightsTip =>
      'Tag a place with #work in its name or notes to track operations. Submit contact updates from the station screen for admin approval.';

  @override
  String get workInsightsNothingMissing =>
      'Every station has a contact on file.';

  @override
  String workInsightsPendingApprovals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending admin approvals',
      one: '1 pending admin approval',
      zero: 'No pending admin approvals',
    );
    return '$_temp0';
  }

  @override
  String workInsightsStationsMissingContactsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stations missing manager contact details',
      one: '1 station missing manager contact details',
      zero: 'No stations missing manager details',
    );
    return '$_temp0';
  }
}
