import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'MapNote'**
  String get appTitle;

  /// No description provided for @placesTitle.
  ///
  /// In en, this message translates to:
  /// **'My Places'**
  String get placesTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or notes'**
  String get searchHint;

  /// No description provided for @addPlace.
  ///
  /// In en, this message translates to:
  /// **'Save current location'**
  String get addPlace;

  /// No description provided for @addPlaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Location'**
  String get addPlaceTitle;

  /// No description provided for @editPlaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Location'**
  String get editPlaceTitle;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. John\'s House'**
  String get fieldNameHint;

  /// No description provided for @fieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get fieldNotes;

  /// No description provided for @fieldNotesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Gate 3, second floor'**
  String get fieldNotesHint;

  /// No description provided for @locationCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Coordinates'**
  String get locationCoordinates;

  /// No description provided for @latitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitude;

  /// No description provided for @longitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitude;

  /// No description provided for @currentLocation.
  ///
  /// In en, this message translates to:
  /// **'Current location'**
  String get currentLocation;

  /// No description provided for @fetchingLocation.
  ///
  /// In en, this message translates to:
  /// **'Getting your location…'**
  String get fetchingLocation;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get nameRequired;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste location from clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @clipboardNoLocation.
  ///
  /// In en, this message translates to:
  /// **'No coordinates found in the clipboard'**
  String get clipboardNoLocation;

  /// No description provided for @clipboardPasted.
  ///
  /// In en, this message translates to:
  /// **'Location pasted from clipboard'**
  String get clipboardPasted;

  /// No description provided for @locationModeCurrentGps.
  ///
  /// In en, this message translates to:
  /// **'Current GPS location'**
  String get locationModeCurrentGps;

  /// No description provided for @locationModeManual.
  ///
  /// In en, this message translates to:
  /// **'Custom coordinates'**
  String get locationModeManual;

  /// No description provided for @customCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Custom coordinates'**
  String get customCoordinates;

  /// No description provided for @coordinateRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a value'**
  String get coordinateRequired;

  /// No description provided for @coordinateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get coordinateInvalid;

  /// No description provided for @latitudeRange.
  ///
  /// In en, this message translates to:
  /// **'Latitude must be between -90 and 90'**
  String get latitudeRange;

  /// No description provided for @longitudeRange.
  ///
  /// In en, this message translates to:
  /// **'Longitude must be between -180 and 180'**
  String get longitudeRange;

  /// No description provided for @plusCode.
  ///
  /// In en, this message translates to:
  /// **'Plus Code'**
  String get plusCode;

  /// No description provided for @plusCodeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 8FVC9G8F+6W'**
  String get plusCodeHint;

  /// No description provided for @shareNoLocation.
  ///
  /// In en, this message translates to:
  /// **'No location found in the shared text'**
  String get shareNoLocation;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @navigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get navigate;

  /// No description provided for @openInGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Google Maps'**
  String get openInGoogleMaps;

  /// No description provided for @openInWaze.
  ///
  /// In en, this message translates to:
  /// **'Open in Waze'**
  String get openInWaze;

  /// No description provided for @copyCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Copy coordinates'**
  String get copyCoordinates;

  /// No description provided for @coordinatesCopied.
  ///
  /// In en, this message translates to:
  /// **'Coordinates copied to clipboard'**
  String get coordinatesCopied;

  /// No description provided for @placeSaved.
  ///
  /// In en, this message translates to:
  /// **'Location saved'**
  String get placeSaved;

  /// No description provided for @placeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Location deleted'**
  String get placeDeleted;

  /// No description provided for @placeDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Place details'**
  String get placeDetailsTitle;

  /// No description provided for @deletePlaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete place?'**
  String get deletePlaceTitle;

  /// No description provided for @deletePlaceMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be removed from this device and from your next backup.'**
  String deletePlaceMessage(String name);

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Saved {date}'**
  String createdAt(String date);

  /// No description provided for @emptyPlacesTitle.
  ///
  /// In en, this message translates to:
  /// **'No saved places yet'**
  String get emptyPlacesTitle;

  /// No description provided for @emptyPlacesMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap + in the top bar to save your current location.'**
  String get emptyPlacesMessage;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No places match your search.'**
  String get noSearchResults;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get sectionLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select language'**
  String get selectLanguage;

  /// No description provided for @preferredNavApp.
  ///
  /// In en, this message translates to:
  /// **'Preferred navigation app'**
  String get preferredNavApp;

  /// No description provided for @preferredNavAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which app opens when you tap Navigate'**
  String get preferredNavAppSubtitle;

  /// No description provided for @navAppSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get navAppSystem;

  /// No description provided for @navAppGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Google Maps'**
  String get navAppGoogleMaps;

  /// No description provided for @navAppWaze.
  ///
  /// In en, this message translates to:
  /// **'Waze'**
  String get navAppWaze;

  /// No description provided for @sectionLocationServices.
  ///
  /// In en, this message translates to:
  /// **'Location services'**
  String get sectionLocationServices;

  /// No description provided for @sectionPreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get sectionPreferences;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @fontScale.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontScale;

  /// No description provided for @fontScaleSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontScaleSmall;

  /// No description provided for @fontScaleStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fontScaleStandard;

  /// No description provided for @fontScaleLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontScaleLarge;

  /// No description provided for @fontScaleExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra large'**
  String get fontScaleExtraLarge;

  /// No description provided for @hapticFeedback.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get hapticFeedback;

  /// No description provided for @uiDensityCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact UI density'**
  String get uiDensityCompact;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @sectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get sectionAccount;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String signedInAs(String email);

  /// No description provided for @notSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get notSignedIn;

  /// No description provided for @syncSignInRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google to sync'**
  String get syncSignInRequired;

  /// No description provided for @sectionSync.
  ///
  /// In en, this message translates to:
  /// **'Sync & backup'**
  String get sectionSync;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncInProgress.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncInProgress;

  /// No description provided for @syncComplete.
  ///
  /// In en, this message translates to:
  /// **'Sync complete'**
  String get syncComplete;

  /// No description provided for @syncSkipped.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync'**
  String get syncSkipped;

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(String error);

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed: {error}'**
  String signInFailed(String error);

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced: {date}'**
  String lastSynced(String date);

  /// No description provided for @neverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get neverSynced;

  /// No description provided for @localOverridesCloud.
  ///
  /// In en, this message translates to:
  /// **'Your device data always overwrites the Google Drive backup.'**
  String get localOverridesCloud;

  /// No description provided for @restoreFromDrive.
  ///
  /// In en, this message translates to:
  /// **'Restore from Google Drive'**
  String get restoreFromDrive;

  /// No description provided for @restoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from Google Drive?'**
  String get restoreConfirmTitle;

  /// No description provided for @restoreConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This replaces all places on this device with the backup from your Google Drive.'**
  String get restoreConfirmMessage;

  /// No description provided for @restoreComplete.
  ///
  /// In en, this message translates to:
  /// **'Restore complete'**
  String get restoreComplete;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @locationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Location permission needed'**
  String get locationPermissionTitle;

  /// No description provided for @locationPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'MapNote needs access to your location to save places.'**
  String get locationPermissionMessage;

  /// No description provided for @locationServicesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Please enable location services on your device.'**
  String get locationServicesDisabled;

  /// No description provided for @locationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not determine your location. Please try again.'**
  String get locationUnavailable;

  /// No description provided for @openAppSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openAppSettings;

  /// No description provided for @locationStatusGps.
  ///
  /// In en, this message translates to:
  /// **'GPS'**
  String get locationStatusGps;

  /// No description provided for @locationStatusPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission'**
  String get locationStatusPermission;

  /// No description provided for @locationGpsOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get locationGpsOn;

  /// No description provided for @locationGpsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get locationGpsOff;

  /// No description provided for @locationPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get locationPermissionGranted;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get locationPermissionDenied;

  /// No description provided for @locationPermissionDeniedForever.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get locationPermissionDeniedForever;

  /// No description provided for @locationPermissionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not requested'**
  String get locationPermissionUnknown;

  /// No description provided for @manageLocation.
  ///
  /// In en, this message translates to:
  /// **'Manage location'**
  String get manageLocation;

  /// No description provided for @dailyGpsSection.
  ///
  /// In en, this message translates to:
  /// **'Daily GPS tracking'**
  String get dailyGpsSection;

  /// No description provided for @dailyGpsToggle.
  ///
  /// In en, this message translates to:
  /// **'Enable daily GPS tracking'**
  String get dailyGpsToggle;

  /// No description provided for @dailyGpsToggleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Records distance and max speed while the app is open'**
  String get dailyGpsToggleSubtitle;

  /// No description provided for @dailyGpsPermissionHint.
  ///
  /// In en, this message translates to:
  /// **'Location access is needed for tracking. Turn on GPS and allow location access, then re-enable tracking.'**
  String get dailyGpsPermissionHint;

  /// No description provided for @dailyDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance today'**
  String get dailyDistance;

  /// No description provided for @dailyMaxSpeed.
  ///
  /// In en, this message translates to:
  /// **'Max speed'**
  String get dailyMaxSpeed;

  /// No description provided for @dailyTrackingActive.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get dailyTrackingActive;

  /// No description provided for @dailyTrackingPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get dailyTrackingPaused;

  /// No description provided for @dailyGpsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'GPS unavailable — check location settings'**
  String get dailyGpsUnavailable;

  /// No description provided for @kmUnit.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get kmUnit;

  /// No description provided for @kmhUnit.
  ///
  /// In en, this message translates to:
  /// **'km/h'**
  String get kmhUnit;

  /// No description provided for @autoMotionSection.
  ///
  /// In en, this message translates to:
  /// **'AutoMotion'**
  String get autoMotionSection;

  /// No description provided for @autoMotionToggle.
  ///
  /// In en, this message translates to:
  /// **'Enable AutoMotion'**
  String get autoMotionToggle;

  /// No description provided for @autoMotionToggleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically records distance and max speed while the app is open'**
  String get autoMotionToggleSubtitle;

  /// No description provided for @autoMotionPermissionHint.
  ///
  /// In en, this message translates to:
  /// **'Location access is needed for AutoMotion. Turn on GPS and allow location access, then re-enable AutoMotion.'**
  String get autoMotionPermissionHint;

  /// No description provided for @autoMotionDistance.
  ///
  /// In en, this message translates to:
  /// **'Today\'s distance'**
  String get autoMotionDistance;

  /// No description provided for @autoMotionMaxSpeed.
  ///
  /// In en, this message translates to:
  /// **'Max speed today'**
  String get autoMotionMaxSpeed;

  /// No description provided for @autoMotionActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get autoMotionActive;

  /// No description provided for @autoMotionPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get autoMotionPaused;

  /// No description provided for @autoMotionDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'AutoMotion Dashboard'**
  String get autoMotionDashboardTitle;

  /// No description provided for @autoMotionDriverMode.
  ///
  /// In en, this message translates to:
  /// **'Driver mode'**
  String get autoMotionDriverMode;

  /// No description provided for @autoMotionCurrentSpeed.
  ///
  /// In en, this message translates to:
  /// **'Current speed'**
  String get autoMotionCurrentSpeed;

  /// No description provided for @autoMotionToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get autoMotionToday;

  /// No description provided for @autoMotionHistory.
  ///
  /// In en, this message translates to:
  /// **'Trip history'**
  String get autoMotionHistory;

  /// No description provided for @autoMotionHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No motion recorded yet'**
  String get autoMotionHistoryEmpty;

  /// No description provided for @autoMotionHistoryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Days with recorded motion will appear here.'**
  String get autoMotionHistoryEmptyHint;

  /// No description provided for @autoMotionActivityBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Activity breakdown'**
  String get autoMotionActivityBreakdown;

  /// No description provided for @autoMotionActivityBreakdownToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s activity'**
  String get autoMotionActivityBreakdownToday;

  /// No description provided for @autoMotionActivityBreakdownEmpty.
  ///
  /// In en, this message translates to:
  /// **'No mode data recorded yet.'**
  String get autoMotionActivityBreakdownEmpty;

  /// No description provided for @autoMotionModeWalk.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get autoMotionModeWalk;

  /// No description provided for @autoMotionModeRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get autoMotionModeRun;

  /// No description provided for @autoMotionModeVehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get autoMotionModeVehicle;

  /// No description provided for @autoMotionAggregates.
  ///
  /// In en, this message translates to:
  /// **'Period aggregates'**
  String get autoMotionAggregates;

  /// No description provided for @autoMotionLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get autoMotionLast7Days;

  /// No description provided for @autoMotionLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get autoMotionLast30Days;

  /// No description provided for @autoMotionDaysRecorded.
  ///
  /// In en, this message translates to:
  /// **'{count} days recorded'**
  String autoMotionDaysRecorded(int count);

  /// No description provided for @autoMotionCustomRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get autoMotionCustomRange;

  /// No description provided for @customDateRange.
  ///
  /// In en, this message translates to:
  /// **'Custom date range'**
  String get customDateRange;

  /// No description provided for @exportMotionData.
  ///
  /// In en, this message translates to:
  /// **'Export motion data'**
  String get exportMotionData;

  /// No description provided for @exportFormatCsv.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get exportFormatCsv;

  /// No description provided for @exportFormatJson.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get exportFormatJson;

  /// No description provided for @zeroCoordinatesNotice.
  ///
  /// In en, this message translates to:
  /// **'Export contains no location coordinates.'**
  String get zeroCoordinatesNotice;

  /// No description provided for @tileCacheSize.
  ///
  /// In en, this message translates to:
  /// **'Tile cache: {size}'**
  String tileCacheSize(String size);

  /// No description provided for @clearTileCache.
  ///
  /// In en, this message translates to:
  /// **'Clear tile cache'**
  String get clearTileCache;

  /// No description provided for @preloadOfflineMaps.
  ///
  /// In en, this message translates to:
  /// **'Pre-load saved places maps'**
  String get preloadOfflineMaps;

  /// No description provided for @offlineMapDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Offline maps downloaded'**
  String get offlineMapDownloaded;

  /// No description provided for @smartBatterySaver.
  ///
  /// In en, this message translates to:
  /// **'Smart battery saver'**
  String get smartBatterySaver;

  /// No description provided for @smartBatterySaverDesc.
  ///
  /// In en, this message translates to:
  /// **'Reduce GPS polling when stationary.'**
  String get smartBatterySaverDesc;

  /// No description provided for @stationaryModeActive.
  ///
  /// In en, this message translates to:
  /// **'Stationary mode active'**
  String get stationaryModeActive;

  /// No description provided for @autoMotionSelectRange.
  ///
  /// In en, this message translates to:
  /// **'Select date range'**
  String get autoMotionSelectRange;

  /// No description provided for @autoMotionExport.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get autoMotionExport;

  /// No description provided for @autoMotionExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export as CSV'**
  String get autoMotionExportCsv;

  /// No description provided for @autoMotionExportJson.
  ///
  /// In en, this message translates to:
  /// **'Export as JSON'**
  String get autoMotionExportJson;

  /// No description provided for @autoMotionExportCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get autoMotionExportCopy;

  /// No description provided for @autoMotionExportCopied.
  ///
  /// In en, this message translates to:
  /// **'Report copied to clipboard'**
  String get autoMotionExportCopied;

  /// No description provided for @autoMotionExportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recorded days in this range.'**
  String get autoMotionExportEmpty;

  /// No description provided for @autoMotionRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'{from} – {to}'**
  String autoMotionRangeLabel(String from, String to);

  /// No description provided for @autoMotionViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get autoMotionViewDetails;

  /// No description provided for @autoMotionRoute.
  ///
  /// In en, this message translates to:
  /// **'Today\'s route'**
  String get autoMotionRoute;

  /// No description provided for @autoMotionRouteEmpty.
  ///
  /// In en, this message translates to:
  /// **'No route recorded yet — turn on tracking and drive or walk to see it drawn here.'**
  String get autoMotionRouteEmpty;

  /// No description provided for @routeMapAttribution.
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap contributors'**
  String get routeMapAttribution;

  /// No description provided for @routeMilestonesTitle.
  ///
  /// In en, this message translates to:
  /// **'Route milestones'**
  String get routeMilestonesTitle;

  /// No description provided for @routeMilestonesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No timed milestones on this route yet — timed stops appear here as the trip is recorded.'**
  String get routeMilestonesEmpty;

  /// No description provided for @milestoneTripStart.
  ///
  /// In en, this message translates to:
  /// **'Trip start'**
  String get milestoneTripStart;

  /// No description provided for @milestoneStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get milestoneStop;

  /// No description provided for @milestoneTripEnd.
  ///
  /// In en, this message translates to:
  /// **'Trip end'**
  String get milestoneTripEnd;

  /// No description provided for @autoMotionEvents.
  ///
  /// In en, this message translates to:
  /// **'Driving events'**
  String get autoMotionEvents;

  /// No description provided for @autoMotionEventsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No harsh maneuvers detected on this trip.'**
  String get autoMotionEventsEmpty;

  /// No description provided for @autoMotionEventsMore.
  ///
  /// In en, this message translates to:
  /// **'{count} more'**
  String autoMotionEventsMore(int count);

  /// No description provided for @harshAcceleration.
  ///
  /// In en, this message translates to:
  /// **'Harsh acceleration'**
  String get harshAcceleration;

  /// No description provided for @harshBraking.
  ///
  /// In en, this message translates to:
  /// **'Hard braking'**
  String get harshBraking;

  /// No description provided for @sharpTurn.
  ///
  /// In en, this message translates to:
  /// **'Sharp turn'**
  String get sharpTurn;

  /// No description provided for @speedBump.
  ///
  /// In en, this message translates to:
  /// **'Speed bump'**
  String get speedBump;

  /// No description provided for @pothole.
  ///
  /// In en, this message translates to:
  /// **'Pothole'**
  String get pothole;

  /// No description provided for @mps2Unit.
  ///
  /// In en, this message translates to:
  /// **'m/s²'**
  String get mps2Unit;

  /// No description provided for @autoMotionEventMarkers.
  ///
  /// In en, this message translates to:
  /// **'Event markers on route'**
  String get autoMotionEventMarkers;

  /// No description provided for @motionSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip driving score'**
  String get motionSummaryTitle;

  /// No description provided for @motionSummaryScore.
  ///
  /// In en, this message translates to:
  /// **'{score} / 100'**
  String motionSummaryScore(int score);

  /// No description provided for @motionSummaryEvents.
  ///
  /// In en, this message translates to:
  /// **'{count} events'**
  String motionSummaryEvents(int count);

  /// No description provided for @motionSummaryClean.
  ///
  /// In en, this message translates to:
  /// **'Clean trip — no harsh maneuvers.'**
  String get motionSummaryClean;

  /// No description provided for @motionSummaryExpand.
  ///
  /// In en, this message translates to:
  /// **'Show motion summary'**
  String get motionSummaryExpand;

  /// No description provided for @motionSummaryCollapse.
  ///
  /// In en, this message translates to:
  /// **'Hide motion summary'**
  String get motionSummaryCollapse;

  /// No description provided for @scoreExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get scoreExcellent;

  /// No description provided for @scoreGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get scoreGood;

  /// No description provided for @scoreFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get scoreFair;

  /// No description provided for @scorePoor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get scorePoor;

  /// No description provided for @locationChipServiceOff.
  ///
  /// In en, this message translates to:
  /// **'Location off — tap to enable'**
  String get locationChipServiceOff;

  /// No description provided for @locationChipPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission needed — tap to allow'**
  String get locationChipPermissionDenied;

  /// No description provided for @locationChipDeniedForever.
  ///
  /// In en, this message translates to:
  /// **'Location blocked — tap to open settings'**
  String get locationChipDeniedForever;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'MapNote saves your favourite places offline and syncs them to your private Google Drive. Navigation opens in the maps app you already use.'**
  String get aboutDescription;

  /// No description provided for @addLocation.
  ///
  /// In en, this message translates to:
  /// **'Add location'**
  String get addLocation;

  /// No description provided for @addCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Current Location'**
  String get addCurrentLocation;

  /// No description provided for @addCurrentLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use your device\'s GPS position'**
  String get addCurrentLocationSubtitle;

  /// No description provided for @aiSmartPaste.
  ///
  /// In en, this message translates to:
  /// **'AI Smart Paste'**
  String get aiSmartPaste;

  /// No description provided for @aiSmartPasteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Paste a Google Maps link or coordinates'**
  String get aiSmartPasteSubtitle;

  /// No description provided for @enterCoordinates.
  ///
  /// In en, this message translates to:
  /// **'Enter Coordinates'**
  String get enterCoordinates;

  /// No description provided for @enterCoordinatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type latitude and longitude manually'**
  String get enterCoordinatesSubtitle;

  /// No description provided for @pinnedLabel.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinnedLabel;

  /// No description provided for @lockedLabel.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get lockedLabel;

  /// No description provided for @pinToTop.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get pinToTop;

  /// No description provided for @unpinFromTop.
  ///
  /// In en, this message translates to:
  /// **'Unpin from top'**
  String get unpinFromTop;

  /// No description provided for @pinnedToTop.
  ///
  /// In en, this message translates to:
  /// **'Pinned to top'**
  String get pinnedToTop;

  /// No description provided for @unpinnedFromTop.
  ///
  /// In en, this message translates to:
  /// **'Removed from top'**
  String get unpinnedFromTop;

  /// No description provided for @shareQr.
  ///
  /// In en, this message translates to:
  /// **'Share QR code'**
  String get shareQr;

  /// No description provided for @addToHomeScreen.
  ///
  /// In en, this message translates to:
  /// **'Add shortcut to home screen'**
  String get addToHomeScreen;

  /// No description provided for @lockLocation.
  ///
  /// In en, this message translates to:
  /// **'Lock location'**
  String get lockLocation;

  /// No description provided for @unlockLocation.
  ///
  /// In en, this message translates to:
  /// **'Unlock location'**
  String get unlockLocation;

  /// No description provided for @locationLocked.
  ///
  /// In en, this message translates to:
  /// **'Location locked'**
  String get locationLocked;

  /// No description provided for @locationUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Location unlocked'**
  String get locationUnlocked;

  /// No description provided for @hideLocation.
  ///
  /// In en, this message translates to:
  /// **'Hide location'**
  String get hideLocation;

  /// No description provided for @unhideLocation.
  ///
  /// In en, this message translates to:
  /// **'Unhide location'**
  String get unhideLocation;

  /// No description provided for @locationHidden.
  ///
  /// In en, this message translates to:
  /// **'Location hidden'**
  String get locationHidden;

  /// No description provided for @locationUnhidden.
  ///
  /// In en, this message translates to:
  /// **'Location unhidden'**
  String get locationUnhidden;

  /// No description provided for @unlockToContinue.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to continue'**
  String get unlockToContinue;

  /// No description provided for @unlockToNavigate.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to navigate'**
  String get unlockToNavigate;

  /// No description provided for @unlockToEdit.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to edit'**
  String get unlockToEdit;

  /// No description provided for @unlockToUnlock.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to unlock'**
  String get unlockToUnlock;

  /// No description provided for @unlockToShareQr.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to share'**
  String get unlockToShareQr;

  /// No description provided for @unlockToOpenVault.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to open the Hidden Vault'**
  String get unlockToOpenVault;

  /// No description provided for @authenticationFailed.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed'**
  String get authenticationFailed;

  /// No description provided for @biometricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication isn\'t available on this device'**
  String get biometricsUnavailable;

  /// No description provided for @noDeviceSecurityWarning.
  ///
  /// In en, this message translates to:
  /// **'No lock screen or biometrics on this device, so verification was skipped.'**
  String get noDeviceSecurityWarning;

  /// No description provided for @sectionPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & security'**
  String get sectionPrivacy;

  /// No description provided for @hiddenVault.
  ///
  /// In en, this message translates to:
  /// **'Hidden Vault'**
  String get hiddenVault;

  /// No description provided for @hiddenVaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No hidden locations} =1{1 hidden location} other{{count} hidden locations}}'**
  String hiddenVaultSubtitle(int count);

  /// No description provided for @hiddenVaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'No hidden locations'**
  String get hiddenVaultEmpty;

  /// No description provided for @hiddenVaultEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Locations you hide will appear here, protected by your device lock.'**
  String get hiddenVaultEmptyMessage;

  /// No description provided for @vaultProtectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Vault protection'**
  String get vaultProtectionTitle;

  /// No description provided for @vaultProtectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How long the Hidden Vault stays unlocked, and whether it locks when the screen does.'**
  String get vaultProtectionSubtitle;

  /// No description provided for @sessionTimeoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock after inactivity'**
  String get sessionTimeoutTitle;

  /// No description provided for @sessionTimeoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The vault re-locks after this long without use.'**
  String get sessionTimeoutSubtitle;

  /// No description provided for @sessionTimeoutMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute} other{{minutes} minutes}}'**
  String sessionTimeoutMinutes(int minutes);

  /// No description provided for @lockOnDeviceLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock when the device locks'**
  String get lockOnDeviceLockTitle;

  /// No description provided for @lockOnDeviceLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ends the vault session as soon as the screen locks, with no grace period.'**
  String get lockOnDeviceLockSubtitle;

  /// No description provided for @vaultDimmingNotice.
  ///
  /// In en, this message translates to:
  /// **'For your privacy, the screen dims while the device is resting unattended.'**
  String get vaultDimmingNotice;

  /// No description provided for @sessionTimeoutUpdated.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock timeout updated'**
  String get sessionTimeoutUpdated;

  /// No description provided for @lockOnDeviceLockUpdated.
  ///
  /// In en, this message translates to:
  /// **'Device-lock protection updated'**
  String get lockOnDeviceLockUpdated;

  /// No description provided for @qrCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Share via QR code'**
  String get qrCodeTitle;

  /// No description provided for @qrCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Scan to open this location in a maps app'**
  String get qrCodeHint;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopied;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @shortcutRequested.
  ///
  /// In en, this message translates to:
  /// **'Follow the on-screen prompt to add the shortcut'**
  String get shortcutRequested;

  /// No description provided for @shortcutUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Home screen shortcuts aren\'t supported on this device'**
  String get shortcutUnsupported;

  /// No description provided for @shortcutUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the shortcut'**
  String get shortcutUnavailable;

  /// No description provided for @sectionSmartInsights.
  ///
  /// In en, this message translates to:
  /// **'Smart insights'**
  String get sectionSmartInsights;

  /// No description provided for @smartInsightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart Insights'**
  String get smartInsightsTitle;

  /// No description provided for @smartInsightsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh suggestions'**
  String get smartInsightsRefresh;

  /// No description provided for @smartInsightsDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get smartInsightsDismiss;

  /// No description provided for @smartInsightsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Everything looks good — no suggestions right now.'**
  String get smartInsightsEmpty;

  /// No description provided for @smartInsightsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add more places to generate smart insights and suggestions.'**
  String get smartInsightsEmptyHint;

  /// No description provided for @smartInsightsEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Smart Insights'**
  String get smartInsightsEnable;

  /// No description provided for @smartInsightsEnableSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show suggestions on the Home screen'**
  String get smartInsightsEnableSubtitle;

  /// No description provided for @smartInsightsCloudAi.
  ///
  /// In en, this message translates to:
  /// **'Cloud AI suggestions'**
  String get smartInsightsCloudAi;

  /// No description provided for @smartInsightsCloudAiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let Google Gemini add optional tips. Only anonymous counts are sent — never your places, notes or coordinates.'**
  String get smartInsightsCloudAiSubtitle;

  /// No description provided for @insightWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Save your first place'**
  String get insightWelcomeTitle;

  /// No description provided for @insightWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to save where you are right now.'**
  String get insightWelcomeBody;

  /// No description provided for @insightNearbyDuplicatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Group nearby places'**
  String get insightNearbyDuplicatesTitle;

  /// No description provided for @insightNearbyDuplicatesBody.
  ///
  /// In en, this message translates to:
  /// **'{count} saved places are clustered within a few metres of each other. Consider grouping or renaming them.'**
  String insightNearbyDuplicatesBody(int count);

  /// No description provided for @insightUnorganizedTitle.
  ///
  /// In en, this message translates to:
  /// **'Add details to your places'**
  String get insightUnorganizedTitle;

  /// No description provided for @insightUnorganizedBody.
  ///
  /// In en, this message translates to:
  /// **'{count} places have no notes. Add a note so you can recognise them later.'**
  String insightUnorganizedBody(int count);

  /// No description provided for @insightSyncIssuesTitle.
  ///
  /// In en, this message translates to:
  /// **'A sync didn\'t finish'**
  String get insightSyncIssuesTitle;

  /// No description provided for @insightSyncIssuesBody.
  ///
  /// In en, this message translates to:
  /// **'{count} recent syncs didn\'t complete. Check your connection and try again.'**
  String insightSyncIssuesBody(int count);

  /// No description provided for @insightNetworkWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Possible weak network'**
  String get insightNetworkWarningTitle;

  /// No description provided for @insightNetworkWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Sync has failed several times recently. Wait for a stable connection before the next backup.'**
  String get insightNetworkWarningBody;

  /// No description provided for @insightParseIssuesTitle.
  ///
  /// In en, this message translates to:
  /// **'Some locations couldn\'t be read'**
  String get insightParseIssuesTitle;

  /// No description provided for @insightParseIssuesBody.
  ///
  /// In en, this message translates to:
  /// **'{count} pasted locations couldn\'t be parsed. Try pasting the full Google Maps link.'**
  String insightParseIssuesBody(int count);

  /// No description provided for @insightStaleBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up your places'**
  String get insightStaleBackupTitle;

  /// No description provided for @insightStaleBackupBody.
  ///
  /// In en, this message translates to:
  /// **'Your last backup was {days} days ago. Sync now to keep your places safe.'**
  String insightStaleBackupBody(int days);

  /// No description provided for @insightStaleBackupNeverBody.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t backed up yet. Sync now to keep your places safe.'**
  String get insightStaleBackupNeverBody;

  /// No description provided for @insightPinFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Pin your favourites'**
  String get insightPinFavoritesTitle;

  /// No description provided for @insightPinFavoritesBody.
  ///
  /// In en, this message translates to:
  /// **'You have {count} saved places and none pinned. Long-press a place to pin it to the top.'**
  String insightPinFavoritesBody(int count);

  /// No description provided for @insightOptimizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep MapNote tidy'**
  String get insightOptimizationTitle;

  /// No description provided for @insightOptimizationBody.
  ///
  /// In en, this message translates to:
  /// **'A large list loads slower. Review duplicate or unused places and remove what you no longer need.'**
  String get insightOptimizationBody;

  /// No description provided for @insightActionSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get insightActionSyncNow;

  /// No description provided for @coordinateDetails.
  ///
  /// In en, this message translates to:
  /// **'Latitude & longitude'**
  String get coordinateDetails;

  /// No description provided for @aiSmartPasteTooltip.
  ///
  /// In en, this message translates to:
  /// **'AI Smart Paste'**
  String get aiSmartPasteTooltip;

  /// No description provided for @categoryWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get categoryWork;

  /// No description provided for @categoryHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get categoryHome;

  /// No description provided for @categorySchool.
  ///
  /// In en, this message translates to:
  /// **'School'**
  String get categorySchool;

  /// No description provided for @categoryPersonal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get categoryPersonal;

  /// No description provided for @plusCodeDetected.
  ///
  /// In en, this message translates to:
  /// **'Plus Code detected in the clipboard'**
  String get plusCodeDetected;

  /// No description provided for @plusCodeImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get plusCodeImport;

  /// No description provided for @plusCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Plus Code'**
  String get plusCodeInvalid;

  /// No description provided for @plusCodeOrCoordinatesRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a Plus Code, or latitude and longitude'**
  String get plusCodeOrCoordinatesRequired;

  /// No description provided for @plusCodeShortNeedsReference.
  ///
  /// In en, this message translates to:
  /// **'This short Plus Code needs a nearby location. Enable GPS, or paste the full code.'**
  String get plusCodeShortNeedsReference;

  /// No description provided for @foundPlace.
  ///
  /// In en, this message translates to:
  /// **'Found: {name}'**
  String foundPlace(String name);

  /// No description provided for @autoFillNameNotes.
  ///
  /// In en, this message translates to:
  /// **'Auto-fill Name & Notes'**
  String get autoFillNameNotes;

  /// No description provided for @dismissSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Dismiss suggestion'**
  String get dismissSuggestion;

  /// No description provided for @suggestionTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby place'**
  String get suggestionTitle;

  /// No description provided for @routePreview.
  ///
  /// In en, this message translates to:
  /// **'Route preview'**
  String get routePreview;

  /// No description provided for @currentLocationMarker.
  ///
  /// In en, this message translates to:
  /// **'Current location'**
  String get currentLocationMarker;

  /// No description provided for @savedLocationMarker.
  ///
  /// In en, this message translates to:
  /// **'Saved place'**
  String get savedLocationMarker;

  /// No description provided for @distanceAway.
  ///
  /// In en, this message translates to:
  /// **'{distance} away'**
  String distanceAway(String distance);

  /// No description provided for @accountAndBackup.
  ///
  /// In en, this message translates to:
  /// **'Account & Cloud Backup'**
  String get accountAndBackup;

  /// No description provided for @sectionLocationTracking.
  ///
  /// In en, this message translates to:
  /// **'Location & Tracking'**
  String get sectionLocationTracking;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About MapNote'**
  String get aboutTitle;

  /// No description provided for @bousla.
  ///
  /// In en, this message translates to:
  /// **'Compass'**
  String get bousla;

  /// No description provided for @smartAutoMotionTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Smart AutoMotion'**
  String get smartAutoMotionTitle;

  /// No description provided for @smartAutoMotionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fuses GPS and motion sensors to track distance & speed while saving battery'**
  String get smartAutoMotionSubtitle;

  /// No description provided for @compassTitle.
  ///
  /// In en, this message translates to:
  /// **'Compass'**
  String get compassTitle;

  /// No description provided for @mapPreview.
  ///
  /// In en, this message translates to:
  /// **'Map preview'**
  String get mapPreview;

  /// No description provided for @enableLocationForRoute.
  ///
  /// In en, this message translates to:
  /// **'Turn on location to see your distance'**
  String get enableLocationForRoute;

  /// No description provided for @qiblaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No GPS fix available'**
  String get qiblaUnavailable;

  /// No description provided for @qiblaDirectionAbbrev.
  ///
  /// In en, this message translates to:
  /// **'e.g. SE'**
  String get qiblaDirectionAbbrev;

  /// No description provided for @qiblaAligned.
  ///
  /// In en, this message translates to:
  /// **'Aligned with Qibla'**
  String get qiblaAligned;

  /// No description provided for @compassNorth.
  ///
  /// In en, this message translates to:
  /// **'North'**
  String get compassNorth;

  /// No description provided for @headingInstruction.
  ///
  /// In en, this message translates to:
  /// **'Adjust phone direction to see Qibla'**
  String get headingInstruction;

  /// No description provided for @compassCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating...'**
  String get compassCalculating;

  /// No description provided for @savedPlacesVault.
  ///
  /// In en, this message translates to:
  /// **'Encrypted Vault'**
  String get savedPlacesVault;

  /// No description provided for @savedPlacesVaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Biometric-protected places, encrypted with AES-256'**
  String get savedPlacesVaultSubtitle;

  /// No description provided for @savedPlacesVaultLocked.
  ///
  /// In en, this message translates to:
  /// **'Vault locked'**
  String get savedPlacesVaultLocked;

  /// No description provided for @savedPlacesVaultLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity to read the places kept in the encrypted vault.'**
  String get savedPlacesVaultLockedMessage;

  /// No description provided for @savedPlacesVaultUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock vault'**
  String get savedPlacesVaultUnlock;

  /// No description provided for @savedPlacesVaultLock.
  ///
  /// In en, this message translates to:
  /// **'Lock vault'**
  String get savedPlacesVaultLock;

  /// No description provided for @savedPlacesVaultEmpty.
  ///
  /// In en, this message translates to:
  /// **'No encrypted places yet'**
  String get savedPlacesVaultEmpty;

  /// No description provided for @savedPlacesVaultEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Move a saved place into the vault to protect it behind your device lock.'**
  String get savedPlacesVaultEmptyMessage;

  /// No description provided for @savedPlacesVaultUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Vault unlocked'**
  String get savedPlacesVaultUnlocked;

  /// No description provided for @savedPlacesVaultUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This device can\'t verify your identity'**
  String get savedPlacesVaultUnavailable;

  /// No description provided for @moveToEncryptedVault.
  ///
  /// In en, this message translates to:
  /// **'Move to encrypted vault'**
  String get moveToEncryptedVault;

  /// No description provided for @moveToEncryptedVaultDone.
  ///
  /// In en, this message translates to:
  /// **'Moved to the encrypted vault'**
  String get moveToEncryptedVaultDone;

  /// No description provided for @restoreFromEncryptedVault.
  ///
  /// In en, this message translates to:
  /// **'Move back to saved places'**
  String get restoreFromEncryptedVault;

  /// No description provided for @restoreFromEncryptedVaultDone.
  ///
  /// In en, this message translates to:
  /// **'Moved back to saved places'**
  String get restoreFromEncryptedVaultDone;

  /// No description provided for @unlockToOpenSavedPlacesVault.
  ///
  /// In en, this message translates to:
  /// **'Verify to open the encrypted vault'**
  String get unlockToOpenSavedPlacesVault;

  /// No description provided for @unlockToMoveToEncryptedVault.
  ///
  /// In en, this message translates to:
  /// **'Verify to move the place into the encrypted vault'**
  String get unlockToMoveToEncryptedVault;

  /// No description provided for @enterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get enterPin;

  /// No description provided for @vaultPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get vaultPinLabel;

  /// No description provided for @vaultPinConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get vaultPinConfirmLabel;

  /// No description provided for @vaultPinHint.
  ///
  /// In en, this message translates to:
  /// **'Use 4 to 12 digits. The PIN unlocks the encrypted vault when biometrics are not available.'**
  String get vaultPinHint;

  /// No description provided for @vaultPinTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 4 digits.'**
  String get vaultPinTooShort;

  /// No description provided for @vaultPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two PINs don\'t match.'**
  String get vaultPinMismatch;

  /// No description provided for @vaultPinRejected.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN.'**
  String get vaultPinRejected;

  /// No description provided for @vaultPinLockedOut.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in a few minutes.'**
  String get vaultPinLockedOut;

  /// No description provided for @vaultPinSet.
  ///
  /// In en, this message translates to:
  /// **'Vault PIN set.'**
  String get vaultPinSet;

  /// No description provided for @vaultPinChanged.
  ///
  /// In en, this message translates to:
  /// **'Vault PIN changed.'**
  String get vaultPinChanged;

  /// No description provided for @vaultPinRemoved.
  ///
  /// In en, this message translates to:
  /// **'Vault PIN removed.'**
  String get vaultPinRemoved;

  /// No description provided for @vaultPinNotSet.
  ///
  /// In en, this message translates to:
  /// **'No PIN set'**
  String get vaultPinNotSet;

  /// No description provided for @usePinInstead.
  ///
  /// In en, this message translates to:
  /// **'Use PIN'**
  String get usePinInstead;

  /// No description provided for @changeVaultPin.
  ///
  /// In en, this message translates to:
  /// **'Vault PIN'**
  String get changeVaultPin;

  /// No description provided for @changeVaultPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN to open the encrypted vault when biometrics are not available.'**
  String get changeVaultPinSubtitle;

  /// No description provided for @removeVaultPin.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get removeVaultPin;

  /// No description provided for @biometricVaultEnabled.
  ///
  /// In en, this message translates to:
  /// **'Biometric vault'**
  String get biometricVaultEnabled;

  /// No description provided for @biometricVaultEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep places in an AES-256 encrypted vault, behind your biometrics or a PIN.'**
  String get biometricVaultEnabledSubtitle;

  /// No description provided for @suggestedPlaceLinks.
  ///
  /// In en, this message translates to:
  /// **'Places you may want to link'**
  String get suggestedPlaceLinks;

  /// No description provided for @suggestedPlaceLinksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Based on today\'s stops'**
  String get suggestedPlaceLinksSubtitle;

  /// No description provided for @suggestedPlaceOpenAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get suggestedPlaceOpenAction;

  /// No description provided for @suggestedPlaceSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get suggestedPlaceSaveAction;

  /// No description provided for @suggestedPlaceStopDetails.
  ///
  /// In en, this message translates to:
  /// **'Stopped for {minutes} min'**
  String suggestedPlaceStopDetails(int minutes);

  /// No description provided for @suggestedPlaceNearSaved.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is {distance} m away'**
  String suggestedPlaceNearSaved(String name, int distance);

  /// No description provided for @suggestedPlaceNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No saved place nearby'**
  String get suggestedPlaceNoMatch;

  /// No description provided for @suggestedPlaceLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked to {name}'**
  String suggestedPlaceLinked(String name);

  /// No description provided for @suggestedPlaceSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to your places'**
  String get suggestedPlaceSaved;

  /// No description provided for @suggestedPlaceLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t link the place'**
  String get suggestedPlaceLinkFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
