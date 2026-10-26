import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

import '../config.dart';
import 'common.dart';

/// A minimal clock on a soft gradient.
///
/// It redraws once a minute, and only while the wallpaper is visible. The
/// time stays clear of the status bar and display cutout with [SafeArea],
/// which works because the wallpaper's insets reach `MediaQuery`.
class ClockScene extends StatefulWidget {
  const ClockScene({super.key, required this.config});

  final DemoConfig config;

  /// The gradient's top and bottom colors: the palette's sky, with
  /// saturation scaled by the intensity. The wallpaper reports these to
  /// Android for Material You.
  static (Color, Color) colors(DemoConfig config) {
    Color tone(Color color) {
      final hsl = HSLColor.fromColor(color);
      return hsl
          .withSaturation(hsl.saturation * (0.2 + 0.8 * config.intensity))
          .toColor();
    }

    return (tone(config.palette.skyTop), tone(config.palette.skyBottom));
  }

  @override
  State<ClockScene> createState() => _ClockSceneState();
}

class _ClockSceneState extends State<ClockScene> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden wallpapers draw nothing, so there's no point waking up every
    // minute while hidden. Catch up when shown again.
    if (Wallpaper.visibleOf(context)) {
      if (_timer == null) {
        _now = DateTime.now();
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

  void _scheduleTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), () {
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final (top, bottom) = ClockScene.colors(config);
    final ink = config.palette.isDark
        ? const Color(0xFFFFFFFF)
        : config.palette.deep;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);

    return LauncherZoom(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Glow(config),
            SafeArea(
              child: Align(
                alignment: const Alignment(0, -0.55),
                child: LayoutBuilder(
                  builder: (context, constraints) => DefaultTextStyle(
                    style: TextStyle(
                      color: ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(_now, use24Hour: use24Hour),
                          style: TextStyle(
                            fontSize: constraints.maxWidth * 0.24,
                            fontWeight: FontWeight.w200,
                            height: 1,
                            letterSpacing: -2,
                          ),
                        ),
                        SizedBox(height: constraints.maxWidth * 0.02),
                        Text(
                          _formatDate(_now).toUpperCase(),
                          style: TextStyle(
                            fontSize: constraints.maxWidth * 0.035,
                            letterSpacing: constraints.maxWidth * 0.008,
                            color: ink.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time, {required bool use24Hour}) {
    final minutes = time.minute.toString().padLeft(2, '0');
    if (use24Hour) return '${time.hour.toString().padLeft(2, '0')}:$minutes';
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$hour:$minutes';
  }

  static String _formatDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} '
        '${date.day}';
  }
}

/// A soft glow that drifts a little as you change pages. In its own widget so
/// page changes don't rebuild the text.
class _Glow extends StatelessWidget {
  const _Glow(this.config);

  final DemoConfig config;

  @override
  Widget build(BuildContext context) {
    final page = Wallpaper.pageOffsetOf(context).dx;
    final light = config.palette.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.6 - 1.2 * page, 0.35),
          radius: 0.9,
          colors: [
            light.withValues(alpha: 0.1 + 0.25 * config.intensity),
            light.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
