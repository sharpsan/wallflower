import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

import '../config.dart';
import 'common.dart';

/// A field of particles at rest. A tap on the home screen sends a ripple
/// through it, and swipes and tilt drag its depth layers along on springs.
///
/// Everything settles back to rest, and once it has, the scene stops drawing
/// frames until the next tap, swipe or tilt.
class ParticlesScene extends StatelessWidget {
  const ParticlesScene({super.key, required this.config, this.taps});

  final DemoConfig config;

  /// Taps to ripple from, in the scene's coordinates. Leave null on the
  /// wallpaper, where the launcher's tap commands are used; the settings
  /// app's preview passes its own.
  final Stream<Offset>? taps;

  @override
  Widget build(BuildContext context) => TiltBuilder(
    enabled: config.tilt,
    builder: (context, tilt) => _ParticleField(
      config: config,
      page: Wallpaper.pageOffsetOf(context).dx,
      tilt: tilt,
      taps: taps,
    ),
  );
}

class _ParticleField extends StatefulWidget {
  const _ParticleField({
    required this.config,
    required this.page,
    required this.tilt,
    required this.taps,
  });

  final DemoConfig config;
  final double page;
  final Offset tilt;
  final Stream<Offset>? taps;

  @override
  State<_ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<_ParticleField>
    with SingleTickerProviderStateMixin {
  static const _depths = [0.25, 0.5, 0.75, 1.0];

  late final Ticker _ticker;
  // Bumped every tick to repaint without rebuilding.
  final _repaint = ValueNotifier(0);
  StreamSubscription<Object>? _input;

  _Particles? _particles;
  Size _size = Size.zero;
  final _ripples = <_Ripple>[];
  Duration _now = Duration.zero;
  Duration _lastTick = Duration.zero;

  // Each depth layer follows the page offset and tilt on a spring.
  final _shift = List.filled(_depths.length, Offset.zero);
  final _shiftVelocity = List.filled(_depths.length, Offset.zero);
  final _shiftTarget = List.filled(_depths.length, Offset.zero);

  // The last pointer down, to place ripples from tap commands precisely.
  Offset? _pointer;
  DateTime? _pointerTime;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _listen();
  }

  @override
  void didUpdateWidget(_ParticleField old) {
    super.didUpdateWidget(old);
    if (old.taps != widget.taps) _listen();
    if (old.config.intensity != widget.config.intensity) _particles = null;
    if (old.page != widget.page ||
        old.tilt != widget.tilt ||
        old.config.intensity != widget.config.intensity) {
      _updateTargets();
    }
  }

