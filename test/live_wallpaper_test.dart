import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/wallflower.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('wallflower/app');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isActive' => true,
        'openPicker' => true,
        'getConfig' => '{"scene":"aurora","speed":2}',
        'send' => 2,
        _ => null,
      };
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('isActive and openPicker pass the service', () async {
    expect(await LiveWallpaper.isActive(), isTrue);
    expect(await LiveWallpaper.openPicker(service: 'Ocean'), isTrue);

    expect(calls[0].arguments, {'service': null});
    expect(calls[1].arguments, {'service': 'Ocean'});
  });

  test('setConfig sends JSON and an empty map clears', () async {
    await LiveWallpaper.setConfig({
      'scene': 'aurora',
      'layers': [1, 2],
    });
    await LiveWallpaper.setConfig({});

    final first = calls[0].arguments as Map;
    expect(jsonDecode(first['config'] as String), {
      'scene': 'aurora',
      'layers': [1, 2],
    });
    expect((calls[1].arguments as Map)['config'], isNull);
  });

  test('setConfig rejects values JSON cannot encode', () {
    expect(
      () => LiveWallpaper.setConfig({'when': DateTime(2026)}),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
  });

  test('getConfig decodes the stored JSON', () async {
    expect(await LiveWallpaper.getConfig(), {'scene': 'aurora', 'speed': 2});
  });

  test('send returns the number of engines reached', () async {
    final reached = await LiveWallpaper.send('ping', data: {'n': 1});

    expect(reached, 2);
    expect(calls.single.arguments, {
      'service': null,
      'name': 'ping',
      'data': {'n': 1},
    });
  });

  test('messages from wallpapers arrive on the stream', () async {
    final next = LiveWallpaper.messages.first;
    final completer = Completer<void>();

    await messenger.handlePlatformMessage(
      'wallflower/app',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('message', {'name': 'pong', 'data': 42}),
      ),
      (_) => completer.complete(),
    );
    await completer.future;

    expect(await next, const WallpaperMessage('pong', 42));
  });
}
