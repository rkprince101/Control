import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:control/ui/expressive_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  double? value,
  bool animate = true,
  WaveMotion? motion,
  WaveMotion? scope,
  bool reducedMotion = false,
  bool tickerEnabled = true,
  TextDirection direction = TextDirection.ltr,
  double width = 120,
  double height = 20,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: TickerMode(
      enabled: tickerEnabled,
      child: Directionality(
        textDirection: direction,
        child: Center(
          child: SizedBox(
            width: width,
            child: WaveMotionScope(
              motion: scope ?? WaveMotion.calm,
              child: ExpressiveProgress(
                value: value,
                animate: animate,
                motion: motion,
                height: height,
                color: const Color(0xFFFF0000),
                trackColor: const Color(0xFF0000FF),
                semanticsLabel: 'Focus goal',
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byType(ExpressiveProgress),
        matching: find.byType(CustomPaint),
      ),
    )
    .painter!;

Future<ByteData> _pixels(WidgetTester tester) async {
  final painter = _painter(tester);
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(120, 20));
    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 20);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return data!;
  }))!;
}

bool _sameImage(ByteData a, ByteData b) {
  if (a.lengthInBytes != b.lengthInBytes) return false;
  for (var i = 0; i < a.lengthInBytes; i++) {
    // Anti-aliasing can land a unit either way after a full period.
    if ((a.getUint8(i) - b.getUint8(i)).abs() > 8) return false;
  }
  return true;
}

/// Any red in column [x], wherever the wave has carried it.
bool _redColumn(ByteData data, int x) {
  for (var y = 0; y < 20; y++) {
    if (_red(data, x, y)) return true;
  }
  return false;
}

bool _red(ByteData data, int x, int y) {
  final offset = (y * 120 + x) * 4;
  return data.getUint8(offset) > 200 &&
      data.getUint8(offset + 2) < 50 &&
      data.getUint8(offset + 3) > 100;
}

