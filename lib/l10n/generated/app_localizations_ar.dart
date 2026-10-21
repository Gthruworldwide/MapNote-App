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
  String get openInWaze => 'افتح في Waze';

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
    return 'سيتم إزالة \"$name\" من هذا الجهاز ومن النسخة الاحتياطية القادمة.';
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
  String get themeSystem => 'النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get sectionAccount => 'الحساب';

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
      'بيانات جهازك تتجاوز دائمًا النسخة الاحتياطية على جوجل درايف.';

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
      'لم يُسجَّل أي مسار بعد — فعّل التتبع ثم قُد أو امشِ ليظهر هنا.';

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
      many: '$count مكانًا مخفيًا',
      few: '$count أماكن مخفية',
      two: 'مكانان مخفيان',
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
      other: '$minutes دقيقة',
      many: '$minutes دقيقة',
      few: '$minutes دقائق',
      two: 'دقيقتان',
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
    return 'يوجد $count أماكن بدون ملاحظات. أضف ملاحظة لتتعرّف عليها لاحقًا.';
  }

  @override
  String get insightSyncIssuesTitle => 'لم تكتمل المزامنة';

  @override
  String insightSyncIssuesBody(int count) {
    return 'لم تكتمل $count عمليات مزامنة حديثة. تحقّق من اتصالك وحاول مجددًا.';
  }

  @override
  String get insightNetworkWarningTitle => 'قد تكون الشبكة ضعيفة';

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
      'لم تنشئ نسخة احتياطية بعد. زامن الآن للحفاظ على أماكنك.';

  @override
  String get insightPinFavoritesTitle => 'ثبّت أماكنك المفضلة';

  @override
  String insightPinFavoritesBody(int count) {
    return 'لديك $count أماكن محفوظة ولا يوجد أي مكان مثبّت. اضغط مطوّلًا على مكان لتثبيته في الأعلى.';
  }

  @override
  String get insightOptimizationTitle => 'حافظ على ترتيب MapNote';

  @override
  String get insightOptimizationBody =>
      'القائمة الكبيرة تُحمّل أبطأ. راجع الأماكن المكررة أو غير المستخدمة واحذف ما لا تحتاجه.';

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
  String get savedPlacesVaultLock => 'قفل الخزنة';

  @override
  String get savedPlacesVaultEmpty => 'لا توجد أماكن مشفّرة بعد';

  @override
  String get savedPlacesVaultEmptyMessage =>
      'انقل مكانًا محفوظًا إلى الخزنة لحمايته بقفل جهازك.';

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
    return '\"$name\" على بعد $distance م';
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
}
