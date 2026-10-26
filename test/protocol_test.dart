import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/src/protocol.dart';
import 'package:wallflower/wallflower.dart';

void main() {
  group('applyUpdate', () {
    test('applies a full snapshot', () {
      final data = applyUpdate(const WallpaperData(), {
        'protocol': 1,
        'engineId': 3,
        'preview': true,
        'visible': true,
        'offset': [0.25, 0.5],
        'offsetStep': [0.25, 1.0],
        'zoom': 0.33,
        'target': 3,
      });

      expect(
        data,
        const WallpaperData(
          visible: true,
          isPreview: true,
          target: WallpaperTarget.homeAndLock,
          pageOffset: Offset(0.25, 0.5),
          pageStep: Offset(0.25, 1),
          zoom: 0.33,
        ),
      );
      expect(data.pageCount, 5);
    });

    test('keeps fields missing from a partial update', () {
      const before = WallpaperData(
        visible: true,
        target: WallpaperTarget.home,
        zoom: 0.2,
      );

      final after = applyUpdate(before, {
        'offset': [1, 0],
      });

      expect(after, before.copyWith(pageOffset: const Offset(1, 0)));
    });

    test('a null target decodes to unknown', () {
      final data = applyUpdate(
        const WallpaperData(target: WallpaperTarget.home),
        {'target': null},
      );

      expect(data.target, WallpaperTarget.unknown);
    });

    test('ignores malformed values and unknown keys', () {
      const before = WallpaperData(visible: true, zoom: 0.5);

      final after = applyUpdate(before, {
        'visible': 'yes',
        'offset': [0.5],
        'zoom': null,
        'somethingNew': 42,
      });

      expect(after, before);
    });
  });

  group('config', () {
    test('decodes JSON objects and rejects everything else', () {
      expect(decodeConfig('{"a":1,"b":[true,null]}'), {
        'a': 1,
        'b': [true, null],
      });
      expect(decodeConfig(null), isEmpty);
      expect(decodeConfig('[1,2]'), isEmpty);
      expect(decodeConfig('not json'), isEmpty);
    });

    test('config equality is deep', () {
      expect(
        const WallpaperData(
          config: {
            'a': [1, 2],
          },
        ),
        WallpaperData(
          config: {
            'a': [1, 2],
          },
        ),
      );
      expect(
        const WallpaperData(
          config: {
            'a': [1, 2],
          },
        ),
        isNot(
          const WallpaperData(
            config: {
              'a': [1, 3],
            },
          ),
        ),
      );
    });
  });

  test('decodeTilt reads the up vector and rotation', () {
    expect(
      decodeTilt({
        'tilt': [0.25, -0.5, 1],
      }),
      (up: const Offset(0.25, -0.5), quarterTurns: 1),
    );
    expect(
      decodeTilt({
        'tilt': [0.25, -0.5],
      }),
      (up: const Offset(0.25, -0.5), quarterTurns: 0),
    );
    expect(decodeTilt({'zoom': 0.1}), isNull);
    expect(
      decodeTilt({
        'tilt': ['a', 0.5, 1],
      }),
      isNull,
    );
  });

  group('WallpaperTarget.fromFlags', () {
    test('decodes WallpaperManager flags', () {
      expect(WallpaperTarget.fromFlags(null), WallpaperTarget.unknown);
      expect(WallpaperTarget.fromFlags(0), WallpaperTarget.unknown);
      expect(WallpaperTarget.fromFlags(1), WallpaperTarget.home);
      expect(WallpaperTarget.fromFlags(2), WallpaperTarget.lock);
      expect(WallpaperTarget.fromFlags(3), WallpaperTarget.homeAndLock);
    });

    test('includesHome and includesLock', () {
      expect(WallpaperTarget.homeAndLock.includesHome, isTrue);
      expect(WallpaperTarget.homeAndLock.includesLock, isTrue);
      expect(WallpaperTarget.lock.includesHome, isFalse);
      expect(WallpaperTarget.unknown.includesLock, isFalse);
    });
  });

  group('decodeCommand', () {
    test('converts physical pixels to logical pixels', () {
      final command = decodeCommand({
        'action': 'android.wallpaper.tap',
        'x': 579,
        'y': 2019,
        'z': 0,
        'extras': <Object?, Object?>{},
      }, devicePixelRatio: 2.625);

      expect(command.action, WallpaperCommand.tap);
      expect(command.isTap, isTrue);
      expect(command.position.dx, closeTo(220.571, 0.001));
      expect(command.position.dy, closeTo(769.143, 0.001));
    });

    test('keeps string-keyed extras', () {
      final command = decodeCommand({
        'action': 'custom',
        'x': 0,
        'y': 0,
        'z': 2,
        'extras': {'a': 1, 'b': 'two', 3: 'dropped'},
      }, devicePixelRatio: 1);

      expect(command.isTap, isFalse);
      expect(command.z, 2);
      expect(command.extras, {'a': 1, 'b': 'two'});
    });
  });

  test('pageCount is 1 without a step', () {
    expect(const WallpaperData().pageCount, 1);
    expect(const WallpaperData(pageStep: Offset(0.5, 0)).pageCount, 3);
  });
}
