import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routenote/src/features/admin/admin_approval_screen.dart';

/// Provider that counts pending approval items in Firestore.
final pendingApprovalsCountProvider = StreamProvider<int>((ref) {
  return FirebaseFirestore.instance
      .collection('pending_updates')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
});

/// A card widget that provides entry to the Admin Approval Screen.
/// Shown at the top of the Home Screen for admin users.
class AdminApprovalCard extends ConsumerWidget {
  const AdminApprovalCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pendingCount = ref.watch(pendingApprovalsCountProvider).value ?? 0;

    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminApprovalScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Badge(
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                backgroundColor: Colors.redAccent,
                child: Icon(
                  Icons.admin_panel_settings,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Approval',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pendingCount > 0
                          ? '$pendingCount pending updates'
                          : 'Review pending station updates',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}