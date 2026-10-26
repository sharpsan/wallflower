# Motion and touch

A wallpaper can respond to the phone's movement and to touches on the home screen. This guide
covers device tilt, pointer events and the commands launchers send.

## Device tilt

`WallpaperTilt.of(context)` returns the device's tilt as an `Offset`, each axis from -1 to 1. `dx`
grows as the right edge of the screen dips, and `dy` grows as the top edge tips away from the
viewer. Shift layers against it for a sense of depth:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Moves [child] against the device tilt, up to [travel] logical pixels.
class TiltShift extends StatelessWidget {
  const TiltShift({super.key, required this.travel, required this.child});

  final double travel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tilt = WallpaperTilt.of(context);
    return Transform.translate(
      offset: Offset(-tilt.dx * travel, -tilt.dy * travel),
      child: RepaintBoundary(child: child),
    );
  }
}
```

Make shifted layers a little larger than the screen, for example with `Transform.scale`, so their
edges never come into view.

Tilt is measured from the way the phone is being held, not from level. When the phone settles at
a new angle, the value drifts back to zero over a couple of seconds, so a scene re-centers by
itself whether the user is standing, sitting or lying down.

### When the sensor runs

The motion sensor runs only while the wallpaper is visible and at least one mounted widget has
called `WallpaperTilt.of`. A widget keeps the sensor on until it unmounts, even if a later build
stops reading tilt. So read tilt in a small widget of its own, and leave that widget out when the
scene doesn't need tilt. (Outside the widget tree, a listener on `WallpaperTilt.listenable` keeps
the sensor on instead.)

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Calls [builder] with the device tilt when [enabled], or with zero.
///
/// Tilt is read in a separate widget that's left out when [enabled] is
/// false, which turns the sensor off.
class TiltBuilder extends StatelessWidget {
  const TiltBuilder({super.key, required this.enabled, required this.builder});

  final bool enabled;
  final Widget Function(BuildContext context, Offset tilt) builder;

  @override
  Widget build(BuildContext context) =>
      enabled ? _TiltReader(builder) : builder(context, Offset.zero);
}

class _TiltReader extends StatelessWidget {
  const _TiltReader(this.builder);

  final Widget Function(BuildContext context, Offset tilt) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, WallpaperTilt.of(context));
}
```

Every sample rebuilds the widgets that read tilt, so read it as low in the tree as you can, in the
widgets that move.

While the phone lies still, the sensor drops to 10 samples a second until it moves again. On a
Pixel 10 Pro, a static scene that read tilt used under 1% of a CPU core while the phone rested.
Devices and emulators without a motion sensor always report zero.

### Tilt settings

`WallpaperTilt.settings` controls how the sensor samples and how its values are filtered. Set it
in the entrypoint, after `runWallpaper`:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

@pragma('vm:entry-point')
void wallpaperMain() {
  runWallpaper(const TiltScene());
  WallpaperTilt.settings = const WallpaperTiltSettings(
    range: 0.25, // Full deflection at about 15 degrees.
    recenter: Duration(seconds: 4), // Re-center more slowly.
  );
}

class TiltScene extends StatelessWidget {
  const TiltScene({super.key});

  @override
  Widget build(BuildContext context) {
    return const TiltShift(
      travel: 24,
      child: ColoredBox(color: Color(0xFF2E4A33)),
    );
  }
}
```

| Setting | Default | Meaning |
|---|---|---|
| `samplingPeriod` | 20 ms | How often the sensor reports while the phone moves. |
| `smoothing` | 80 ms | The smoothing filter's time constant. Longer is calmer but lags more. `Duration.zero` turns it off. |
| `recenter` | 2 s | How quickly the neutral position follows the way the phone is held. `null` keeps the position from when the wallpaper became visible. |
| `range` | 0.35 | The tilt that maps to 1, as the sine of the angle: 0.35 is about 20 degrees. Larger tilts are clamped. |

## Touch

Touches on the home screen reach the wallpaper as ordinary pointer events, so `Listener` and
`GestureDetector` work. The wallpaper sees every touch on the home screen, including swipes
between pages and touches on icons and widgets, which the launcher handles as well.

To react only to taps on empty parts of the home screen, use the launcher's commands.

## Launcher commands

Launchers and the system send commands on `Wallpaper.commands`, a broadcast stream:

| Command | Sent when |
|---|---|
| `WallpaperCommand.tap` | The user taps an empty part of the home screen. Not for taps on icons, and not for swipes. |
| `WallpaperCommand.secondaryTap` | A secondary tap, such as with a second finger. |
| `WallpaperCommand.drop` | The user drops an item, such as an icon, on the home screen. |
| `WallpaperCommand.wakingUp` | The screen turns on. Pixel devices send it; others may not. |
| `WallpaperCommand.goingToSleep` | The screen turns off. Pixel devices send it; others may not. |

`WallpaperCommand.position` is where it happened, in logical pixels. Launchers compute it their
own way, and on Pixel Launcher it can be several percent away from the actual touch. For an exact
position, pair a tap command with the pointer event from the same tap:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Draws a ring where the user taps an empty part of the home screen.
class Ripples extends StatefulWidget {
  const Ripples({super.key});

  @override
  State<Ripples> createState() => _RipplesState();
}

class _RipplesState extends State<Ripples> with SingleTickerProviderStateMixin {
  late final AnimationController _ring;
  late final StreamSubscription<WallpaperCommand> _commands;
  Offset _center = Offset.zero;

  // The last pointer down: the exact position of the latest touch.
  Offset? _pointer;
  DateTime _pointerTime = DateTime(0);

  @override
  void initState() {
    super.initState();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _commands = Wallpaper.commands.listen(_onCommand);
  }

  @override
  void dispose() {
    _commands.cancel();
    _ring.dispose();
    super.dispose();
  }

  void _onCommand(WallpaperCommand command) {
    if (!command.isTap) return;
    final pointer = _pointer;
    final recent =
        DateTime.now().difference(_pointerTime) <
        const Duration(milliseconds: 600);
    setState(() {
      _center = recent && pointer != null ? pointer : command.position;
    });
    _ring.forward(from: 0); // Draws for 800 ms, then frames stop.
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _pointer = event.localPosition;
        _pointerTime = DateTime.now();
      },
      child: CustomPaint(
        painter: _RingPainter(_ring, _center),
        size: Size.infinite,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.center) : super(repaint: progress);

  final Animation<double> progress;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t == 0 || t == 1) return;
    canvas.drawCircle(
      center,
      240 * t,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Color.fromRGBO(255, 255, 255, 1 - t),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.center != center;
}
```

The animation runs once per tap and then stops, so the scene draws nothing between taps.

Commands arrive only in a running wallpaper. In widget tests and in-app previews, nothing sends
them; [Testing and previews](testing.md) shows how to feed taps to a scene there.
