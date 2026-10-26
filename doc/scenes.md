# Writing scenes

A scene is the widget you pass to `runWallpaper`. This guide covers reading the wallpaper's state,
keeping a scene cheap to run, and fitting in with the rest of the system.

## What a scene runs in

`runWallpaper` puts your widget under:

- a `WallpaperScope`, which provides the wallpaper's state,
- a left-to-right `Directionality`,
- a background fill, black unless you pass `background:`.

There's no `MaterialApp` or `WidgetsApp`. If the scene needs Material widgets, themes or
localizations, add a `MaterialApp` inside it. Plain widgets such as `Text` work without one; wrap
them in a `DefaultTextStyle` to set the font and color.

`MediaQuery` works as in an app: the screen size, the status bar and navigation bar padding,
display cutouts and rounded corners, dark mode, text scaling and the locale. `SafeArea` keeps
content clear of the status bar and the navigation bar.

## Reading the wallpaper's state

Read state the way you read `MediaQuery`. Each of these methods rebuilds the caller only when its
own value changes:

| Method | Returns |
|---|---|
| `Wallpaper.visibleOf(context)` | Whether the wallpaper is on screen. |
| `Wallpaper.pageOffsetOf(context)` | The launcher's scroll position, 0 to 1 on each axis. |
| `Wallpaper.pageStepOf(context)` | The page offset distance between two pages. |
| `Wallpaper.zoomOf(context)` | How far the launcher zoomed the wallpaper out, 0 to 1. |
| `Wallpaper.isPreviewOf(context)` | Whether this is the wallpaper picker's preview. |
| `Wallpaper.targetOf(context)` | Home screen, lock screen or both. |
| `Wallpaper.configOf(context)` | The settings the app saved for the wallpaper. |

`Wallpaper.of(context)` returns all of them as one `WallpaperData`, and rebuilds the caller when
any of them changes. Page offsets change every frame during a swipe, so a widget that needs only
visibility should call `visibleOf`.

With five home screen pages, `pageOffset.dx` is 0 on the first page, 0.25 on the second and 1 on
the last; `pageStep.dx` is 0.25, and `WallpaperData.pageCount` is 5. Both are 0 when the launcher
doesn't report them.

## Parallax

Move distant layers less than near ones as the user swipes:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

class Hills extends StatelessWidget {
  const Hills({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color(0xFF9BC4E2)), // The sky doesn't move.
        ParallaxLayer(depth: 0.1, child: Hill(Color(0xFF7A9CB8), height: 0.45)),
        ParallaxLayer(depth: 0.25, child: Hill(Color(0xFF4F7A5A), height: 0.3)),
        ParallaxLayer(depth: 0.5, child: Hill(Color(0xFF2E4A33), height: 0.18)),
      ],
    );
  }
}

/// Moves [child] [depth] screen widths to the left between the first home
/// screen page and the last. [child] is that much wider than the screen.
class ParallaxLayer extends StatelessWidget {
  const ParallaxLayer({super.key, required this.depth, required this.child});

  final double depth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final page = Wallpaper.pageOffsetOf(context).dx;
    final width = MediaQuery.sizeOf(context).width;
    return OverflowBox(
      alignment: Alignment.centerLeft,
      minWidth: width * (1 + depth),
      maxWidth: width * (1 + depth),
      child: Transform.translate(
        offset: Offset(-page * depth * width, 0),
        // Moving a repaint boundary doesn't repaint what's inside it.
        child: RepaintBoundary(child: child),
      ),
    );
  }
}

class Hill extends StatelessWidget {
  const Hill(this.color, {super.key, required this.height});

  final Color color;

  /// The hill's height as a fraction of the screen's.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(
              top: Radius.elliptical(600, 160),
            ),
          ),
        ),
      ),
    );
  }
}
```

The layers rebuild on every frame of a swipe, but they're cheap: each builds a translation, and the
`RepaintBoundary` lets Flutter move the already painted layer instead of painting it again.

Parallax can follow device tilt too; see [Motion and touch](motion-and-touch.md).

## Launcher zoom

Launchers zoom the wallpaper out slightly when they open the app drawer or the recents screen
(Android 11 and later). Android's own image wallpaper shows this by scaling, and a scene can do
the same:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Slightly enlarged at rest, back to full size as the launcher zooms out.
class LauncherZoom extends StatelessWidget {
  const LauncherZoom({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zoom = Wallpaper.zoomOf(context);
    return Transform.scale(scale: 1.04 - 0.04 * zoom, child: child);
  }
}
```

