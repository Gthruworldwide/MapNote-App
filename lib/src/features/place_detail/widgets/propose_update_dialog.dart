import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../data/models/place.dart';

/// A dialog for proposing a manager/contact update for a station.
/// Features 2 tabs: Import from team contacts, and New Entry with role selector.
class ProposeUpdateDialog extends StatefulWidget {
  const ProposeUpdateDialog({
    super.key,
    required this.place,
    required this.onSubmitted,
  });

  final Place place;
  final void Function(String name, String phone, String role) onSubmitted;

  @override
  State<ProposeUpdateDialog> createState() => _ProposeUpdateDialogState();
}

class _ProposeUpdateDialogState extends State<ProposeUpdateDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _selectedRole = 'manager';

  final List<String> _roles = ['manager', 'supervisor', 'support', 'staff'];
  final List<String> _roleLabels = [
    'مدير محطة',
    'مشرف محطة',
    'مسؤول دعم / عمليات',
    'موظف شركة',
  ];

  // Simulated team contacts (in real app, fetch from master_stations)
  final List<Map<String, String>> _teamContacts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _nameController.text = widget.place.displayName ?? '';
    _phoneController.text = widget.place.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: const Text('إضافة / اقتراح جهة اتصال للمحطة'),
      content: SizedBox(
        width: double.maxFinite,
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
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Import from team contacts
                  _buildImportTab(context),
                  // Tab 2: New entry
                  _buildNewEntryTab(context),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onSubmitted(
              _nameController.text.trim(),
              _phoneController.text.trim(),
              _selectedRole,
            );
            Navigator.of(context).pop(true);
          },
          child: Text(l10n.confirm),
        ),
      ],
    );
  }

  Widget _buildImportTab(BuildContext context) {
    if (_teamContacts.isEmpty) {
      return const Center(
        child: Text('لا توجد جهات اتصال محفوظة في فريق العمل'),
      );
    }

    return ListView.builder(
      itemCount: _teamContacts.length,
      itemBuilder: (context, index) {
        final contact = _teamContacts[index];
        return ListTile(
          title: Text(contact['name'] ?? ''),
          subtitle: Text(contact['phone'] ?? ''),
          trailing: Text(contact['role'] ?? ''),
          onTap: () {
            setState(() {
              _nameController.text = contact['name'] ?? '';
              _phoneController.text = contact['phone'] ?? '';
              _selectedRole = contact['role'] ?? 'manager';
            });
            _tabController.animateTo(1);
          },
        );
      },
    );
  }

  Widget _buildNewEntryTab(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'الاسم الكامل',
              hintText: 'الاسم الكامل',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف / الواتساب',
              hintText: 'رقم الهاتف / الواتساب',
            ),
            keyboardType: TextInputType.phone,
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