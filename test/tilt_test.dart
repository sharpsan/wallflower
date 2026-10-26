import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/src/wallpaper/tilt.dart';
import 'package:wallflower/wallflower.dart';

void main() {
  late List<bool> demand;
  late TiltController tilt;

  setUp(() {
    demand = [];
    tilt = TiltController(onDemandChanged: (wanted, _) => demand.add(wanted));
  });

  tearDown(() => tilt.dispose());

  Widget app(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: WallpaperScope(
      data: ValueNotifier(const WallpaperData(visible: true)),
      tilt: tilt,
      child: child,
    ),
  );

  group('demand', () {
    testWidgets('a widget reading tilt turns the sensor on while mounted', (
      tester,
    ) async {
      final reader = Builder(
        builder: (context) => Text('${WallpaperTilt.of(context)}'),
      );

      await tester.pumpWidget(app(const SizedBox()));
      expect(demand, isEmpty);

      await tester.pumpWidget(app(Column(children: [reader])));
      expect(demand, [true]);

      await tester.pumpWidget(app(const SizedBox()));
      expect(demand, [true, false]);
    });

    test('listeners on the listenable count as readers', () {
      void listener() {}
      tilt.addListener(listener);
      tilt.addListener(listener);
      tilt.removeListener(listener);
      expect(demand, [true]);

      tilt.removeListener(listener);
      expect(demand, [true, false]);

      // Removing an unknown listener is harmless.
      tilt.removeListener(() {});
      expect(demand, [true, false]);
    });

    test('changing settings while wanted re-sends the demand', () {
      final sent = <WallpaperTiltSettings>[];
      final controller = TiltController(
        onDemandChanged: (wanted, settings) => sent.add(settings),
      );
      addTearDown(controller.dispose);
      controller.addListener(() {});
      const slower = WallpaperTiltSettings(
        samplingPeriod: Duration(milliseconds: 60),
      );

      controller.settings = slower;

      expect(sent.last, slower);
    });
  });

  group('filtering', () {
    testWidgets('a tilt moves the value, then it re-centers', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      tilt.setVisible(true);

      // Held still: the first sample becomes the neutral position.
      tilt.addSample(const Offset(0, 0.8));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tilt.value, Offset.zero);

      // Dip the right edge: the up vector's x goes negative.
      tilt.addSample(const Offset(-0.175, 0.8));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tilt.value.dx, greaterThan(0.3));
      expect(tilt.value.dy, 0);

      // Holding the new angle, the neutral position catches up.
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tilt.value.dx, closeTo(0, 0.01));

      // Hiding stops the filter.
      tilt.setVisible(false);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a display rotation re-centers at once', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      tilt.settings = const WallpaperTiltSettings(recenter: null);
      tilt.setVisible(true);

      tilt.addSample(const Offset(0, 0.8));
      await tester.pump(const Duration(milliseconds: 16));
      // Turned to landscape: the same pose reads along the other axis.
      tilt.addSample(const Offset(0.8, 0), quarterTurns: 1);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tilt.value, Offset.zero);
      tilt.setVisible(false);
    });

    testWidgets('values are clamped to the range', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      tilt.settings = const WallpaperTiltSettings(
        recenter: null,
        smoothing: Duration.zero,
      );
      tilt.setVisible(true);

      tilt.addSample(const Offset(0, 0.5));
      await tester.pump(const Duration(milliseconds: 16));
      tilt.addSample(const Offset(-1, -0.5));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(tilt.value, const Offset(1, 1));
    });

    testWidgets('nothing is filtered while hidden', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));

      tilt.addSample(const Offset(0, 0.5));
      tilt.addSample(const Offset(-0.3, 0.5));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tilt.value, Offset.zero);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('the ticker stops once settled', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      tilt.setVisible(true);
      tilt.addSample(const Offset(0.1, 0.7));
      tilt.addSample(const Offset(0.2, 0.7));

      for (var i = 0; i < 1000; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  testWidgets('WallpaperTilt.of is zero without a tilt source', (tester) async {
    Offset? read;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          read = WallpaperTilt.of(context);
          return const SizedBox();
        },
      ),
    );

    expect(read, Offset.zero);
  });

  testWidgets('a fixed tilt listenable drives previews', (tester) async {
    final fixed = ValueNotifier(const Offset(0.5, -0.25));
    addTearDown(fixed.dispose);
    Offset? read;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WallpaperScope(
          data: ValueNotifier(const WallpaperData()),
          tilt: fixed,
          child: Builder(
            builder: (context) {
              read = WallpaperTilt.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(read, const Offset(0.5, -0.25));

    fixed.value = Offset.zero;
    await tester.pump();
    expect(read, Offset.zero);
  });
}
