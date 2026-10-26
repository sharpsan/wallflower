import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Scales [child] the way Android's own image wallpaper does: a little
/// enlarged at rest, back to full size as the launcher zooms out to show the
/// app drawer or the recents screen.
class LauncherZoom extends StatelessWidget {
  const LauncherZoom({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final zoom = Wallpaper.zoomOf(context);
    return Transform.scale(scale: 1.04 - 0.04 * zoom, child: child);
  }
}

/// Builds with the device tilt when [enabled], otherwise with zero.
///
/// The tilt sensor runs while any widget that called `WallpaperTilt.of` is
/// mounted, and a widget stays registered until it unmounts, even if it stops
/// calling it. So the read happens in a separate widget that is left out
/// entirely when tilt is off.
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
