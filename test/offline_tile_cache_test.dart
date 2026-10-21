import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:routenote/src/services/offline_tile_cache_strategy.dart';

void main() {
  test('default max cache size is 100 MB', () {
    final OfflineTileCacheStrategy s = OfflineTileCacheStrategy();
    expect(s.maxCacheBytes, 100 * 1024 * 1024);
  });

  test('eviction policy is LRU', () {
    final OfflineTileCacheStrategy s = OfflineTileCacheStrategy();
    expect(s.evictionPolicy, 'lru');
  });

  test('shouldRenderFullPin true at zoom >= 12', () {
    final OfflineTileCacheStrategy s = OfflineTileCacheStrategy();
    expect(s.shouldRenderFullPin(12), isTrue);
    expect(s.shouldRenderFullPin(15), isTrue);
    expect(s.shouldRenderFullPin(11.9), isFalse);
    expect(s.shouldRenderFullPin(8), isFalse);
  });

  testWidgets('wrapPin wraps child in RepaintBoundary', (tester) async {
    final OfflineTileCacheStrategy s = OfflineTileCacheStrategy();
    await tester.pumpWidget(
      MaterialApp(home: s.wrapPin(const Text('pin'))),
    );
    expect(find.byType(RepaintBoundary), findsAtLeastNWidgets(1));
    expect(find.text('pin'), findsOneWidget);
  });

  testWidgets('buildDotMarker renders a small circle', (tester) async {
    final OfflineTileCacheStrategy s = OfflineTileCacheStrategy();
    await tester.pumpWidget(
      MaterialApp(home: s.buildDotMarker(color: Colors.red, size: 6)),
    );
    expect(find.byType(Container), findsOneWidget);
  });

  test('preloadTilesForPlaces completes without error', () async {
    final OfflineTileCacheStrategy s = OfflineTileCacheStrategy();
    await s.preloadTilesForPlaces(const [], minZoom: 12, maxZoom: 14);
    // no throw
  });
}
