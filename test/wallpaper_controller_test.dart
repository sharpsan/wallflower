import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/src/protocol.dart';
import 'package:wallflower/src/wallpaper/wallpaper_controller.dart';
import 'package:wallflower/wallflower.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(wallpaperChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late WallpaperController controller;

  setUp(() {
    controller = WallpaperController();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    controller.dispose();
  });

  /// Delivers a native-to-Dart call to the controller.
  Future<void> nativeCalls(String method, Object? arguments) async {
    final completer = Completer<void>();
    await messenger.handlePlatformMessage(
      wallpaperChannelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) => completer.complete(),
    );
    await completer.future;
  }

  test('attach sends ready with the protocol version and applies the '
      'snapshot', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return {
        'protocol': protocolVersion,
        'engineId': 7,
        'preview': false,
        'visible': true,
        'offset': [0.5, 0.5],
        'offsetStep': [0.25, 0.0],
        'zoom': 0.0,
        'target': 1,
      };
    });

    await controller.attach();

    expect(received?.method, 'ready');
    expect(received?.arguments, {'protocol': protocolVersion});
    expect(controller.engineId, 7);
    expect(controller.isAttached, isTrue);
    expect(
      controller.data.value,
      const WallpaperData(
        visible: true,
        target: WallpaperTarget.home,
        pageOffset: Offset(0.5, 0.5),
        pageStep: Offset(0.25, 0),
      ),
    );
  });

  test('attach is idempotent', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return {'protocol': protocolVersion, 'engineId': 1};
    });

    await Future.wait([controller.attach(), controller.attach()]);
    await controller.attach();

    expect(calls, 1);
  });

  test('without a wallpaper engine the scene behaves as visible', () async {
    await controller.attach();

    expect(controller.isAttached, isFalse);
    expect(controller.data.value.visible, isTrue);
  });

  test('updates change only the fields they carry', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return {'protocol': protocolVersion, 'engineId': 1, 'visible': true};
    });
    await controller.attach();

    await nativeCalls('update', {'zoom': 0.33});

    expect(
      controller.data.value,
      const WallpaperData(visible: true, zoom: 0.33),
    );

    await nativeCalls('update', {'visible': false});

    expect(controller.data.value.visible, isFalse);
    expect(controller.data.value.zoom, 0.33);
  });

  test('commands arrive on the stream in logical pixels', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return {'protocol': protocolVersion, 'engineId': 1};
    });
    await controller.attach();
    final dpr =
        PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    final next = controller.commands.first;

    await nativeCalls('command', {
      'action': 'android.wallpaper.tap',
      'x': 300,
      'y': 900,
      'z': 0,
      'extras': <Object?, Object?>{},
    });

    final command = await next;
    expect(command.action, WallpaperCommand.tap);
    expect(command.position, Offset(300 / dpr, 900 / dpr));
  });

  group('config, messages, tilt and colors', () {
    late List<MethodCall> sent;

    setUp(() {
      sent = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return switch (call.method) {
          'ready' => {
            'protocol': protocolVersion,
            'engineId': 1,
            'visible': true,
            'config': '{"scene":"aurora"}',
          },
          'send' => 1,
          'tilt' => true,
          _ => null,
        };
      });
    });

    test('the snapshot carries the config and updates replace it', () async {
      await controller.attach();
      expect(controller.data.value.config, {'scene': 'aurora'});

      await nativeCalls('update', {'config': '{"scene":"ocean","speed":2}'});
      expect(controller.data.value.config, {'scene': 'ocean', 'speed': 2});

      await nativeCalls('update', {'config': null});
      expect(controller.data.value.config, isEmpty);
    });

    test('app messages arrive on the stream', () async {
      await controller.attach();
      final next = controller.messages.first;

      await nativeCalls('message', {
        'name': 'ping',
        'data': [1, 2],
      });

      expect(await next, const WallpaperMessage('ping', [1, 2]));
    });

    test('sendToApp and reportColors call native', () async {
      await controller.attach();

      expect(await controller.sendToApp('pong', {'ok': true}), 1);
      await controller.reportColors(primary: 0xFF336699, hints: 1);

      expect(sent[1].method, 'send');
      expect(sent[1].arguments, {
        'name': 'pong',
        'data': {'ok': true},
      });
      expect(sent[2].method, 'colors');
      expect(sent[2].arguments, {
        'primary': 0xFF336699,
        'secondary': null,
        'tertiary': null,
        'hints': 1,
      });
    });

    test('tilt demand from before attach is sent once attached', () async {
      controller.tilt.addListener(() {});
      expect(sent, isEmpty);

      await controller.attach();

      final tilt = sent.singleWhere((call) => call.method == 'tilt');
      expect(tilt.arguments, {'enabled': true, 'samplingPeriodUs': 20000});
    });

    test('tilt samples reach the tilt controller', () async {
      await controller.attach();

      await nativeCalls('update', {
        'tilt': [0.1, 0.9],
      });

      // The first sample becomes the neutral position, so the value stays 0.
      expect(controller.tilt.value, Offset.zero);
    });

    test('colors reported before attach are sent once attached', () async {
      final early = controller.reportColors(primary: 0xFF112233);
      await controller.attach();
      await early;

      final colors = sent.where((call) => call.method == 'colors').toList();
      expect(colors, hasLength(1));
      expect((colors.single.arguments as Map)['primary'], 0xFF112233);
    });

    test('without an engine, sending is a no-op', () async {
      messenger.setMockMethodCallHandler(channel, null);
      await controller.attach();

      expect(await controller.sendToApp('pong', null), 0);
      await controller.reportColors(primary: 0xFF000000);
    });
  });
}
