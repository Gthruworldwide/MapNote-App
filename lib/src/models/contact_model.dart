/// Model representing a device contact for linking to a place.
class ContactModel {
  /// Unique identifier for the contact (usually the raw contact ID).
  final String id;

  /// Display name of the contact.
  final String name;

  /// Phone number associated with the contact.
  final String phone;

  ContactModel({
    required this.id,
    required this.name,
    required this.phone,
  });
}