## Visibility and battery

A live wallpaper is on screen whenever the home screen is, so a scene's cost adds up over a day.

While the wallpaper is hidden, by an app or with the screen off, the engine draws no frames.
Animations, tickers and `AnimationController`s stop on their own. Dart timers, stream
subscriptions and network requests keep running, so stop them while the wallpaper is hidden:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Shows the time, updated each minute while the wallpaper is visible.
class Clock extends StatefulWidget {
  const Clock({super.key});

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Wallpaper.visibleOf(context)) {
      if (_timer == null) {
        _now = DateTime.now(); // Catch up after being hidden.
        _scheduleTick();
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Wakes up once, at the start of the next minute.
  void _scheduleTick() {
    final now = DateTime.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(next.difference(now), () {
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final minute = _now.minute.toString().padLeft(2, '0');
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.6),
        child: Text(
          '${_now.hour}:$minute',
          style: const TextStyle(fontSize: 72, color: Color(0xFFFFFFFF)),
        ),
      ),
    );
  }
}
```

While visible, prefer animations that end:

- **Scenes that change only with input draw nothing in between.** A scene that moves only with
  swipes, tilt or taps costs almost nothing while the user isn't touching the phone.
- **Run animations once, not forever.** Start an `AnimationController` with `forward()` when
  something happens, and let it stop. An animation that repeats forever draws 60 frames or more a
  second, the whole time the home screen is up. The README's
  [Battery](https://github.com/sharpsan/wallflower#battery) section has measurements.
- **Paint layers once.** Wrap layers that only move in a `RepaintBoundary`, as in the parallax
  example.

## The picker preview and the lock screen

While the user looks at the wallpaper in the picker, a second copy of it runs for the preview,
alongside the applied wallpaper if there is one. `Wallpaper.isPreviewOf(context)` is true in the
preview. Use it to skip an intro animation, for example, or to show what the wallpaper does.

On Android 14 and later, users can apply a live wallpaper to the home screen, the lock screen or
both, and `Wallpaper.targetOf(context)` says which:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Darkens the scene when it's applied only to the lock screen, where it
/// sits behind the clock and notifications.
class LockScreenDim extends StatelessWidget {
  const LockScreenDim({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Wallpaper.targetOf(context) != WallpaperTarget.lock) return child;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Color(0x66000000), BlendMode.srcATop),
      child: child,
    );
  }
}
```

A wallpaper applied to both screens runs as one copy with the target `homeAndLock`, so it can't
tell which screen is showing. Before Android 14, the target is `unknown`.

## Colors for Material You

Android picks the system theme's colors from the wallpaper when the user's theme follows it, and
chooses light or dark status bar icons to suit it. Tell it the scene's colors with
`Wallpaper.reportColors`, when the scene starts and whenever its look changes:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// A sky that the app switches between day and night through the config.
class DayNightSky extends StatefulWidget {
  const DayNightSky({super.key});

  @override
  State<DayNightSky> createState() => _DayNightSkyState();
}

class _DayNightSkyState extends State<DayNightSky> {
  Color? _sky;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final night = Wallpaper.configOf(context)['night'] == true;
    final sky = night ? const Color(0xFF101830) : const Color(0xFF9BC4E2);
    if (sky != _sky) {
      _sky = sky;
      // Only on changes: each report makes the system recompute its theme.
      unawaited(
        Wallpaper.reportColors(
          sky,
          supportsDarkText: !night, // Dark status bar icons over a light sky.
          supportsDarkTheme: night,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(color: _sky!);
}
```

Colors need Android 8.1 (API 27) or later, and `supportsDarkText` and `supportsDarkTheme` need
Android 12.

## Outside the widget tree

Game loops and other code outside the widget tree can read the same state:

- `Wallpaper.data` is a `ValueListenable<WallpaperData>`.
- `Wallpaper.commands` and `Wallpaper.messages` are broadcast streams.
- `WallpaperTilt.listenable` is a `ValueListenable<Offset>`.

Any widget can be the scene, including Flame's `GameWidget`. Pause the game while the wallpaper is
hidden: call `pauseEngine()` when `Wallpaper.data.value.visible` turns false, and
`resumeEngine()` when it turns true.
