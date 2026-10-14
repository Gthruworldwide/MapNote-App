import 'package:flutter/widgets.dart';

/// Navigator used for app-level navigation that originates outside the widget
/// tree — for example when another app shares a location with MapNote.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
