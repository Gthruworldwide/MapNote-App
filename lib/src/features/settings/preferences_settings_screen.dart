import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../core/config/app_config.dart';
import '../../core/config/preferred_nav_app.dart';
import '../../data/local/settings_repository.dart';
import '../../providers/app_providers.dart';
import '../automotion/widgets/auto_motion_export_sheet.dart';
import 'settings_shared.dart';

/// Preferences settings: navigation app, language, theme, font scale, haptics,
/// density, tile cache, offline maps and Smart Insights.
class PreferencesSettingsScreen extends ConsumerWidget {
  const PreferencesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale? locale = ref.watch(localeControllerProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final FontScalePreset fontScale = ref.watch(fontScaleProvider);
    final PreferredNavApp navApp = ref.watch(preferredNavAppProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionPreferences)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SettingsSection(
            title: l10n.sectionPreferences,
            child: _buildPreferencesCard(
              context,
              ref,
              l10n,
              locale,
              themeMode,
              navApp,
              fontScale,
            ),
          ),
          SettingsSection(
            title: l10n.sectionSmartInsights,
            child: _buildAgentCard(context, ref, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Locale? locale,
    ThemeMode themeMode,
    PreferredNavApp navApp,
    FontScalePreset fontScale,
  ) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(l10n.selectLanguage),
            trailing: DropdownButton<Locale?>(
              value: locale,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<Locale?>>[
                DropdownMenuItem<Locale?>(
                  value: null,
                  child: Text(l10n.languageSystem),
                ),
                DropdownMenuItem<Locale?>(
                  value: const Locale('en'),
                  child: Text(l10n.languageEnglish),
                ),
                DropdownMenuItem<Locale?>(
                  value: const Locale('ar'),
                  child: Text(l10n.languageArabic),
                ),
              ],
              onChanged: (Locale? value) =>
                  ref.read(localeControllerProvider.notifier).setLocale(value),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.navigation_outlined),
            title: Text(l10n.preferredNavApp),
            subtitle: Text(l10n.preferredNavAppSubtitle),
            trailing: DropdownButton<PreferredNavApp>(
              value: navApp,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<PreferredNavApp>>[
                DropdownMenuItem<PreferredNavApp>(
                  value: PreferredNavApp.system,
                  child: Text(l10n.navAppSystem),
                ),
                DropdownMenuItem<PreferredNavApp>(
                  value: PreferredNavApp.googleMaps,
                  child: Text(l10n.navAppGoogleMaps),
                ),
                DropdownMenuItem<PreferredNavApp>(
                  value: PreferredNavApp.waze,
                  child: Text(l10n.navAppWaze),
                ),
              ],
              onChanged: (PreferredNavApp? value) {
                if (value != null) {
                  ref
                      .read(preferredNavAppProvider.notifier)
                      .setPreferredApp(value);
                }
              },
            ),
          ),
          const Divider(height: 24),
          Row(
            children: <Widget>[
              const Icon(Icons.dark_mode_outlined, size: 20),
              const SizedBox(width: 12),
              Text(l10n.appearance, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ThemeChoice(
                label: l10n.themeSystem,
                icon: Icons.brightness_auto,
                value: ThemeMode.system,
                selected: themeMode,
                onSelected: (ThemeMode value) =>
                    ref.read(themeModeProvider.notifier).setThemeMode(value),
              ),
              ThemeChoice(
                label: l10n.themeLight,
                icon: Icons.light_mode,
                value: ThemeMode.light,
                selected: themeMode,
                onSelected: (ThemeMode value) =>
                    ref.read(themeModeProvider.notifier).setThemeMode(value),
              ),
              ThemeChoice(
                label: l10n.themeDark,
                icon: Icons.dark_mode,
                value: ThemeMode.dark,
                selected: themeMode,
                onSelected: (ThemeMode value) =>
                    ref.read(themeModeProvider.notifier).setThemeMode(value),
              ),
            ],
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.text_fields),
            title: Text(l10n.fontScale),
            trailing: DropdownButton<FontScalePreset>(
              value: fontScale,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<FontScalePreset>>[
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.small,
                  child: Text(l10n.fontScaleSmall),
                ),
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.standard,
                  child: Text(l10n.fontScaleStandard),
                ),
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.large,
                  child: Text(l10n.fontScaleLarge),
                ),
                DropdownMenuItem<FontScalePreset>(
                  value: FontScalePreset.extraLarge,
                  child: Text(l10n.fontScaleExtraLarge),
                ),
              ],
              onChanged: (FontScalePreset? value) {
                if (value != null) {
                  ref.read(fontScaleProvider.notifier).setFontScale(value);
                }
              },
            ),
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.vibration),
            title: Text(l10n.hapticFeedback),
            value: ref.watch(settingsRepositoryProvider).isHapticFeedbackEnabled,
            onChanged: (bool value) =>
                ref.read(settingsRepositoryProvider).setHapticFeedbackEnabled(value),
          ),
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.density_medium),
            title: Text(l10n.uiDensityCompact),
            value: ref.watch(settingsRepositoryProvider).isUiDensityCompact,
            onChanged: (bool value) =>
                ref.read(settingsRepositoryProvider).setUiDensityCompact(value),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_download_outlined),
            title: Text(l10n.exportMotionData),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AutoMotionExportBottomSheet(),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: Text(l10n.tileCacheSize('0 MB')),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(l10n.clearTileCache),
            onTap: () => showDialog<void>(
              context: context,
              builder: (BuildContext ctx) => AlertDialog(
                title: Text(l10n.clearTileCache),
                content: Text(l10n.clearTileCache),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.clearTileCache)),
                      );
                    },
                    child: Text(l10n.delete),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.preloadOfflineMaps),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.offlineMapDownloaded)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool cloudAvailable = AppConfig.isGeminiConfigured;
    final bool insightsEnabled = ref.watch(smartInsightsEnabledProvider);
    final bool cloudEnabled = ref.watch(cloudAiEnabledProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.auto_awesome,
              color: theme.colorScheme.primary,
            ),
            title: Text(l10n.smartInsightsEnable),
            subtitle: Text(l10n.smartInsightsEnableSubtitle),
            value: insightsEnabled,
            onChanged: (bool value) => ref
                .read(smartInsightsEnabledProvider.notifier)
                .setEnabled(value),
          ),
          if (cloudAvailable) ...<Widget>[
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.cloud_outlined),
              title: Text(l10n.smartInsightsCloudAi),
              subtitle: Text(l10n.smartInsightsCloudAiSubtitle),
              value: cloudEnabled,
              onChanged: (bool value) =>
                  ref.read(cloudAiEnabledProvider.notifier).setEnabled(value),
            ),
          ],
        ],
      ),
    );
  }
}
