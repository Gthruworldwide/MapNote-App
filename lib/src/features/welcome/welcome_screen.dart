import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';

/// Welcome / Onboarding screen shown on first launch or after edition change.
///
/// Displays the edition type (Work vs AutoMotion) and primary actions
/// clearly, without clutter. The user can dismiss this and return to the
/// home screen at any time.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isAutoMotionEdition = ref.watch(automotionAvailableProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Logo / Brand mark
                const SizedBox(height: 48),
                // Edition title
                Text(
                  isAutoMotionEdition
                      ? l10n.welcomeEditionAutoMotion
                      : l10n.welcomeEditionWork,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Edition subtitle
                Text(
                  isAutoMotionEdition
                      ? l10n.welcomeEditionAutoMotionSubtitle
                      : l10n.welcomeEditionWorkSubtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Main subtitle
                Text(
                  l10n.welcomeSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Primary CTA
                FilledButton.tonal(
                  onPressed: () {
                    // Navigate to home screen, dismissing the welcome
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (route) => false,
                    );
                  },
                  child: Text(l10n.welcomeGetStarted),
                ),
                const SizedBox(height: 16),
                // Skip button
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/',
                      (route) => false,
                    );
                  },
                  child: Text(l10n.sectionAccount), // Reusing an existing key for "Skip"
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}