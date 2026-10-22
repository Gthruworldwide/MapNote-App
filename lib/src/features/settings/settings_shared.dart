import 'package:flutter/material.dart';

/// Shared card container used by every settings sub-screen.
class SettingsSection extends StatelessWidget {
  const SettingsSection({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(child: child),
        ],
      ),
    );
  }
}

/// Stacks the sub-cards of a consolidated settings card.
Widget grouped(List<Widget> parts) {
  final List<Widget> children = <Widget>[];
  for (int i = 0; i < parts.length; i++) {
    if (i > 0) {
      children.add(const Divider(height: 1, indent: 16, endIndent: 16));
    }
    children.add(parts[i]);
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

/// A sub-header inside a consolidated card.
Widget subHeader(BuildContext context, String title) {
  final ThemeData theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Text(
      title,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// A label/value row with a status colour.
class StatusRow extends StatelessWidget {
  const StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = ok
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// One option in the theme-mode selector.
class ThemeChoice extends StatelessWidget {
  const ThemeChoice({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final IconData icon;
  final ThemeMode value;
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: value == selected,
      onSelected: (_) => onSelected(value),
    );
  }
}
