import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../admin/admin_approval_screen.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/place.dart';
import '../../../data/models/station_manager.dart';
import '../../../providers/app_providers.dart';

/// A modern contact dialog with 2 tabs: Import from team contacts and New Entry.
/// Supports role tagging (manager, supervisor, support, staff).
class ModernContactDialog extends StatefulWidget {
  const ModernContactDialog({
    super.key,
    required this.place,
  });

  final Place place;

  @override
  State<ModernContactDialog> createState() => _ModernContactDialogState();
}

class _ModernContactDialogState extends State<ModernContactDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  String _selectedRole = 'manager';

  final List<String> _roles = ['manager', 'supervisor', 'support', 'staff'];
  final List<String> _roleLabels = [
    '🏢 مدير محطة',
    '👷 مشرف محطة',
    '🎧 مسؤول دعم / عمليات',
    '💼 موظف شركة',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Places display contacts from the real model fields
    // (displayName/phoneNumber and managers), not managerName/managerPhone.
    final String initialName = widget.place.displayName ?? widget.place.managerName ?? '';
    final String initialPhone = widget.place.phoneNumber ?? '';
    _nameController.text = initialName;
    _phoneController.text = initialPhone;
    if (widget.place.managers.isNotEmpty && initialPhone.isEmpty) {
      _phoneController.text = widget.place.managers.first.phone ?? '';
    }
  }

  Future<void> _submitContact() async {
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء إدخال الاسم ورقم الهاتف')),
        );
      }
      return;
    }

    try {
      // Get Hive database from provider
      final ProviderContainer container = ProviderScope.containerOf(context);
      final hiveDb = container.read(hiveDatabaseProvider);

      // Append the new contact while preserving all existing managers,
      // skipping duplicates by (name, phone).
      final newManager = StationManager(name: name, phone: phone);
      final List<StationManager> updatedManagers = List<StationManager>.from(widget.place.managers);
      final bool alreadyManaged = updatedManagers.any(
        (m) => StationManager.isDuplicate(newManager, m),
      );
      if (!alreadyManaged) {
        updatedManagers.add(newManager);
      }

      final updatedPlace = widget.place.copyWith(
        displayName: (widget.place.displayName?.isNotEmpty ?? false)
            ? widget.place.displayName
            : name,
        phoneNumber: (widget.place.phoneNumber?.isNotEmpty ?? false)
            ? widget.place.phoneNumber
            : phone,
        managers: updatedManagers,
      );

      // Admins apply immediately; non-admins keep the change pending until an
      // admin approves it in Firestore.
      final isAdmin = container.read(adminSession);

      if (isAdmin) {
        // Admin: apply directly to local Hive and Firestore master stations.
        final placeData = updatedPlace.toMap();
        await hiveDb.placesBox.put(widget.place.id, placeData);
        await hiveDb.stationBox.put(widget.place.id, placeData);

        await FirebaseFirestore.instance
            .collection('master_stations')
            .doc(widget.place.id)
            .set({
          'stationId': widget.place.id,
          'managerName': name,
          'managerPhone': phone,
          'managerRole': _selectedRole,
          'status': 'approved',
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Refresh placesProvider for instant UI
        container.invalidate(placesProvider);
      }

      // ALWAYS send the proposal to pending_updates for sync/audit trail.
      // Admin submissions land directly approved; non-admin submissions stay
      // pending. Non-admin submissions MUST NEVER touch local Hive (only the
      // admin branch above may). Standardized payload (top-level + proposedData
      // parity) so AdminApprovalScreen renders details without "Incomplete proposal".
      final String stationId = widget.place.id;
      final String stationName = widget.place.name;
      final String status = isAdmin ? 'approved' : 'pending';
      await FirebaseFirestore.instance.collection('pending_updates').add({
        'stationId': stationId,
        'stationName': stationName,
        'type': 'contact_update',
        'managerName': name,
        'managerPhone': phone,
        'managerRole': _selectedRole,
        'proposedData': {
          'stationId': stationId,
          'stationName': stationName,
          'managerName': name,
          'managerPhone': phone,
          'managerRole': _selectedRole,
          'displayName': name,
          'phoneNumber': phone,
        },
        'status': status,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).pop(true);
        if (isAdmin) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حفظ وتحديث جهة الاتصال بنجاح')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال الاقتراح للأدمن للموافقة')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ جهة الاتصال: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickPhoneContact() async {
    // No native contact-picker plugin is bundled (pubspec). Request permission
    // and guide the user; the icon provides a discoverable entry point.
    final status = await Permission.contacts.request();
    if (!mounted) return;
    if (status.isGranted) {
      _tabController.animateTo(1);
      _phoneFocusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال جهة الاتصال يدوياً'),
        ),
      );
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'يرجى منح صلاحية الوصول لجهات الاتصال لاستيراد الأرقام تلقائياً',
          ),
          action: SnackBarAction(
            label: 'فتح الإعدادات',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'يرجى منح صلاحية الوصول لجهات الاتصال لاستيراد الأرقام تلقائياً',
          ),
          action: SnackBarAction(
            label: 'فتح الإعدادات',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final EdgeInsets viewInsets = MediaQuery.viewInsetsOf(context);
    final double availableHeight =
        MediaQuery.sizeOf(context).height - viewInsets.bottom - 96;
    final double maxBodyHeight =
        availableHeight.clamp(220.0, MediaQuery.sizeOf(context).height * 0.72);

    return AlertDialog(
      title: const Text('إضافة / اقتراح جهة اتصال'),
      scrollable: false,
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      content: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: viewInsets.bottom > 0 ? 0 : 0),
        child: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxBodyHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'استيراد من أرقام الفريق'),
                    Tab(text: 'إدخال جديد'),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildImportTab(context),
                      _buildNewEntryTab(context),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Actions pinned at the bottom of the dialog layout.
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitContact,
                      child: Text(l10n.confirm),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: const <Widget>[],
    );
  }

  Widget _buildImportTab(BuildContext context) {
    return const Center(
      child: Text('لا توجد جهات اتصال محفوظة في فريق العمل'),
    );
  }

  Widget _buildNewEntryTab(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Device contacts import button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.contacts),
              label: const Text('اختر من جهات اتصال الهاتف'),
              onPressed: _pickPhoneContact,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _phoneFocusNode.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'الاسم الكامل',
              hintText: 'الاسم الكامل',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'رقم الهاتف',
              hintText: 'رقم الهاتف',
              suffixIcon: IconButton(
                icon: const Icon(Icons.contacts_outlined),
                tooltip: 'اختر من جهات الاتصال',
                onPressed: _pickPhoneContact,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            decoration: const InputDecoration(
              labelText: 'تحديد الصفة/الوسم',
            ),
            items: List.generate(_roles.length, (index) {
              return DropdownMenuItem<String>(
                value: _roles[index],
                child: Text(_roleLabels[index]),
              );
            }),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedRole = value);
              }
            },
          ),
        ],
      ),
    );
  }
}