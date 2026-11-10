import 'package:flutter/material.dart';

/// نقاط الكسر القياسية لتحديد حجم الشاشات (Responsive Breakpoints)
class ResponsiveBreakpoints {
  static const double mobileMax = 600.0;
  static const double tabletMax = 1024.0;
  static const double desktopLarge = 1280.0;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileMax;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileMax &&
      MediaQuery.of(context).size.width <= tabletMax;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width > tabletMax;
}

/// نموذج البيانات لتشغيل الوجهات الميدانية
class NavigationDestinationData {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;

  const NavigationDestinationData({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });
}

/// غلاف الملاحة التكيفي الشامل للتطبيق
class ResponsiveNavigationWrapper extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestinationData> destinations;
  final Widget child;
  final Widget? titleWidget;

  const ResponsiveNavigationWrapper({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.child,
    this.titleWidget,
  });

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    // 1. الشاشات الكبيرة والمكتب (Desktop & Tablet) -> NavigationRail جانبي
    if (screenWidth >= ResponsiveBreakpoints.mobileMax) {
      final bool isExtended = screenWidth >= ResponsiveBreakpoints.desktopLarge;

      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                extended: isExtended,
                leading: titleWidget != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: titleWidget,
                      )
                    : null,
                destinations: destinations
                    .map(
                      (item) => NavigationRailDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selectedIcon ?? item.icon),
                        label: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: ClipRect(
                child: child,
              ),
            ),
          ],
        ),
      );
    }

    // 2. الهواتف والشاشات الصغيرة (Mobile) -> NavigationBar سفلي
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.selectedIcon ?? item.icon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Destination item used by [ResponsiveAppScaffold].
class ResponsiveDestination {
  const ResponsiveDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
}

/// Adaptive navigation container providing [NavigationRail] on desktop/tablet
/// and [NavigationBar] on mobile devices.
class ResponsiveAppScaffold extends StatelessWidget {
  const ResponsiveAppScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    this.leading,
    this.trailing,
    this.appBar,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<ResponsiveDestination> destinations;
  final Widget body;
  final Widget? leading;
  final Widget? trailing;
  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    if (ResponsiveBreakpoints.isDesktop(context)) {
      final bool isExtended =
          MediaQuery.of(context).size.width >= ResponsiveBreakpoints.desktopLarge;

      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              extended: isExtended,
              leading: leading,
              trailing: trailing,
              destinations: destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon ?? d.icon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations
            .map(
              (d) => NavigationDestination(
                icon: d.icon,
                selectedIcon: d.selectedIcon ?? d.icon,
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

/// Two-pane / split view layout pattern for desktop and tablet screens.
/// On desktop screens, renders [master] and [detail] side-by-side.
/// On mobile screens, renders [master] (or [detail] if selected).
class DesktopMasterDetailLayout extends StatelessWidget {
  const DesktopMasterDetailLayout({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 380.0,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > ResponsiveBreakpoints.tabletMax) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: masterWidth,
                child: master,
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: detail,
              ),
            ],
          );
        }

        return master;
      },
    );
  }
}
