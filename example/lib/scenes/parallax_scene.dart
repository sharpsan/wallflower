import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

import '../config.dart';
import 'common.dart';

/// Layered mountain ridges. Each layer moves by its depth, far ridges a
/// little and near ones a lot, as you swipe between home screen pages and as
/// the phone tilts.
///
/// Nothing moves by itself, so between swipes, and while the phone is still,
/// the scene draws no frames at all.
class ParallaxScene extends StatelessWidget {
  const ParallaxScene({super.key, required this.config});

  final DemoConfig config;

  @override
  Widget build(BuildContext context) {
    final palette = config.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // How far a layer at depth 1 travels from the first page to the last,
        // and with a full tilt.
        final travel = _Travel(
          page: size.width * (0.15 + 0.45 * config.intensity),
          tilt: size.width * (0.03 + 0.07 * config.intensity),
        );
        Widget layer(
          double depth,
          CustomPainter Function(Offset overscan) painter,
        ) => _Layer(
          depth: depth,
          travel: travel,
          tilt: config.tilt,
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: painter(travel.overscan(depth)),
            ),
          ),
        );

        return LauncherZoom(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.skyTop, palette.skyBottom],
                    stops: const [0, 0.62],
                  ),
                ),
              ),
              if (palette == DemoPalette.night)
                layer(
                  0.03,
                  (overscan) => _StarsPainter(palette.light, overscan),
                ),
              layer(0.08, (overscan) => _SunPainter(palette, overscan)),
              for (final (i, ridge) in _ridges.indexed)
                layer(
                  ridge.depth,
                  (overscan) => _RidgePainter(
                    ridge,
                    overscan,
                    color: Color.lerp(
                      palette.haze,
                      palette.deep,
                      math.pow(i / (_ridges.length - 1), 0.8).toDouble(),
                    )!,
                    fog: palette.haze,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// How far layers move, in logical pixels, at depth 1.
class _Travel {
  const _Travel({required this.page, required this.tilt});

  final double page;
  final double tilt;

  /// How far past the screen edges a layer at [depth] must be drawn so
  /// moving it never uncovers an edge.
  Offset overscan(double depth) =>
      Offset((page / 2 + tilt) * depth + 2, tilt * depth + 2);
}

/// Moves [child] by the page offset and tilt, scaled by [depth].
class _Layer extends StatelessWidget {
  const _Layer({
    required this.depth,
    required this.travel,
    required this.tilt,
    required this.child,
  });

  final double depth;
  final _Travel travel;
  final bool tilt;
  final Widget child;

  @override
  Widget build(BuildContext context) => TiltBuilder(
    enabled: tilt,
    builder: (context, tilt) {
      final page = Wallpaper.pageOffsetOf(context).dx;
      // Layers slide toward the lowered edge, as if pulled by gravity.
      final offset = Offset(
        ((0.5 - page) * travel.page + tilt.dx * travel.tilt) * depth,
        tilt.dy * travel.tilt * depth,
      );
      // Only the transform changes from frame to frame; the painted layer
      // below the repaint boundary is reused.
      return Transform.translate(offset: offset, child: child);
    },
  );
}

/// One ridge line: a few sine waves with seeded phases.
class _Ridge {
  const _Ridge({
    required this.depth,
    required this.top,
    required this.height,
    required this.roughness,
    required this.seed,
    this.trees = 0,
  });

  /// How strongly the ridge moves: 0 is fixed, 1 moves the full travel.
  final double depth;

  /// The ridge line's average height, as a fraction of the screen height
  /// from the top.
  final double top;

  /// How far peaks rise above [top], as a fraction of the screen height.
  final double height;

  /// 0 gives rolling hills, 1 jagged peaks.
  final double roughness;

  final int seed;

  /// Pine trees per screen width along the ridge line.
  final double trees;

  /// The ridge line at [u] screen widths from the left, from -1 to 1.
  double lineAt(double u, List<(double, double, double)> waves) {
    var sum = 0.0;
    var total = 0.0;
    for (final (frequency, amplitude, phase) in waves) {
      sum += amplitude * math.sin(u * frequency * 2 * math.pi + phase);
      total += amplitude;
    }
    return sum / total;
  }

  /// (frequency per screen width, amplitude, phase) for each wave.
  List<(double, double, double)> waves() {
    final random = math.Random(seed);
    const octaves = [(0.7, 1.0), (1.6, 0.55), (3.4, 0.3), (7.3, 0.16)];
    return [
      for (final (i, (frequency, amplitude)) in octaves.indexed)
        (
          frequency * (0.8 + 0.4 * random.nextDouble()),
          amplitude * (i < 2 ? 1 : roughness),
          random.nextDouble() * 2 * math.pi,
        ),
    ];
  }
}

const _ridges = [
  _Ridge(depth: 0.15, top: 0.50, height: 0.11, roughness: 1, seed: 3),
  _Ridge(depth: 0.3, top: 0.57, height: 0.08, roughness: 0.7, seed: 11),
  _Ridge(depth: 0.5, top: 0.65, height: 0.06, roughness: 0.45, seed: 23),
  _Ridge(
    depth: 0.75,
    top: 0.74,
    height: 0.05,
    roughness: 0.3,
    seed: 5,
    trees: 30,
  ),
  _Ridge(
    depth: 1,
    top: 0.85,
    height: 0.04,
    roughness: 0.2,
    seed: 41,
    trees: 20,
  ),
];

class _RidgePainter extends CustomPainter {
  _RidgePainter(
    this.ridge,
    this.overscan, {
    required this.color,
    required this.fog,
  });

  final _Ridge ridge;

  /// How far past each edge to draw.
  final Offset overscan;
  final Color color;

  /// The color the ridge fades toward at its foot, like valley mist.
  final Color fog;

  @override
  void paint(Canvas canvas, Size size) {
    final waves = ridge.waves();
    double lineY(double x) =>
        (ridge.top - ridge.height * ridge.lineAt(x / size.width, waves)) *
        size.height;

    final left = -overscan.dx;
    final right = size.width + overscan.dx;
    final bottom = size.height + overscan.dy;
    final step = size.width / 90;
    final path = Path()..moveTo(left, bottom);
    for (var x = left; x < right + step; x += step) {
      path.lineTo(x, lineY(x));
    }
    path
      ..lineTo(right + step, bottom)
      ..close();

    _addTrees(path, lineY, left, right, size);

    final peak = (ridge.top - ridge.height) * size.height;
    final foot = (ridge.top + 0.2) * size.height;
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color, Color.lerp(color, fog, 0.45)!],
        ).createShader(Rect.fromLTRB(left, peak, right, foot)),
    );
  }

  void _addTrees(
    Path path,
    double Function(double x) lineY,
    double left,
    double right,
    Size size,
  ) {
    if (ridge.trees <= 0) return;
    final random = math.Random(ridge.seed * 31);
    final spacing = size.width / ridge.trees;
    for (var x = left; x < right; x += spacing * (0.4 + random.nextDouble())) {
      // Leave clearings.
      if (random.nextDouble() < 0.3) continue;
      final height =
          size.height * ridge.depth * (0.03 + 0.03 * random.nextDouble());
      final width = height * 0.45;
      final base = lineY(x) + height * 0.15;
      path
        ..moveTo(x - width / 2, base)
        ..lineTo(x, base - height)
        ..lineTo(x + width / 2, base)
        ..close();
    }
  }

  @override
  bool shouldRepaint(_RidgePainter old) =>
      old.ridge != ridge ||
      old.color != color ||
      old.fog != fog ||
      old.overscan != overscan;
}

