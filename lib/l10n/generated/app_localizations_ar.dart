// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'MapNote';

  @override
  String get placesTitle => 'أماكني';

  @override
  String get searchHint => 'ابحث بالاسم أو الملاحظات';

  @override
  String get addPlace => 'احفظ الموقع الحالي';

  @override
  String get addPlaceTitle => 'حفظ موقع';

  @override
  String get editPlaceTitle => 'تعديل الموقع';

  @override
  String get fieldName => 'الاسم';

  @override
  String get fieldNameHint => 'مثال: منزل أحمد';

  @override
  String get fieldNotes => 'ملاحظات';

  @override
  String get fieldNotesHint => 'مثال: البوابة ٣، الدور الثاني';

  @override
  String get locationCoordinates => 'الإحداثيات';

  @override
  String get latitude => 'خط العرض';

  @override
  String get longitude => 'خط الطول';

  @override
  String get currentLocation => 'الموقع الحالي';

  @override
  String get fetchingLocation => 'جارٍ تحديد موقعك…';

  @override
  String get nameRequired => 'الرجاء إدخال اسم';

  @override
  String get pasteFromClipboard => 'لصق موقع من الحافظة';

  @override
  String get clipboardNoLocation => 'لا توجد إحداثيات في الحافظة';

  @override
  String get clipboardPasted => 'تم لصق الموقع من الحافظة';

  @override
  String get locationModeCurrentGps => 'الموقع الحالي (GPS)';

  @override
  String get locationModeManual => 'إحداثيات مخصصة';

  @override
  String get customCoordinates => 'إحداثيات مخصصة';

  @override
  String get coordinateRequired => 'الرجاء إدخال قيمة';

  @override
  String get coordinateInvalid => 'أدخل رقمًا صالحًا';

  @override
  String get latitudeRange => 'يجب أن يكون خط العرض بين ‎-90 و90';

  @override
  String get longitudeRange => 'يجب أن يكون خط الطول بين ‎-180 و180';

  @override
  String get plusCode => 'رمز Plus';

  @override
  String get plusCodeHint => 'مثال: 8FVC9G8F+6W';

  @override
  String get shareNoLocation => 'لم يتم العثور على موقع في النص المُشارَك';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get ok => 'حسنًا';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get navigate => 'التنقل';

  @override
  String get openInGoogleMaps => 'افتح في خرائط جوجل';

  @override
  String get openInWaze => 'افتح في ويز';

  @override
  String get copyCoordinates => 'نسخ الإحداثيات';

  @override
  String get coordinatesCopied => 'تم نسخ الإحداثيات';

  @override
  String get placeSaved => 'تم حفظ الموقع';

  @override
  String get placeDeleted => 'تم حذف الموقع';

  @override
  String get placeDetailsTitle => 'تفاصيل المكان';

  @override
  String get deletePlaceTitle => 'حذف المكان؟';

  @override
  String deletePlaceMessage(String name) {
    return 'سيتم إزالة \\\"$name\\\" من هذا الجهاز ومن النسخة الاحتياطية القادمة.';
  }

  @override
  String createdAt(String date) {
    return 'حُفظ بتاريخ $date';
  }

  @override
  String get emptyPlacesTitle => 'لا توجد أماكن محفوظة بعد';

  @override
  String get emptyPlacesMessage =>
      'اضغط زر + في الشريط العلوي لحفظ موقعك الحالي.';

  @override
  String get noSearchResults => 'لا توجد أماكن مطابقة لبحثك.';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get sectionLanguage => 'اللغة';

  @override
  String get languageSystem => 'حسب النظام';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get selectLanguage => 'اختر اللغة';

  @override
  String get preferredNavApp => 'تطبيق الملاحة المفضل';

  @override
  String get preferredNavAppSubtitle =>
      'التطبيق الذي يُفتح عند الضغط على «تنقّل»';

  @override
  String get navAppSystem => 'افتراضي النظام';

  @override
  String get navAppGoogleMaps => 'خرائط جوجل';

  @override
  String get navAppWaze => 'ويز';

  @override
  String get sectionLocationServices => 'خدمات الموقع';

  @override
  String get sectionPreferences => 'التفضيلات';

  @override
  String get appearance => 'المظهر';

  @override
  String get fontScale => 'حجم الخط';

  @override
  String get fontScaleSmall => 'صغير';

  @override
  String get fontScaleStandard => 'قياسي';

  @override
  String get fontScaleLarge => 'كبير';

  @override
  String get fontScaleExtraLarge => 'كبير جدًا';

  @override
  String get hapticFeedback => 'الاهتزاز';

  @override
  String get uiDensityCompact => 'واجهة مضغوطة';

  @override
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get sectionAccount => 'الحساب';

  @override
  String get sectionSecurityVault => 'خزنة الأمان';

  @override
  String get signInWithGoogle => 'تسجيل الدخول بجوجل';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String signedInAs(String email) {
    return 'مسجّل الدخول باسم $email';
  }

  @override
  String get notSignedIn => 'لم تسجّل الدخول';

  @override
  String get syncSignInRequired => 'سجّل الدخول بجوجل للمزامنة';

  @override
  String get sectionSync => 'المزامنة والنسخ الاحتياطي';

  @override
  String get syncNow => 'مزامنة الآن';

  @override
  String get syncInProgress => 'جارٍ المزامنة…';

  @override
  String get syncComplete => 'تمت المزامنة';

  @override
  String get syncSkipped => 'سجّل الدخول للمزامنة';

  @override
  String syncFailed(String error) {
    return 'فشلت المزامنة: $error';
  }

  @override
  String signInFailed(String error) {
    return 'فشل تسجيل الدخول: $error';
  }

  @override
  String lastSynced(String date) {
    return 'آخر مزامنة: $date';
  }

  @override
  String get neverSynced => 'لم تتم المزامنة بعد';

  @override
  String get localOverridesCloud =>
      'بيانات جهازك تتجاوز always النسخة الاحتياطية على جوجل درايف.';

  @override
  String get restoreFromDrive => 'الاستعادة من جوجل درايف';

  @override
  String get restoreConfirmTitle => 'الاستعادة من جوجل درايف؟';

  @override
  String get restoreConfirmMessage =>
      'سيؤدي هذا إلى استبدال جميع الأماكن على هذا الجهاز بالنسخة الاحتياطية من جوجل درايف.';

  @override
  String get restoreComplete => 'تمت الاستعادة';

  @override
  String restoreFailed(String error) {
    return 'فشلت الاستعادة: $error';
  }

  @override
  String get locationPermissionTitle => 'مطلوب إذن الموقع';

  @override
  String get locationPermissionMessage =>
      'يحتاج MapNote إلى الوصول لموقعك لحفظ الأماكن.';

  @override
  String get locationServicesDisabled => 'يرجى تفعيل خدمات الموقع على جهازك.';

  @override
  String get locationUnavailable => 'تعذّر تحديد موقعك. حاول مرة أخرى.';

  @override
  String get openAppSettings => 'افتح الإعدادات';

  @override
  String get locationStatusGps => 'نظام تحديد المواقع';

  @override
  String get locationStatusPermission => 'الإذن';

  @override
  String get locationGpsOn => 'مفعّل';

  @override
  String get locationGpsOff => 'متوقف';

  @override
  String get locationPermissionGranted => 'مسموح';

  @override
  String get locationPermissionDenied => 'مرفوض';

  @override
  String get locationPermissionDeniedForever => 'محظور';

  @override
  String get locationPermissionUnknown => 'لم يُطلب';

  @override
  String get manageLocation => 'إدارة الموقع';

  @override
  String get contactsPermissionTitle => 'إذنcontacts مطلوب';

  @override
  String get contactsPermissionNeeded =>
      'يحتاج MapNote إلى الوصول إلىcontacts لربطها بالمواقع المحفوظة.';

  @override
  String get contactsPermissionDeniedPermanently =>
      'تم رفضذنcontacts بشكل دائم. يمكنك تغيير هذا في إعدادات الجهاز.';

  @override
  String get contactPickerFeatureNotReady =>
      'ميزة تحديد جهة الاتصال غير جاهزة بعد.';

  @override
  String get unlinkContactFeatureNotReady => 'ميزة فك الربط غير جاهزة بعد.';

  @override
  String get allow => 'سماح';

  @override
  String get settings => 'الإعدادات';

  @override
  String linkedContact(String name) {
    return 'جهة اتصال مرتبطة: $name';
  }

  @override
  String get unlinkContact => 'فك الربط';

  @override
  String get linkContact => 'ربط جهة اتصال';

  @override
  String get smartBatterySaver => 'موفر البطارية الذكي';

  @override
  String get smartBatterySaverDesc => 'تقليل تحديثات GPS عند الثبات.';

  @override
  String get exportMotionData => 'تصدير بيانات الحركة';

  @override
  String tileCacheSize(Object size) {
    return 'ذاكرة الخرائط: $size';
  }

  @override
  String get clearTileCache => 'مسح ذاكرة الخرائط';

  @override
  String get preloadOfflineMaps => 'تحميل خرائط الأماكن مسبقًا';

  @override
  String get offlineMapDownloaded => 'تم تحميل الخرائط دون اتصال';

  @override
  String get offlineMapRegionSelection => 'منطقة الخريطة التحميلية';

  @override
  String get minLatitude => 'الحد الأدنى للخط العرض';

  @override
  String get maxLatitude => 'الحد الأقصى للخط العرض';

  @override
  String get latitudeHint => 'الحد الأدنى للخط العرض (مثال: 30.05)';

  @override
  String get minLongitude => 'الحد الأدنى للخط الطول';

  @override
  String get maxLongitude => 'الحد الأقصى للخط الطول';

  @override
  String get longitudeHint => 'الحد الأدنى للخط الطول (مثال: 31.22)';

  @override
  String get minZoom => 'أدنى مستوى تكبير';

  @override
  String get maxZoom => 'أقصى مستوى تكبير';

  @override
  String get zoomHint => 'مستوى التكبير (0-20)';

  @override
  String get startDownload => 'بدء التحميل';

  @override
  String get autoMotionExport => 'تصدير البيانات';

  @override
  String get autoMotionCustomRange => 'نطاق مخصص';

  @override
  String autoMotionRangeLabel(Object from, Object to) {
    return '$from – $to';
  }

  @override
  String get autoMotionSelectRange => 'نطاق مخصص';

  @override
  String get autoMotionExportCopied => 'تم نسخ التقرير';

  @override
  String get zeroCoordinatesNotice => 'التصدير لا enthältoire محتويات موقع.';

  @override
  String get autoMotionExportCsv => 'تصدير CSV';

  @override
  String get autoMotionExportJson => 'تصدير JSON';

  @override
  String get autoMotionExportCopy => 'نسخ إلى الحافظة';

  @override
  String get savedPlacesVaultLock => 'قفل الخزنة';

  @override
  String get dailyGpsSection => 'تتبع GPS اليومي';

  @override
  String get dailyGpsToggle => 'تفعيل تتبع GPS اليومي';

  @override
  String get dailyGpsToggleSubtitle =>
      'يسجّل المسافة والسرعة القصوى أثناء فتح التطبيق';

  @override
  String get dailyGpsPermissionHint =>
      'يلزم إذن الموقع للتتبع. شغّل GPS واسمح بتحديد الموقع ثم أعد تفعيل التتبع.';

  @override
  String get dailyDistance => 'المسافة اليوم';

  @override
  String get dailyMaxSpeed => 'السرعة القصوى';

  @override
  String get dailyTrackingActive => 'التتبع نشط';

  @override
  String get dailyTrackingPaused => 'متوقف مؤقتًا';

  @override
  String get dailyGpsUnavailable => 'GPS غير متاح — تحقق من إعدادات الموقع';

  @override
  String get kmUnit => 'كم';

  @override
  String get kmhUnit => 'كم/س';

  @override
  String get autoMotionSection => 'أوتوموشن';

  @override
  String get autoMotionToggle => 'تفعيل أوتوموشن';

  @override
  String get autoMotionToggleSubtitle =>
      'يسجّل المسافة والسرعة القصوى تلقائيًا أثناء فتح التطبيق';

  @override
  String get autoMotionPermissionHint =>
      'يلزم إذن الموقع لأوتوموشن. شغّل GPS واسمح بتحديد الموقع ثم أعد تفعيل أوتوموشن.';

  @override
  String get autoMotionDistance => 'المسافة اليوم';

  @override
  String get autoMotionMaxSpeed => 'السرعة القصوى اليوم';

  @override
  String get autoMotionActive => 'نشط';

  @override
  String get autoMotionPaused => 'متوقف';

  @override
  String get autoMotionDashboardTitle => 'لوحة أوتوموشن';

  @override
  String get autoMotionDriverMode => 'وضع القيادة';

  @override
  String get autoMotionCurrentSpeed => 'السرعة الحالية';

  @override
  String get autoMotionToday => 'اليوم';

  @override
  String get autoMotionHistory => 'سجل الرحلات';

  @override
  String get autoMotionHistoryEmpty => 'لم تُسجَّل أي حركة بعد';

  @override
  String get autoMotionHistoryEmptyHint =>
      'ستظهر هنا الأيام التي سُجّلت فيها حركة.';

  @override
  String get autoMotionActivityBreakdown => 'تفصيل النشاط';

  @override
  String get autoMotionActivityBreakdownToday => 'نشاط اليوم';

  @override
  String get autoMotionActivityBreakdownEmpty =>
      'لم يُسجّل بيانات حسب الوضع بعد.';

  @override
  String get autoMotionModeWalk => 'مشّي';

  @override
  String get autoMotionModeRun => 'ركض';

  @override
  String get autoMotionModeVehicle => 'مركبة';

  @override
  String get autoMotionAggregates => 'إجماليات الفترة';

  @override
  String get autoMotionLast7Days => 'آخر ٧ أيام';

  @override
  String get autoMotionLast30Days => 'آخر ٣٠ يومًا';

  @override
  String autoMotionDaysRecorded(int count) {
    return '$count أيام مسجّلة';
  }

  @override
  String get autoMotionViewDetails => 'عرض التفاصيل';

  @override
  String get autoMotionRoute => 'مسار اليوم';

  @override
  String get autoMotionRouteEmpty =>
      'لم يُسجَّل أي مسار بعد — فعّل التتبع ثم قد أو امشِ ليظهر هنا.';

  @override
  String get routeMapAttribution => '© المساهمون في OpenStreetMap';

  @override
  String get routeMilestonesTitle => 'محطات المسار';

  @override
  String get routeMilestonesEmpty =>
      'لا توجد محطات موقوتة على هذا المسار بعد — تظهر محطات التوقف الموقوتة هنا أثناء تسجيل الرحلة.';

  @override
  String get milestoneTripStart => 'بداية الرحلة';

  @override
  String get milestoneStop => 'توقف';

  @override
  String get milestoneTripEnd => 'نهاية الرحلة';

  @override
  String get autoMotionEvents => 'أحداث القيادة';

  @override
  String get autoMotionEventsEmpty => 'لم تُرصد مناورات قاسية في هذه الرحلة.';

  @override
  String autoMotionEventsMore(int count) {
    return '$count أخرى';
  }

  @override
  String get harshAcceleration => 'تسارع حاد';

  @override
  String get harshBraking => 'كبح حاد';

  @override
  String get sharpTurn => 'انعطاف حاد';

  @override
  String get speedBump => 'مطب صناعي';

  @override
  String get pothole => 'حفرة';

  @override
  String get mps2Unit => 'm/s²';

  @override
  String get autoMotionEventMarkers => 'علامات الأحداث على المسار';

  @override
  String get motionSummaryTitle => 'تقييم قيادة الرحلة';

  @override
  String motionSummaryScore(int score) {
    return '$score / 100';
  }

  @override
  String motionSummaryEvents(int count) {
    return '$count حدث';
  }

  @override
  String get motionSummaryClean => 'رحلة هادئة — لا مناورات قاسية.';

  @override
  String get motionSummaryExpand => 'إظهار ملخص الحركة';

  @override
  String get motionSummaryCollapse => 'إخفاء ملخص الحركة';

  @override
  String get scoreExcellent => 'ممتاز';

  @override
  String get scoreGood => 'جيد';

  @override
  String get scoreFair => 'مقبول';

  @override
  String get scorePoor => 'ضعيف';

  @override
  String get locationChipServiceOff => 'الموقع متوقف — اضغط للتفعيل';

  @override
  String get locationChipPermissionDenied => 'إذن الموقع مطلوب — اضغط للسماح';

  @override
  String get locationChipDeniedForever => 'الموقع محظور — اضغط لفتح الإعدادات';

  @override
  String get errorGeneric => 'حدث خطأ ما';

  @override
  String get about => 'حول';

  @override
  String get version => 'الإصدار';

  @override
  String get aboutDescription =>
      'يحفظ MapNote أماكنك المفضلة دون اتصال ويزامنها إلى جوجل درايف الخاص بك. يتم فتح التنقل في تطبيق الخرائط الذي تستخدمه بالفعل.';

  @override
  String get addLocation => 'إضافة موقع';

  @override
  String get addCurrentLocation => 'الموقع الحالي';

  @override
  String get addCurrentLocationSubtitle => 'استخدم موقع جهازك عبر GPS';

  @override
  String get aiSmartPaste => 'اللصق الذكي';

  @override
  String get aiSmartPasteSubtitle => 'الصق رابط خرائط جوجل أو الإحداثيات';

  @override
  String get enterCoordinates => 'إدخال الإحداثيات';

  @override
  String get enterCoordinatesSubtitle => 'اكتب خط العرض وخط الطول يدويًا';

  @override
  String get pinnedLabel => 'مثبّت';

  @override
  String get lockedLabel => 'مقفل';

  @override
  String get pinToTop => 'تثبيت في الأعلى';

  @override
  String get unpinFromTop => 'إلغاء التثبيت';

  @override
  String get pinnedToTop => 'تم التثبيت في الأعلى';

  @override
  String get unpinnedFromTop => 'تمت الإزالة من الأعلى';

  @override
  String get shareQr => 'مشاركة رمز QR';

  @override
  String get shareViaWhatsApp => 'إرسال عبر الواتساب';

  @override
  String get searchContact => 'بحث';

  @override
  String get proposeManagerUpdateTitle => 'اقترح تحديث المسؤول';

  @override
  String get proposeManagerUpdate => 'اقترح تحديث المسؤول';

  @override
  String get updateProposalSubmitted => 'تم إرسال proposal';

  @override
  String get managerName => 'اسم المدير';

  @override
  String get managerPhone => 'رقم المدير';

  @override
  String get confirm => 'تأكيد';

  @override
  String get currentUserName => 'اسم المستخدم الحالي';

  @override
  String get shareViaSystem => 'مشاركة عبر النظام';

  @override
  String get sendToDriver => 'إرسال للسائق';

  @override
  String get submitStationUpdate => 'إرسال تعديل للمحطة';

  @override
  String get submittingUpdate => 'جاري الإرسال...';

  @override
  String get updateSuccess => 'تم إرسال proposal بنجاح';

  @override
  String get updateFailed => 'فشل إرسال proposal';

  @override
  String get addToHomeScreen => 'إضافة اختصار إلى الشاشة الرئيسية';

  @override
  String get lockLocation => 'قفل الموقع';

  @override
  String get unlockLocation => 'إلغاء قفل الموقع';

  @override
  String get locationLocked => 'تم قفل الموقع';

  @override
  String get locationUnlocked => 'تم إلغاء قفل الموقع بنجاح';

  @override
  String get hideLocation => 'إخفاء الموقع';

  @override
  String get unhideLocation => 'إظهار الموقع';

  @override
  String get locationHidden => 'تم إخفاء الموقع';

  @override
  String get locationUnhidden => 'تم إظهار الموقع';

  @override
  String get unlockToContinue => 'أكّد هويتك للمتابعة';

  @override
  String get unlockToNavigate => 'أكّد هويتك للتنقل';

  @override
  String get unlockToEdit => 'أكّد هويتك للتعديل';

  @override
  String get unlockToUnlock => 'أكّد هويتك لإلغاء القفل';

  @override
  String get unlockToShareQr => 'أكّد هويتك للمشاركة';

  @override
  String get unlockToOpenVault => 'أكّد هويتك لفتح الخزنة المخفية';

  @override
  String get authenticationFailed => 'فشل التحقق';

  @override
  String get biometricsUnavailable => 'التحقق الحيوي غير متاح على هذا الجهاز';

  @override
  String get noDeviceSecurityWarning =>
      'لا توجد شاشة قفل أو تحقق حيوي على هذا الجهاز، لذلك تم تخطي التحقق';

  @override
  String get sectionPrivacy => 'الخصوصية والأمان';

  @override
  String get hiddenVault => 'الخزنة المخفية';

  @override
  String hiddenVaultSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مكان مخفي',
      many: '$count مكان مخفي',
      few: '$count أماكن مخفية',
      one: 'مكان مخفي واحد',
      zero: 'لا توجد أماكن مخفية',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVaultEmpty => 'لا توجد أماكن مخفية';

  @override
  String get hiddenVaultEmptyMessage =>
      'ستظهر الأماكن التي تخفيها هنا، محمية بقفل جهازك.';

  @override
  String get vaultProtectionTitle => 'حماية الخزنة';

  @override
  String get vaultProtectionSubtitle =>
      'كم تبقى الخزنة المخفية مفتوحة، وما إذا كانت تُقفل عند قفل الشاشة.';

  @override
  String get sessionTimeoutTitle => 'القفل التلقائي عند عدم الاستخدام';

  @override
  String get sessionTimeoutSubtitle =>
      'تُقفل الخزنة مرة أخرى بعد هذه المدة من عدم الاستخدام.';

  @override
  String sessionTimeoutMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes دقائق',
      one: 'دقيقة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get lockOnDeviceLockTitle => 'القفل عند قفل الجهاز';

  @override
  String get lockOnDeviceLockSubtitle =>
      'ينهي جلسة الخزنة بمجرد قفل الشاشة، دون أي مهلة.';

  @override
  String get vaultDimmingNotice =>
      'لخصوصيتك، تخفت الشاشة عندما يكون الجهاز في وضع السكون دون مراقبة.';

  @override
  String get sessionTimeoutUpdated => 'تم تحديث مدة القفل التلقائي';

  @override
  String get lockOnDeviceLockUpdated => 'تم تحديث الحماية عند قفل الجهاز';

  @override
  String get qrCodeTitle => 'مشاركة عبر رمز QR';

  @override
  String get qrCodeHint => 'امسح الرمز لفتح هذا الموقع في تطبيق الخرائط';

  @override
  String get copyLink => 'نسخ الرابط';

  @override
  String get linkCopied => 'تم نسخ الرابط';

  @override
  String get close => 'إغلاق';

  @override
  String get shortcutRequested => 'اتبع التنبيه على الشاشة لإضافة الاختصار';

  @override
  String get shortcutUnsupported =>
      'اختصارات الشاشة الرئيسية غير مدعومة على هذا الجهاز';

  @override
  String get shortcutUnavailable => 'تعذّرت إضافة الاختصار';

  @override
  String get sectionSmartInsights => 'رؤى ذكية';

  @override
  String get smartInsightsTitle => 'رؤى ذكية';

  @override
  String get smartInsightsRefresh => 'تحديث الاقتراحات';

  @override
  String get smartInsightsDismiss => 'تجاهل';

  @override
  String get smartInsightsEmpty => 'كل شيء يبدو جيدًا — لا توجد اقتراحات الآن.';

  @override
  String get smartInsightsEmptyHint =>
      'أضف المزيد من الأماكن لتوليد رؤى واقتراحات ذكية.';

  @override
  String get smartInsightsEnable => 'تفعيل الرؤى الذكية';

  @override
  String get smartInsightsEnableSubtitle => 'عرض الاقتراحات في الشاشة الرئيسية';

  @override
  String get smartInsightsCloudAi => 'اقتراحات الذكاء السحابي';

  @override
  String get smartInsightsCloudAiSubtitle =>
      'اسمح لجوجل Gemini بإضافة نصائح اختيارية. تُرسل أعداد مجهولة فقط — ولا تُرسل أماكنك أو ملاحظاتك أبدًا.';

  @override
  String get insightWelcomeTitle => 'احفظ مكانك الأول';

  @override
  String get insightWelcomeBody => 'اضغط زر + لحفظ موقعك الحالي.';

  @override
  String get insightNearbyDuplicatesTitle => 'جمّع الأماكن المتقاربة';

  @override
  String insightNearbyDuplicatesBody(int count) {
    return 'يوجد $count أماكن محفوظة متقاربة جدًا. جرّب تجميعها أو إعادة تسميتها.';
  }

  @override
  String get insightUnorganizedTitle => 'أضف تفاصيل لأماكنك';

  @override
  String insightUnorganizedBody(int count) {
    return 'يوجد $count أماكن بدون ملاحظات. أضف ملاحظة لتتعرف عليها لاحقًا.';
  }

  @override
  String get insightSyncIssuesTitle => 'لم تكتمل المزامنة';

  @override
  String insightSyncIssuesBody(int count) {
    return 'لم تكتمل $count عمليات مزامنة حديثة. تحقّق من اتصالك وحاول مجددًا.';
  }

  @override
  String get insightNetworkWarningTitle => 'احتمال ضعف الشبكة';

  @override
  String get insightNetworkWarningBody =>
      'فشلت المزامنة عدة مرات مؤخرًا. انتظر اتصالًا مستقرًا قبل النسخ الاحتياطي التالي.';

  @override
  String get insightParseIssuesTitle => 'تعذّر قراءة بعض المواقع';

  @override
  String insightParseIssuesBody(int count) {
    return 'تعذّر تحليل $count مواقع ملصوقة. جرّب لصق رابط خرائط جوجل الكامل.';
  }

  @override
  String get insightStaleBackupTitle => 'انشئ نسخة احتياطية';

  @override
  String insightStaleBackupBody(int days) {
    return 'كان آخر نسخ احتياطي قبل $days يومًا. زامن الآن للحفاظ على أماكنك.';
  }

  @override
  String get insightStaleBackupNeverBody =>
      'لم تنشئ نسخة احتياطي بعد. زامن الآن للحفاظ على أماكنك.';

  @override
  String get insightPinFavoritesTitle => 'ثبّت أماكنك المفضلة';

  @override
  String insightPinFavoritesBody(int count) {
    return 'لديك $count أماكن محفوظة ولا يوجد أي مكان مثبّت. اضغط مطوّلًا على مكان لتثبيته في الأعلى.';
  }

  @override
  String get insightOptimizationTitle => 'احتفظ بـ MapNote مرتبًا';

  @override
  String get insightOptimizationBody =>
      'القائمة الكبيرة تُحمّل أبطأ. راجع الأماكن المكررة أو غير المستخدمة واحذف ما لا تحتاجه.';

  @override
  String get insightMotionSummaryTitle => 'حركتك اليوم';

  @override
  String insightMotionSummaryBody(
    String walking,
    String running,
    String vehicle,
  ) {
    return 'قطعت اليوم $walking مشيًا و$running جريًا، إضافة إلى $vehicle بالمركبة.';
  }

  @override
  String insightMotionSummaryBodySteps(
    String walking,
    String running,
    String vehicle,
    int steps,
  ) {
    return 'قطعت اليوم $walking مشيًا و$running جريًا، إضافة إلى $vehicle بالمركبة، على $steps خطوة معدودة.';
  }

  @override
  String get insightActionSyncNow => 'زامن الآن';

  @override
  String get coordinateDetails => 'خط العرض وخط الطول';

  @override
  String get aiSmartPasteTooltip => 'اللصق الذكي';

  @override
  String get categoryWork => 'العمل';

  @override
  String get categoryHome => 'المنزل';

  @override
  String get categorySchool => 'الدراسة';

  @override
  String get categoryPersonal => 'شخصي';

  @override
  String get plusCodeDetected => 'تم رصد رمز Plus في الحافظة';

  @override
  String get plusCodeImport => 'استيراد';

  @override
  String get plusCodeInvalid => 'أدخل رمز Plus صالحًا';

  @override
  String get plusCodeOrCoordinatesRequired =>
      'أدخل رمز Plus أو خط العرض وخط الطول';

  @override
  String get plusCodeShortNeedsReference =>
      'يحتاج رمز Plus المختصر إلى موقع قريب. فعّل GPS أو الصق الرمز الكامل.';

  @override
  String foundPlace(String name) {
    return 'تم العثور على: $name';
  }

  @override
  String get autoFillNameNotes => 'تعبئة الاسم والملاحظات تلقائيًا';

  @override
  String get dismissSuggestion => 'تجاهل الاقتراح';

  @override
  String get suggestionTitle => 'مكان قريب';

  @override
  String get routePreview => 'معاينة المسار';

  @override
  String get currentLocationMarker => 'الموقع الحالي';

  @override
  String get savedLocationMarker => 'المكان المحفوظ';

  @override
  String distanceAway(String distance) {
    return 'يبعد $distance';
  }

  @override
  String get accountAndBackup => 'الحساب والنسخ السحابي';

  @override
  String get sectionLocationTracking => 'الموقع والتتبع';

  @override
  String get aboutTitle => 'حول MapNote';

  @override
  String get bousla => 'البوصلة';

  @override
  String get smartAutoMotionTitle => 'تفعيل تتبع AutoMotion الذكي';

  @override
  String get smartAutoMotionSubtitle =>
      'دمج الـ GPS وحساسات الحركة لتتبع المسافة والسرعة تلقائياً وتوفير البطارية';

  @override
  String get compassTitle => 'البوصلة';

  @override
  String get mapPreview => 'معاينة الخريطة';

  @override
  String get enableLocationForRoute => 'فعّل الموقع لرؤية المسافة';

  @override
  String get qiblaUnavailable => 'لا توجد قراءة GPS';

  @override
  String get qiblaDirectionAbbrev => 'مثلاً: SE';

  @override
  String get qiblaAligned => 'محاذاة مع القبلة';

  @override
  String get compassNorth => 'شمال';

  @override
  String get headingInstruction => 'عدل اتجاه الجهاز لرؤية القبلة';

  @override
  String get compassCalculating => 'جاري الحساب...';

  @override
  String get savedPlacesVault => 'الخزنة المشفّرة';

  @override
  String get savedPlacesVaultSubtitle =>
      'أماكن محمية بالمصادقة الحيوية ومشفّرة بـ AES-256';

  @override
  String get savedPlacesVaultLocked => 'الخزنة مقفلة';

  @override
  String get savedPlacesVaultLockedMessage =>
      'تحقق من هويتك لقراءة الأماكن المحفوظة في الخزنة المشفّرة.';

  @override
  String get savedPlacesVaultUnlock => 'فتح الخزنة';

  @override
  String get savedPlacesVaultEmpty => 'لا توجد أماكن مشفّرة بعد';

  @override
  String get savedPlacesVaultEmptyMessage =>
      'Move a saved place into the vault to protect it behind your device lock.';

  @override
  String get savedPlacesVaultUnlocked => 'تم فتح الخزنة';

  @override
  String get savedPlacesVaultUnavailable =>
      'لا يمكن لهذا الجهاز التحقق من هويتك';

  @override
  String get moveToEncryptedVault => 'نقل إلى الخزنة المشفّرة';

  @override
  String get moveToEncryptedVaultDone => 'تم النقل إلى الخزنة المشفّرة';

  @override
  String get restoreFromEncryptedVault => 'إعادة إلى الأماكن المحفوظة';

  @override
  String get restoreFromEncryptedVaultDone =>
      'تمت الإعادة إلى الأماكن المحفوظة';

  @override
  String get unlockToOpenSavedPlacesVault => 'تحقق لفتح الخزنة المشفّرة';

  @override
  String get unlockToMoveToEncryptedVault =>
      'تحقق لنقل المكان إلى الخزنة المشفّرة';

  @override
  String get enterPin => 'أدخل رمز PIN';

  @override
  String get vaultPinLabel => 'رمز PIN';

  @override
  String get vaultPinConfirmLabel => 'تأكيد رمز PIN';

  @override
  String get vaultPinHint =>
      'استخدم من 4 إلى 12 رقماً. يفتح الرمز الخزنة المشفّرة عندما لا تتوفر البصمة.';

  @override
  String get vaultPinTooShort => 'استخدم 4 أرقام على الأقل.';

  @override
  String get vaultPinMismatch => 'رمزان PIN غير متطابقين.';

  @override
  String get vaultPinRejected => 'رمز PIN غير صحيح.';

  @override
  String get vaultPinLockedOut =>
      'محاولات كثيرة. Versuch wieder nach wenigen Minuten.';

  @override
  String get vaultPinSet => 'تم تعيين رمز PIN.';

  @override
  String get vaultPinChanged => 'تم تغيير رمز PIN.';

  @override
  String get vaultPinRemoved => 'تمت إزالة الرمز';

  @override
  String get vaultPinNotSet => 'لا يوجد رمز PIN';

  @override
  String get usePinInstead => 'استخدام رمز PIN';

  @override
  String get changeVaultPin => 'رمز PIN للخزنة';

  @override
  String get changeVaultPinSubtitle =>
      'عيّن رمز PIN لفتح الخزنة المشفّرة عندما لا تتوفر البصمة.';

  @override
  String get removeVaultPin => 'إزالة الرمز';

  @override
  String get biometricVaultEnabled => 'خزنة حيوية';

  @override
  String get biometricVaultEnabledSubtitle =>
      'Keep places in an AES-256 encrypted vault, behind your biometrics or a PIN.';

  @override
  String get suggestedPlaceLinks => 'أماكن قد ترغب في ربطها';

  @override
  String get suggestedPlaceLinksSubtitle => 'بناءً على توقفات اليوم';

  @override
  String get suggestedPlaceOpenAction => 'فتح';

  @override
  String get suggestedPlaceSaveAction => 'حفظ';

  @override
  String suggestedPlaceStopDetails(int minutes) {
    return 'توقفت لمدة $minutes دقيقة';
  }

  @override
  String suggestedPlaceNearSaved(String name, int distance) {
    return ' \"$name\" على بعد $distance م';
  }

  @override
  String get suggestedPlaceNoMatch => 'لا يوجد مكان محفوظ قريب';

  @override
  String suggestedPlaceLinked(String name) {
    return 'تم الربط بـ $name';
  }

  @override
  String get suggestedPlaceSaved => 'تم الحفظ في أماكنك';

  @override
  String get suggestedPlaceLinkFailed => 'تعذّر ربط المكان';

  @override
  String get motionHistoryTitle => 'سجل الحركة';

  @override
  String get motionHistorySubtitle =>
      'الرحلات والمشي والجري والتوقفات المسجلة في هذا اليوم';

  @override
  String get motionTypeDrive => 'قيادة';

  @override
  String get motionTypeWalk => 'مشي';

  @override
  String get motionTypeRun => 'جري';

  @override
  String get motionTypeStopover => 'توقف';

  @override
  String get motionHistoryToday => 'اليوم';

  @override
  String get motionHistoryYesterday => 'أمس';

  @override
  String get motionHistoryPickDate => 'اختر يومًا';

  @override
  String get motionHistoryPreviousDay => 'اليوم السابق';

  @override
  String get motionHistoryNextDay => 'اليوم التالي';

  @override
  String get motionHistoryViewTimeline => 'الخط الزمني';

  @override
  String get motionHistoryViewMap => 'الخريطة';

  @override
  String get motionHistoryTotalDistance => 'المسافة';

  @override
  String get motionHistoryDriveTime => 'زمن القيادة';

  @override
  String get motionHistoryStopoverTime => 'زمن التوقف';

  @override
  String get motionHistoryEmptyTitle => 'لا توجد حركة مسجلة';

  @override
  String get motionHistoryEmptyBody =>
      'لم يُسجَّل شيء في هذا اليوم. شغّل AutoMotion ثم قد أو امشِ لبناء الخط الزمني.';

  @override
  String get motionHistoryNoRoute => 'لا يوجد مسار لرسمه في هذا اليوم.';

  @override
  String get motionHistoryShowOnMap => 'اعرض على الخريطة';

  @override
  String motionHistoryDriveStats(String distance, String duration) {
    return '$distance كم · $duration';
  }

  @override
  String motionHistoryAverageSpeed(String speed) {
    return 'المتوسط $speed كم/س';
  }

  @override
  String motionHistoryStepStats(String distance, int steps) {
    return '$distance م · $steps خطوة';
  }

  @override
  String get motionHistorySteps => 'خطوات';

  @override
  String get motionHistoryModeBreakdownHint =>
      'تُقاس مسافات المشي والجري بالعداد الخطوي، أما مسافة المركبة فتُستمد من GPS.';

  @override
  String motionHistoryStopoverStats(String duration) {
    return 'توقفت لمدة $duration';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours س $minutes د';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes د';
  }

  @override
  String get durationZero => '0 د';

  @override
  String get durationLessThanMinute => 'أقل من دقيقة';

  @override
  String get stationManagersTitle => 'مسؤول المحطة';

  @override
  String get callManager => 'اتصال بالمسؤول';

  @override
  String get messageManagerOnWhatsApp => 'مراسلة على واتساب';

  @override
  String get managerPhoneMissing => 'لم يُضف رقم هاتف بعد';

  @override
  String get managerContactUnavailable =>
      'لا يوجد تطبيق على هذا الجهاز يمكنه تنفيذ ذلك';

  @override
  String managerWhatsAppMessage(String name, String station) {
    return 'مرحبًا $name، بخصوص $station.';
  }

  @override
  String get adminApprovalTitle => 'وصول المسؤول';

  @override
  String get noPendingUpdates => 'لا توجد ترقيعاتpending';

  @override
  String proposalForStation(Object stationId) {
    return 'اقتراح للمحطة $stationId';
  }

  @override
  String currentManager(Object name) {
    return 'مسؤول حالي: $name';
  }

  @override
  String currentManagerPhone(Object phone) {
    return 'هاتف: $phone';
  }

  @override
  String proposedManager(Object name) {
    return 'مسؤول مقترح: $name';
  }

  @override
  String proposedManagerPhone(Object phone) {
    return 'هاتف: $phone';
  }

  @override
  String submittedBy(Object name) {
    return 'تم الإرسال بواسطة: $name';
  }

  @override
  String submittedAt(Object date) {
    return 'تم الإرسال في: $date';
  }

  @override
  String get adminPinRequired => 'يُطلب رمز المسؤول';

  @override
  String get pin => 'رمز PIN';

  @override
  String get incorrectPin => 'رمز غير صحيح';

  @override
  String get incorrectPinAttempt => 'الرمز المدخل خاطئ، يرجىようとする';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get wrongPin => 'رمز خاطئ';

  @override
  String get unlock => 'فتح';

  @override
  String get unknownManager => 'لا مسئول';

  @override
  String get unknownPhone => 'لا يوجد هاتف';

  @override
  String get approve => 'قبول';

  @override
  String get reject => 'رفض';

  @override
  String get resetPin => 'إعادة تعيين الرمز';

  @override
  String get incompleteProposal => 'طلب غير مكتمل';

  @override
  String get dismissProposal => 'تجاهل';

  @override
  String get proposalDismissed => 'تم تجاوز الاقتراح';

  @override
  String get dismissFailed => 'فشل تجاوز الاقتراح';

  @override
  String get incompleteNewStation => 'اقتراح محطة غير مكتمل';

  @override
  String get missingStation => 'المرجع للمحطة غير محدد';

  @override
  String get proposalApproved => 'تم قبول الاقتراح بنجاح';

  @override
  String get proposalRejected => 'تم رفض الاقتراح';

  @override
  String get approveFailed => 'فشل قبول الاقتراح';

  @override
  String get rejectFailed => 'فشل رفض الاقتراح';

  @override
  String get newStationApproved => 'تم قبول محطة جديدة بنجاح';

  @override
  String get adminPinHint => '1991';

  @override
  String newStationTitle(String name) {
    return 'محطة جديدة: $name';
  }

  @override
  String proposalIdLabel(String id) {
    return 'معرّف الاقتراح: $id';
  }

  @override
  String proposalRole(String role) {
    return 'الدور: $role';
  }

  @override
  String proposalLocation(String lat, String lng) {
    return 'الموقع: $lat، $lng';
  }

  @override
  String proposalCity(String city) {
    return 'المدينة: $city';
  }

  @override
  String get unknownStation => 'محطة غير معروفة';

  @override
  String get roleManager => 'مدير';

  @override
  String get roleSupervisor => 'مشرف';

  @override
  String get roleSupport => 'دعم';

  @override
  String get roleStaff => 'موظف';

  @override
  String workInsightsStations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محطة',
      many: '$count محطة',
      few: '$count محطات',
      two: 'محطتان',
      one: 'محطة واحدة',
      zero: 'لا توجد محطات',
    );
    return '$_temp0';
  }

  @override
  String workInsightsManagers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جهة اتصال لمسؤول',
      many: '$count جهة اتصال لمسؤول',
      few: '$count جهات اتصال لمسؤولين',
      two: 'جهتا اتصال لمسؤولين',
      one: 'جهة اتصال لمسؤول واحدة',
      zero: 'لا توجد جهات اتصال لمسؤولين',
    );
    return '$_temp0';
  }

  @override
  String workInsightsMissingContacts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محطة بدون رقم هاتف',
      many: '$count محطة بدون رقم هاتف',
      few: '$count محطات بدون رقم هاتف',
      two: 'محطتان بدون رقم هاتف',
      one: 'محطة واحدة بدون رقم هاتف',
      zero: 'كل المحطات لديها رقم هاتف',
    );
    return '$_temp0';
  }

  @override
  String workInsightsWorkTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مكان موسوم بـ #work',
      many: '$count مكانًا موسومًا بـ #work',
      few: '$count أماكن موسومة بـ #work',
      two: 'مكانان موسومان بـ #work',
      one: 'مكان واحد موسوم بـ #work',
      zero: 'لا توجد أماكن موسومة بـ #work',
    );
    return '$_temp0';
  }

  @override
  String get workInsightsTip =>
      'أضف الوسم #work إلى اسم المكان أو ملاحظاته لتتبع العمليات. قدّم تحديثات جهات الاتصال من شاشة المحطة لاعتمادها من المسؤول.';

  @override
  String get workInsightsNothingMissing => 'كل المحطات لديها جهة اتصال مسجلة.';

  @override
  String workInsightsPendingApprovals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count موافقة إدارية معلقة',
      many: '$count موافقة إدارية معلقة',
      few: '$count موافقات إدارية معلقة',
      two: 'موافقتان إداريتان معلقتان',
      one: 'موافقة إدارية معلقة واحدة',
      zero: 'لا توجد موافقات إدارية معلقة',
    );
    return '$_temp0';
  }

  @override
  String workInsightsStationsMissingContactsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count محطة ينقصها بيانات مسؤول الاتصال',
      many: '$count محطة ينقصها بيانات مسؤول الاتصال',
      few: '$count محطات ينقصها بيانات مسؤول الاتصال',
      two: 'محطتان ينقصهما بيانات مسؤول الاتصال',
      one: 'محطة واحدة ينقصها بيانات مسؤول الاتصال',
      zero: 'لا توجد محطات ينقصها بيانات المسؤول',
    );
    return '$_temp0';
  }
}