  @override
  void dispose() {
    _input?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _listen() {
    _input?.cancel();
    final taps = widget.taps;
    _input = taps != null
        ? taps.listen(_ripple)
        : Wallpaper.commands.listen(_onCommand);
  }

  void _onCommand(WallpaperCommand command) {
    if (command.isTap) {
      // Launchers send tap commands only for taps on empty space, but their
      // coordinates can be off by a few percent. The pointer event from the
      // same tap has the exact position.
      final pointer = _pointer;
      final recent =
          _pointerTime != null &&
          DateTime.now().difference(_pointerTime!) <
              const Duration(milliseconds: 600);
      _ripple(pointer != null && recent ? pointer : command.position);
    } else if (command.action == WallpaperCommand.wakingUp) {
      _ripple(Offset(_size.width / 2, _size.height), strength: 0.5);
    }
  }

  // How far a layer at depth 1 travels across all pages, and with full tilt.
  double get _pageTravel => _size.width * (0.1 + 0.3 * widget.config.intensity);
  double get _tiltTravel =>
      _size.width * (0.03 + 0.05 * widget.config.intensity);

  void _updateTargets({bool start = true}) {
    for (final (i, depth) in _depths.indexed) {
      _shiftTarget[i] = Offset(
        ((0.5 - widget.page) * _pageTravel + widget.tilt.dx * _tiltTravel) *
            depth,
        widget.tilt.dy * _tiltTravel * depth,
      );
    }
    if (start) _start();
  }

  void _ripple(Offset center, {double strength = 1}) {
    if (_size.isEmpty) return;
    if (_ripples.length == 4) _ripples.removeAt(0);
    // Ripples are sized for a phone; scale them for smaller previews.
    _ripples.add(_Ripple(center, _now, strength, _size.shortestSide / 400));
    _start();
  }

  void _start() {
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min((elapsed - _lastTick).inMicroseconds / 1e6, 1 / 30);
    _lastTick = elapsed;
    _now += Duration(microseconds: (dt * 1e6).round());
    final particles = _particles;
    if (particles == null) {
      _ticker.stop();
      return;
    }

    var moving = false;
    for (var i = 0; i < _depths.length; i++) {
      // A slightly bouncy spring; deeper layers trail a little more.
      final omega = 2 * math.pi * (1.6 - 0.6 * _depths[i]);
      final accel =
          (_shiftTarget[i] - _shift[i]) * (omega * omega) -
          _shiftVelocity[i] * (2 * 0.6 * omega);
      _shiftVelocity[i] += accel * dt;
      _shift[i] += _shiftVelocity[i] * dt;
      if ((_shiftTarget[i] - _shift[i]).distance > 0.1 ||
          _shiftVelocity[i].distance > 1) {
        moving = true;
      }
    }

    _ripples.removeWhere((r) => r.age(_now) > _Ripple.lifetime);
    if (particles.step(dt, _ripples, _now, widget.config.intensity, _shift)) {
      moving = true;
    }
    _repaint.value++;
    if (!moving && _ripples.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.config.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _size || _particles == null) {
          _size = size;
          _particles = _Particles(
            count: (120 + 520 * widget.config.intensity).round(),
            size: size,
            overscan:
                Offset(_pageTravel / 2 + _tiltTravel, _tiltTravel) +
                const Offset(8, 8),
            layers: _depths.length,
          );
          // Start at rest, without springing in from the old size.
          _updateTargets(start: false);
          for (var i = 0; i < _depths.length; i++) {
            _shift[i] = _shiftTarget[i];
            _shiftVelocity[i] = Offset.zero;
          }
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            _pointer = event.localPosition;
            _pointerTime = DateTime.now();
          },
          child: CustomPaint(size: size, painter: _FieldPainter(this, palette)),
        );
      },
    );
  }
}

class _Ripple {
  _Ripple(this.center, this.start, this.strength, this.scale);

  static const lifetime = 1.6;

  final Offset center;
  final Duration start;
  final double strength;

  /// 1 on a 400-pixel-wide phone.
  final double scale;

  double age(Duration now) => (now - start).inMicroseconds / 1e6;

  double radius(Duration now) => age(now) * 900 * scale;

  /// How wide the pushing band around the wave front is.
  double get band => 50 * scale;

  /// 1 when fresh, fading to 0 at [lifetime].
  double fade(Duration now) =>
      math.pow(1 - (age(now) / lifetime).clamp(0.0, 1.0), 1.5).toDouble();
}