class _SunPainter extends CustomPainter {
  _SunPainter(this.palette, this.overscan);

  final DemoPalette palette;
  final Offset overscan;

  @override
  void paint(Canvas canvas, Size size) {
    final night = palette == DemoPalette.night;
    final center = Offset(size.width * 0.7, size.height * 0.38);
    final radius = size.width * (night ? 0.045 : 0.065);
    final glow = size.width * (night ? 0.3 : 0.45);
    canvas
      ..drawCircle(
        center,
        glow,
        Paint()
          ..shader = RadialGradient(
            colors: [
              palette.light.withValues(alpha: night ? 0.18 : 0.4),
              palette.light.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: glow)),
      )
      ..drawCircle(center, radius, Paint()..color = palette.light);
  }

  @override
  bool shouldRepaint(_SunPainter old) =>
      old.palette != palette || old.overscan != overscan;
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.color, this.overscan);

  final Color color;
  final Offset overscan;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 140; i++) {
      final position = Offset(
        -overscan.dx + random.nextDouble() * (size.width + 2 * overscan.dx),
        random.nextDouble() * size.height * 0.6,
      );
      paint.color = color.withValues(alpha: 0.25 + 0.6 * random.nextDouble());
      canvas.drawCircle(position, 0.4 + random.nextDouble() * 0.9, paint);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) =>
      old.color != color || old.overscan != overscan;
}
