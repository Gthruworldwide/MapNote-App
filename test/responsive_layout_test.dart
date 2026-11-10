import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routenote/src/core/responsive/responsive_layout.dart';

void main() {
  testWidgets('ResponsiveBreakpoints correctly categorises screen sizes', (tester) async {
    Widget buildTestWidget(Size size, WidgetBuilder builder) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(builder: builder),
        ),
      );
    }

    // Mobile screen (< 600)
    await tester.pumpWidget(
      buildTestWidget(const Size(400, 800), (context) {
        expect(ResponsiveBreakpoints.isMobile(context), isTrue);
        expect(ResponsiveBreakpoints.isTablet(context), isFalse);
        expect(ResponsiveBreakpoints.isDesktop(context), isFalse);
        return const SizedBox();
      }),
    );

    // Tablet screen (600 - 1024)
    await tester.pumpWidget(
      buildTestWidget(const Size(800, 1024), (context) {
        expect(ResponsiveBreakpoints.isMobile(context), isFalse);
        expect(ResponsiveBreakpoints.isTablet(context), isTrue);
        expect(ResponsiveBreakpoints.isDesktop(context), isFalse);
        return const SizedBox();
      }),
    );

    // Desktop screen (> 1024)
    await tester.pumpWidget(
      buildTestWidget(const Size(1440, 900), (context) {
        expect(ResponsiveBreakpoints.isMobile(context), isFalse);
        expect(ResponsiveBreakpoints.isTablet(context), isFalse);
        expect(ResponsiveBreakpoints.isDesktop(context), isTrue);
        return const SizedBox();
      }),
    );
  });

  testWidgets('ResponsiveNavigationWrapper renders NavigationRail on desktop', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveNavigationWrapper(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          titleWidget: const Text('MapNote'),
          destinations: const [
            NavigationDestinationData(
              label: 'AutoMotion',
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore,
            ),
            NavigationDestinationData(
              label: 'Work Edition',
              icon: Icons.alt_route_outlined,
              selectedIcon: Icons.alt_route,
            ),
          ],
          child: const Text('Desktop Body'),
        ),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('MapNote'), findsOneWidget);
    expect(find.text('Desktop Body'), findsOneWidget);
  });

  testWidgets('ResponsiveNavigationWrapper renders NavigationBar on mobile', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveNavigationWrapper(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            NavigationDestinationData(
              label: 'AutoMotion',
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore,
            ),
            NavigationDestinationData(
              label: 'Work Edition',
              icon: Icons.alt_route_outlined,
              selectedIcon: Icons.alt_route,
            ),
          ],
          child: const Text('Mobile Body'),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Mobile Body'), findsOneWidget);
  });

  testWidgets('ResponsiveAppScaffold renders NavigationRail on desktop', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveAppScaffold(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            ResponsiveDestination(icon: Icon(Icons.explore), label: 'Track'),
            ResponsiveDestination(icon: Icon(Icons.map), label: 'Map'),
          ],
          body: const Text('Desktop Content'),
        ),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Desktop Content'), findsOneWidget);
  });

  testWidgets('ResponsiveAppScaffold renders NavigationBar on mobile', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveAppScaffold(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            ResponsiveDestination(icon: Icon(Icons.explore), label: 'Track'),
            ResponsiveDestination(icon: Icon(Icons.map), label: 'Map'),
          ],
          body: const Text('Mobile Content'),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Mobile Content'), findsOneWidget);
  });

  testWidgets('DesktopMasterDetailLayout renders master and detail side-by-side on desktop', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopMasterDetailLayout(
            master: Text('Master List'),
            detail: Text('Detail View'),
          ),
        ),
      ),
    );

    expect(find.text('Master List'), findsOneWidget);
    expect(find.text('Detail View'), findsOneWidget);
  });

  testWidgets('DesktopMasterDetailLayout renders only master on mobile', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopMasterDetailLayout(
            master: Text('Master List'),
            detail: Text('Detail View'),
          ),
        ),
      ),
    );

    expect(find.text('Master List'), findsOneWidget);
    expect(find.text('Detail View'), findsNothing);
  });
}