/// Rest positions, ripple displacements and velocities, in flat lists.
class _Particles {
  _Particles({
    required int count,
    required Size size,
    required Offset overscan,
    required int layers,
  }) {
    // A jittered grid over the screen plus its overscan, so particles are
    // spread evenly but not in rows.
    final random = math.Random(1);
    final width = size.width + 2 * overscan.dx;
    final height = size.height + 2 * overscan.dy;
    final cell = math.sqrt(size.width * size.height / count);
    final columns = (width / cell).ceil();
    final rows = (height / cell).ceil();
    final n = columns * rows;
    restX = Float32List(n);
    restY = Float32List(n);
    dx = Float32List(n);
    dy = Float32List(n);
    vx = Float32List(n);
    vy = Float32List(n);
    layer = Uint8List(n);
    var i = 0;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        restX[i] = -overscan.dx + (column + random.nextDouble()) * cell;
        restY[i] = -overscan.dy + (row + random.nextDouble()) * cell;
        layer[i] = random.nextInt(layers);
        i++;
      }
    }
  }

  late final Float32List restX, restY, dx, dy, vx, vy;
  late final Uint8List layer;

  int get length => restX.length;

  /// Advances the ripple physics. Returns whether anything still moves.
  bool step(
    double dt,
    List<_Ripple> ripples,
    Duration now,
    double intensity,
    List<Offset> shifts,
  ) {
    const omega = 2 * math.pi * 1.1;
    const damping = 2 * 0.35 * omega;
    final push = 1500 * (0.5 + intensity);
    var moving = false;
    for (var i = 0; i < length; i++) {
      var ax = -dx[i] * omega * omega - vx[i] * damping;
      var ay = -dy[i] * omega * omega - vy[i] * damping;
      for (final ripple in ripples) {
        final shift = shifts[layer[i]];
        final px = restX[i] + shift.dx - ripple.center.dx;
        final py = restY[i] + shift.dy - ripple.center.dy;
        final distance = math.sqrt(px * px + py * py);
        if (distance < 1) continue;
        // A band around the wave front pushes outward.
        final front = (distance - ripple.radius(now)) / ripple.band;
        if (front.abs() > 3) continue;
        final force =
            push *
            ripple.scale *
            ripple.strength *
            ripple.fade(now) *
            math.exp(-front * front);
        ax += force * px / distance;
        ay += force * py / distance;
      }
      vx[i] += ax * dt;
      vy[i] += ay * dt;
      dx[i] += vx[i] * dt;
      dy[i] += vy[i] * dt;
      if (!moving &&
          (dx[i].abs() > 0.05 ||
              dy[i].abs() > 0.05 ||
              vx[i].abs() > 0.5 ||
              vy[i].abs() > 0.5)) {
        moving = true;
      }
    }
    return moving;
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.state, this.palette) : super(repaint: state._repaint);

  final _ParticleFieldState state;
  final DemoPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.2,
          colors: [
            Color.lerp(palette.skyTop, palette.skyBottom, 0.35)!,
            palette.skyTop,
            palette.deep,
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    final particles = state._particles;
    if (particles == null) return;
    final now = state._now;

    // Ripple rings.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final ripple in state._ripples) {
      ring.color = palette.light.withValues(
        alpha: 0.35 * ripple.fade(now) * ripple.strength,
      );
      canvas.drawCircle(ripple.center, ripple.radius(now), ring);
    }

    // Particles, one batch per depth layer, plus brighter batches for the
    // ones a ripple is moving.
    final layers = _ParticleFieldState._depths.length;
    final calm = List.generate(layers, (_) => <double>[]);
    final excited = List.generate(layers, (_) => <double>[]);
    for (var i = 0; i < particles.length; i++) {
      final layer = particles.layer[i];
      final shift = state._shift[layer];
      final x = particles.restX[i] + particles.dx[i] + shift.dx;
      final y = particles.restY[i] + particles.dy[i] + shift.dy;
      if (x < -4 || y < -4 || x > size.width + 4 || y > size.height + 4) {
        continue;
      }
      final moved = particles.dx[i].abs() + particles.dy[i].abs() > 2.5;
      (moved ? excited : calm)[layer].addAll([x, y]);
    }
    final dark = palette.isDark;
    final base = dark ? palette.skyBottom : palette.deep;
    final bright = dark ? palette.light : palette.skyTop;
    for (var layer = 0; layer < layers; layer++) {
      final depth = _ParticleFieldState._depths[layer];
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.2 + 2.6 * depth;
      paint.color = base.withValues(alpha: 0.25 + 0.45 * depth);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(calm[layer]),
        paint,
      );
      paint.color = bright.withValues(alpha: 0.5 + 0.5 * depth);
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(excited[layer]),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.state != state || old.palette != palette;
}
