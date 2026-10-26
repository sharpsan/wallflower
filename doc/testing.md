# Testing and previews

`WallpaperScope` provides wallpaper state to the widgets below it. `runWallpaper` adds one with the
real state; add your own to drive a scene with made-up state in widget tests, or to show a scene
inside your app.

A `WallpaperScope` takes a `ValueListenable<WallpaperData>` as `data`, and optionally a
`ValueListenable<Offset>` as `tilt`, the value `WallpaperTilt.of` returns. Change their values and
the scene sees the change, as it would see a swipe, a tilt or the app saving a new config.

## Widget tests

A test needs what `runWallpaper` would otherwise provide: a `WallpaperScope` and a
`Directionality`. This file tests a small scene, and checks that its animation ends:

```dart
// test/scene_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/wallflower.dart';

/// Shows which home screen page is in front, and dims when the app's config
/// says so.
class PageScene extends StatelessWidget {
  const PageScene({super.key});

  @override
  Widget build(BuildContext context) {
    final data = Wallpaper.of(context);
    final step = data.pageStep.dx;
    final page = step > 0 ? (data.pageOffset.dx / step).round() + 1 : 1;
    return AnimatedOpacity(
      opacity: data.config['dim'] == true ? 0.5 : 1,
      duration: const Duration(milliseconds: 300),
      child: Text('Page $page of ${data.pageCount}'),
    );
  }
}

/// Puts [scene] under a WallpaperScope, as runWallpaper does.
Widget wallpaper(ValueNotifier<WallpaperData> data, Widget scene) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: WallpaperScope(data: data, child: scene),
  );
}

void main() {
  testWidgets('follows home screen swipes', (tester) async {
    // Five pages (a step of 0.25), on the first.
    final data = ValueNotifier(
      const WallpaperData(visible: true, pageStep: Offset(0.25, 0)),
    );
    await tester.pumpWidget(wallpaper(data, const PageScene()));
    expect(find.text('Page 1 of 5'), findsOneWidget);

    data.value = data.value.copyWith(pageOffset: const Offset(0.5, 0));
    await tester.pump();
    expect(find.text('Page 3 of 5'), findsOneWidget);
  });

  testWidgets('stops drawing after a config change', (tester) async {
    final data = ValueNotifier(const WallpaperData(visible: true));
    await tester.pumpWidget(wallpaper(data, const PageScene()));

    data.value = data.value.copyWith(config: {'dim': true});
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue); // Fading.

    // pumpAndSettle fails if the scene never stops scheduling frames.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
```

`pumpAndSettle` is a useful check for every scene: an animation that never ends draws frames the
whole time the home screen is up. Run it after each kind of input the scene reacts to.

### Tilt

Pass a `tilt` notifier and change its value:

```dart
// test/tilt_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/wallflower.dart';

class TiltLabel extends StatelessWidget {
  const TiltLabel({super.key});

  @override
  Widget build(BuildContext context) =>
      Text(WallpaperTilt.of(context).dx.toStringAsFixed(1));
}

void main() {
  testWidgets('shows the tilt', (tester) async {
    final tilt = ValueNotifier(Offset.zero);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WallpaperScope(
          data: ValueNotifier(const WallpaperData(visible: true)),
          tilt: tilt,
          child: const TiltLabel(),
        ),
      ),
    );

    tilt.value = const Offset(0.5, 0);
    await tester.pump();
    expect(find.text('0.5'), findsOneWidget);
  });
}
```

### Launcher commands

Nothing sends launcher commands in a test. Let the scene take its commands as a parameter that
defaults to `Wallpaper.commands`, and pass your own stream in tests:

```dart
// test/tap_counter_test.dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/wallflower.dart';

/// Counts taps on empty parts of the home screen.
class TapCounter extends StatefulWidget {
  const TapCounter({super.key, this.commands});

  /// Where commands come from. Defaults to [Wallpaper.commands].
  final Stream<WallpaperCommand>? commands;

  @override
  State<TapCounter> createState() => _TapCounterState();
}

class _TapCounterState extends State<TapCounter> {
  late final StreamSubscription<WallpaperCommand> _commands;
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    _commands = (widget.commands ?? Wallpaper.commands).listen((command) {
      if (command.isTap) setState(() => _taps++);
    });
  }

  @override
  void dispose() {
    _commands.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('Taps: $_taps');
}

void main() {
  testWidgets('counts taps', (tester) async {
    // Synchronous, so each command arrives before the next pump.
    final commands = StreamController<WallpaperCommand>.broadcast(sync: true);
    addTearDown(commands.close);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WallpaperScope(
          data: ValueNotifier(const WallpaperData(visible: true)),
          child: TapCounter(commands: commands.stream),
        ),
      ),
    );

    commands.add(const WallpaperCommand(action: WallpaperCommand.tap));
    await tester.pump();
    expect(find.text('Taps: 1'), findsOneWidget);
  });
}
```

Pointer events work in tests as usual, with `tester.tapAt` and `tester.drag`.

## Previews in the app

The same scope shows a scene inside the app, for example next to its settings. This preview draws
the scene in a phone-shaped box, on a chosen page and with the config being edited:

```dart
// lib/scene_preview.dart
import 'package:flutter/material.dart';
import 'package:wallflower/wallflower.dart';

/// Shows [scene] as it would look on the home screen with [config], on page
/// [page] (0 to 4) of five.
class ScenePreview extends StatefulWidget {
  const ScenePreview({
    super.key,
    required this.scene,
    this.config = const {},
    this.page = 0,
  });

  final Widget scene;
  final Map<String, Object?> config;
  final int page;

  @override
  State<ScenePreview> createState() => _ScenePreviewState();
}

class _ScenePreviewState extends State<ScenePreview> {
  late final ValueNotifier<WallpaperData> _data;

  @override
  void initState() {
    super.initState();
    _data = ValueNotifier(_dataFor(widget));
  }

  @override
  void didUpdateWidget(ScenePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _data.value = _dataFor(widget);
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  static WallpaperData _dataFor(ScenePreview widget) => WallpaperData(
    visible: true,
    isPreview: true,
    pageStep: const Offset(0.25, 0),
    pageOffset: Offset(widget.page * 0.25, 0),
    config: widget.config,
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    const width = 200.0;
    final height = width * media.size.longestSide / media.size.shortestSide;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        width: width,
        height: height,
        // Scenes size themselves from MediaQuery, so give them the box's
        // size instead of the screen's.
        child: MediaQuery(
          data: media.copyWith(
            size: Size(width, height),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
          ),
          child: WallpaperScope(data: _data, child: widget.scene),
        ),
      ),
    );
  }
}
```

Hot reload works on previews, since they're ordinary widgets in the app. To try other launcher
behavior, drive `pageOffset` from a drag on the preview, the way the example app does.

## On a device

To see the scene full screen without setting it as the wallpaper, run an entrypoint that calls
`runWallpaper` directly, as described in [Getting started](getting-started.md#6-work-on-the-scene).

To open the wallpaper picker on your wallpaper without going through the app, replace
`com.example.drifting_sky` with your application ID:

```sh
adb shell am start -a android.service.wallpaper.CHANGE_LIVE_WALLPAPER \
  --ecn android.service.wallpaper.extra.LIVE_WALLPAPER_COMPONENT \
  com.example.drifting_sky/app.sharpsan.wallflower.FlutterWallpaperService
```

The wallpaper logs under the tags `flutter` and `Wallflower`: `adb logcat -s flutter Wallflower`.
Judge smoothness and startup time in profile or release builds, not debug builds.
