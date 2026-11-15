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
      title: Text(l10n.contactDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.importFromTeamContacts),
                Tab(text: l10n.newEntry),
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
    final l10n = AppLocalizations.of(context);
    if (_teamContacts.isEmpty) {
      return Center(child: Text(l10n.noTeamContactsAvailable));
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
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.fieldName,
              hintText: l10n.fieldName,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: l10n.managerPhone,
              hintText: l10n.managerPhone,
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            decoration: InputDecoration(labelText: l10n.contactRole),
            items: List.generate(_roles.length, (index) {
              return DropdownMenuItem<String>(
                value: _roles[index],
                child: Text(_roleLabel(l10n, _roles[index])),
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

  String _roleLabel(AppLocalizations l10n, String role) {
    switch (role) {
      case 'supervisor':
        return l10n.roleSupervisor;
      case 'support':
        return l10n.roleSupport;
      case 'staff':
        return l10n.roleStaff;
      case 'manager':
      default:
        return l10n.roleManager;
    }
  }
}
