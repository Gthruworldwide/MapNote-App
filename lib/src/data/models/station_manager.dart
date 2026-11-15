/// A manager assigned to a fuel station, shipped with the seeded catalogue.
///
/// Kept deliberately tiny and value-typed: it is what the support rep needs on
/// the place-detail screen (a name to call and, once the phone sheet is filled
/// in, a number to dial). It carries no account id, email or coordinates.
class StationManager {
  const StationManager({required this.name, this.phone});

  /// The manager's full name as it appears in the station sheet.
  final String name;

  /// Optional phone number. The first catalogue has none — the manager sheet
  /// has no phone column — so every caller must handle a null/blank value
  /// instead of rendering a dead "call" button.
  final String? phone;

  /// Whether this manager can actually be contacted right now.
  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;

  /// Whether [candidate] duplicates [existing] on the (name, phone) identity
  /// used for manager deduplication. Comparison is trimmed on both sides, so
  /// `"  احمد  "` and `"احمد"` are the same contact.
  static bool isDuplicate(StationManager candidate, StationManager existing) {
    return candidate.name.trim() == existing.name.trim() &&
        (candidate.phone ?? '').trim() == (existing.phone ?? '').trim();
  }

  /// Returns [managers] with duplicates removed, preserving first-occurrence
  /// order. The input list is not mutated.
  static List<StationManager> withoutDuplicates(
    List<StationManager> managers,
  ) {
    final List<StationManager> unique = <StationManager>[];
    for (final StationManager manager in managers) {
      final bool duplicate = unique.any(
        (StationManager existing) => isDuplicate(manager, existing),
      );
      if (!duplicate) {
        unique.add(manager);
      }
    }
    return List<StationManager>.unmodifiable(unique);
  }

  StationManager copyWith({String? name, String? phone}) => StationManager(
        name: name ?? this.name,
        phone: phone ?? this.phone,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'phone': phone,
      };

  factory StationManager.fromMap(Map<String, dynamic> map) {
    final String name = map['name']?.toString().trim() ?? '';
    final String phone = map['phone']?.toString().trim() ?? '';
    return StationManager(name: name, phone: phone.isEmpty ? null : phone);
  }

  @override
  bool operator ==(Object other) =>
      other is StationManager && other.name == name && other.phone == phone;

  @override
  int get hashCode => Object.hash(name, phone);

  @override
  String toString() => 'StationManager($name, phone: $phone)';
}
