import 'package:intl/intl.dart';

/// Formats a UTC [dateTime] in the user's locale (e.g. "Oct 9, 2026, 5:30 PM").
String formatDateTime(DateTime dateTime, String locale) {
  final DateFormat format = DateFormat.yMMMd(locale).add_jm();
  return format.format(dateTime.toLocal());
}

/// Formats the date part of [dateTime] in the user's locale (e.g. "Oct 9, 2026").
String formatDate(DateTime dateTime, String locale) {
  return DateFormat.yMMMd(locale).format(dateTime.toLocal());
}