void main() {
  testWidgets('semantics exposes label and clamped percentage', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final (value, expected) in [
      (-2.0, '0%'),
      (0.0, '0%'),
      (0.426, '43%'),
      (1.0, '100%'),
      (2.0, '100%'),
      (double.nan, '0%'),
      (double.infinity, '100%'),
      (double.negativeInfinity, '0%'),
    ]) {
      await tester.pumpWidget(_host(value: value));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getSemantics(find.byType(ExpressiveProgress)),
        matchesSemantics(label: 'Focus goal', value: expected),
      );
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('a partial bar keeps its wave travelling', (tester) async {
    await tester.pumpWidget(_host(value: 0.5));
    await tester.pump(const Duration(milliseconds: 16));
    var previous = _painter(tester);
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      final next = _painter(tester);
      expect(next.shouldRepaint(previous), isTrue, reason: 'frame $frame');
      previous = next;
    }
    expect(tester.binding.hasScheduledFrame, isTrue);
    // Still travelling long after any value transition would have finished.
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('the wave has come back round after one period', (tester) async {
    for (final motion in [WaveMotion.calm, WaveMotion.lively]) {
      await tester.pumpWidget(_host(value: 0.5, motion: motion));
      await tester.pump();
      final start = await _pixels(tester);
      await tester.pump(motion.period! ~/ 2);
      final half = await _pixels(tester);
      await tester.pump(motion.period! ~/ 2);
      final full = await _pixels(tester);
      expect(_sameImage(start, half), isFalse, reason: '$motion half period');
      expect(_sameImage(start, full), isTrue, reason: '$motion full period');
    }
    expect(
      WaveMotion.lively.period! < WaveMotion.calm.period!,
      isTrue,
      reason: 'lively is the faster of the two',
    );
  });

  testWidgets('empty and finished bars have no wave to move', (tester) async {
    for (final value in [0.0, 1.0]) {
      await tester.pumpWidget(_host(value: value));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse, reason: '$value');
    }
  });

  testWidgets('Off from the scope holds the wave still and settles', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 0.2, scope: WaveMotion.off));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    final initial = _painter(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_painter(tester).shouldRepaint(initial), isFalse);

    // Off also means value changes land without easing.
    await tester.pumpWidget(_host(value: 0.8, scope: WaveMotion.off));
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Turning motion back on picks the wave up again.
    await tester.pumpWidget(_host(value: 0.8, scope: WaveMotion.lively));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('value changes ease to the new length while the wave moves', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 0.2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(_host(value: 0.8));
    await tester.pump(const Duration(milliseconds: 120));
    final middle = await _pixels(tester);
    // Part way: the stroke has passed 0.2 of the width (x = 25) but not
    // reached 0.8 (x = 95).
    expect(_redColumn(middle, 35), isTrue);
    expect(_redColumn(middle, 90), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    final after = await _pixels(tester);
    expect(_redColumn(after, 90), isTrue);
  });

  testWidgets('an explicit motion wins over the scope', (tester) async {
    await tester.pumpWidget(
      _host(value: 0.5, scope: WaveMotion.off, motion: WaveMotion.calm),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(
      _host(value: 0.5, scope: WaveMotion.lively, motion: WaveMotion.off),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('determinate waves stop for TickerMode and reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(_host(value: 0.5, tickerEnabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host(value: 0.5, reducedMotion: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion shows a static partial loading wave', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(reducedMotion: true));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byType(ExpressiveProgress)),
      matchesSemantics(label: 'Focus goal', value: 'Loading'),
    );
    final initial = _painter(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_painter(tester).shouldRepaint(initial), isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final data = await _pixels(tester);
    expect(_red(data, 9, 12), isTrue);
    expect(_red(data, 85, 10), isFalse);
    semantics.dispose();
  });

  testWidgets('indeterminate motion stops for TickerMode and reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    final initial = _painter(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_painter(tester).shouldRepaint(initial), isTrue);
    await tester.pumpWidget(_host(tickerEnabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(_host(reducedMotion: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('animate false disables both loading and value transitions', (
    tester,
  ) async {
    await tester.pumpWidget(_host(animate: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host(value: 0.2, animate: false));
    await tester.pumpWidget(_host(value: 0.9, animate: false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    final initial = _painter(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_painter(tester).shouldRepaint(initial), isFalse);
  });

  testWidgets('reduced motion also skips determinate transitions', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 0.1, reducedMotion: true));
    await tester.pumpWidget(_host(value: 0.9, reducedMotion: true));
    final initial = _painter(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_painter(tester).shouldRepaint(initial), isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('wave, track gap and stop dot mirror in RTL', (tester) async {
    await tester.pumpWidget(_host(value: 0.5, animate: false));
    final ltr = await _pixels(tester);
    expect(_red(ltr, 9, 12), isTrue);
    expect(_red(ltr, 110, 12), isFalse);
    // Active endpoint is x=60; the rounded track starts at x=66.
    expect(ltr.getUint8((10 * 120 + 64) * 4 + 3), 0);
    expect(_red(ltr, 118, 10), isTrue);
    await tester.pumpWidget(
      _host(value: 0.5, animate: false, direction: TextDirection.rtl),
    );
    final rtl = await _pixels(tester);
    expect(_red(rtl, 110, 12), isTrue);
    expect(_red(rtl, 9, 12), isFalse);
    expect(_red(rtl, 1, 10), isTrue);
  });

  testWidgets(
    'zero draws only track and stop; full draws a flat active stroke',
    (tester) async {
      await tester.pumpWidget(_host(value: 0, animate: false));
      final zero = await _pixels(tester);
      expect(_red(zero, 10, 10), isFalse);
      expect(_red(zero, 60, 10), isFalse);
      expect(_red(zero, 118, 10), isTrue);
      await tester.pumpWidget(_host(value: 1, animate: false));
      final full = await _pixels(tester);
      expect(_red(full, 10, 10), isTrue);
      expect(_red(full, 60, 10), isTrue);
      expect(_red(full, 118, 10), isTrue);
      expect(_red(full, 9, 13), isFalse);
    },
  );

  testWidgets('wave amplitude tapers as completion approaches', (tester) async {
    await tester.pumpWidget(_host(value: 0.5, animate: false));
    final middle = await _pixels(tester);
    expect(_red(middle, 9, 13), isTrue);
    await tester.pumpWidget(_host(value: 0.99, animate: false));
    final nearFull = await _pixels(tester);
    expect(_red(nearFull, 9, 13), isFalse);
    expect(_red(nearFull, 9, 10), isTrue);
  });

  testWidgets('loading settles once the bar is finished', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(_host(value: 0.6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(_host(value: 1));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('tiny widths and heights never overflow', (tester) async {
    for (final width in [0.0, 1.0, 3.0, 8.0, 20.0]) {
      for (final value in <double?>[0, 0.5, 1, null]) {
        for (final direction in TextDirection.values) {
          await tester.pumpWidget(
            _host(
              width: width,
              height: width < 3 ? width : 20,
              value: value,
              animate: false,
              direction: direction,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'width=$width, value=$value, direction=$direction',
          );
        }
      }
    }
  });
}
