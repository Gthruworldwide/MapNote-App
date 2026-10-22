import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../domain/services/vault_pin_verifier.dart';

/// Asks the user to type their vault PIN.
///
/// Returns the entered PIN, or `null` when the user cancels. The dialog only
/// *collects* the PIN: verifying it is the caller's job, so the same dialog
/// serves both "enter your PIN to unlock" and "choose a new PIN".
Future<String?> showVaultPinDialog(
  BuildContext context, {
  required AppLocalizations l10n,
  bool requireConfirmation = false,
  String? title,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _VaultPinDialog(
      l10n: l10n,
      requireConfirmation: requireConfirmation,
      title: title,
    ),
  );
}

/// The PIN entry dialog.
class _VaultPinDialog extends StatefulWidget {
  const _VaultPinDialog({
    required this.l10n,
    required this.requireConfirmation,
    this.title,
  });

  final AppLocalizations l10n;

  /// Whether a second "confirm" field is shown.
  final bool requireConfirmation;

  final String? title;

  @override
  State<_VaultPinDialog> createState() => _VaultPinDialogState();
}

class _VaultPinDialogState extends State<_VaultPinDialog> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final String pin = _pinController.text;
    if (!VaultPinPolicy.isValid(pin)) {
      setState(() => _error = widget.l10n.vaultPinTooShort);
      return;
    }
    if (widget.requireConfirmation && _confirmController.text != pin) {
      setState(() => _error = widget.l10n.vaultPinMismatch);
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppLocalizations l10n = widget.l10n;

    return AlertDialog(
      title: Text(widget.title ?? l10n.enterPin),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: VaultPinPolicy.maxLength,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(VaultPinPolicy.maxLength),
            ],
            decoration: InputDecoration(
              labelText: l10n.vaultPinLabel,
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => widget.requireConfirmation ? null : _submit(),
          ),
          if (widget.requireConfirmation) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: VaultPinPolicy.maxLength,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(VaultPinPolicy.maxLength),
              ],
              decoration: InputDecoration(
                labelText: l10n.vaultPinConfirmLabel,
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (widget.requireConfirmation) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              l10n.vaultPinHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
