import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Raw RGBA pixels of a rendered SVG.
class _Raster {
  _Raster(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  int alphaAt(int x, int y) => pixels[(y * width + x) * 4 + 3];

  String rgbAt(int x, int y) => _rgbAt((y * width + x) * 4);

  /// How many fully opaque pixels carry exactly [rgb] (lowercase hex).
  int count(String rgb) {
    int total = 0;
    for (int i = 0; i < pixels.length; i += 4) {
      if (pixels[i + 3] >= 250 && _rgbAt(i) == rgb) {
        total++;
      }
    }
    return total;
  }

  String _rgbAt(int i) {
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '${hex(pixels[i])}${hex(pixels[i + 1])}${hex(pixels[i + 2])}';
  }

  /// Bounds of the inked pixels, as `[left, top, right, bottom]`.
  List<int> inkBounds() {
    int left = width;
    int top = height;
    int right = -1;
    int bottom = -1;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (alphaAt(x, y) < 250) {
          continue;
        }
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return <int>[left, top, right, bottom];
  }
}

Future<_Raster> _rasterSvg(
  WidgetTester tester, {
  required String svg,
  required double width,
  required double height,
}) async {
  // The default test surface is 800x600; the wordmark at 4x is wider than that,
  // and a constrained SizedBox would silently shrink it.
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: width,
            height: height,
            child: SvgPicture.string(svg),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final ui.Image image = (await tester.runAsync(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return boundary.toImage();
  }))!;
  final ByteData? data = await tester.runAsync<ByteData?>(
    () async => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return _Raster(
    image.width,
    image.height,
    data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

String _read(String asset) => File(asset).readAsStringSync();

/// `assets/brand/route_note_mark.svg` is cropped to `31.5 31.5 78.5 113`; the
/// tests below draw it at 4x, so a Figma user-space point maps to
/// `(point - 31.5) * 4` pixels.
int _px(double userUnits) => ((userUnits - 31.5) * 4).round();

void main() {
  const String mark = 'assets/brand/route_note_mark.svg';
  const String wordmark = 'assets/brand/route_note_wordmark.svg';

  testWidgets('the mark renders as vector with its chevron punched out', (
    WidgetTester tester,
  ) async {
    final _Raster raster = await _rasterSvg(
      tester,
      svg: _read(mark),
      width: 78.5 * 4,
      height: 113 * 4,
    );

    expect(raster.width, 314);
    expect(raster.height, 452);

    // The two brand colours are present: the blue pin and the cyan notebook.
    expect(raster.count('145cff'), greaterThan(90000));
    expect(raster.count('00cfff'), greaterThan(5000));

    // Mid-stroke on the chevron: transparent, so the backdrop shows through.
    expect(raster.alphaAt(_px(63.6923), _px(105.23095)), 0);
    // The pin body just above the chevron's vertex: solid blue.
    expect(raster.rgbAt(_px(70.7692), _px(100)), '145cff');
    // The middle of the pin's circular hole: transparent too.
    expect(raster.alphaAt(_px(70.7692), _px(65.8)), 0);
    // A notebook rule: cyan.
    expect(raster.rgbAt(_px(46.46), _px(122)), '00cfff');

    // The crop is the mark's ink plus a 0.5 unit bleed, so the ink lands just
    // inside the asset's edges: nothing is clipped, nothing is over-cropped.
    final List<int> bounds = raster.inkBounds();
    expect(bounds[0], 2);
    expect(bounds[1], 2);
    expect(bounds[2], closeTo(312, 1));
    expect(bounds[3], closeTo(450, 1));
  });

  testWidgets('the wordmark renders as vector, two-tone, uncropped', (
    WidgetTester tester,
  ) async {
    final _Raster raster = await _rasterSvg(
      tester,
      svg: _read(wordmark),
      width: 245 * 4,
      height: 113 * 4,
    );

    expect(raster.width, 980);
    expect(raster.height, 452);

    // "Route" in blue, "Note" in cyan - both render, neither is an outline.
    expect(raster.count('145cff'), greaterThan(20000));
    expect(raster.count('00cfff'), greaterThan(20000));

    // The crop leaves the whole wordmark inside the asset: the first glyph
    // starts at x = 136.898 and the last ends at x = 380.25.
    final List<int> bounds = raster.inkBounds();
    expect(bounds[0], closeTo(3.6, 1));
    expect(bounds[2], closeTo(977, 2));
  });
}
