import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/wallflower.dart';
import 'package:wallflower_example/config.dart';
import 'package:wallflower_example/scenes/scene_view.dart';
import 'package:wallflower_example/settings_app.dart';

void main() {
  group('DemoConfig', () {
    test('round-trips through JSON', () {
      const config = DemoConfig(
        scene: DemoScene.clock,
        palette: DemoPalette.glacier,
        intensity: 0.25,
        tilt: false,
      );
      expect(DemoConfig.fromJson(config.toJson()), config);
    });

    test('falls back to defaults for missing or unknown values', () {
      expect(
        DemoConfig.fromJson({'scene': 'aquarium', 'intensity': 'high'}),
        const DemoConfig(),
      );
      expect(DemoConfig.fromJson({'intensity': 3}).intensity, 1);
    });
  });

  // A battery check: after a swipe or a tap, every scene must come to rest
  // and stop scheduling frames. pumpAndSettle fails if frames never stop.
  for (final scene in DemoScene.values) {
    testWidgets('${scene.label} settles after input', (tester) async {
      final data = ValueNotifier(
        const WallpaperData(visible: true, pageStep: Offset(0.25, 0)),
      );
      final taps = StreamController<Offset>.broadcast();
      addTearDown(data.dispose);
      addTearDown(taps.close);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 860)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: WallpaperScope(
              data: data,
              child: SceneView(
                config: DemoConfig(scene: scene),
                taps: taps.stream,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      data.value = data.value.copyWith(pageOffset: const Offset(0.5, 0));
      taps.add(const Offset(200, 400));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);

      // Hidden: the clock stops its timer, so the test ends cleanly.
      data.value = data.value.copyWith(visible: false);
      await tester.pump();
    });
  }

  group('settings app', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('wallflower/app'), (
            call,
          ) async {
            calls.add(call);
            return switch (call.method) {
              'isActive' => true,
              'send' => 1,
              _ => null,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('wallflower/app'),
            null,
          );
    });

    testWidgets('saves the picked scene as the wallpaper config', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const SettingsApp());
      await tester.pumpAndSettle();
      expect(find.text('This is your live wallpaper'), findsOneWidget);

      await tester.tap(find.text('Particles'));
      await tester.pumpAndSettle();

      final saved = calls.lastWhere((call) => call.method == 'setConfig');
      final json = (saved.arguments as Map)['config'] as String;
      expect(json, contains('"scene":"particles"'));
    });
  });
}
