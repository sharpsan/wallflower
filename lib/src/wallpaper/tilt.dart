import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How `WallpaperTilt` samples and filters device tilt.
@immutable
class WallpaperTiltSettings {
  /// Creates tilt settings.
  const WallpaperTiltSettings({
    this.samplingPeriod = const Duration(milliseconds: 20),
    this.smoothing = const Duration(milliseconds: 80),
    this.recenter = const Duration(seconds: 2),
    this.range = 0.35,
  }) : assert(range > 0);

  /// How often the sensor reports. The default matches Android's
  /// `SENSOR_DELAY_GAME`; longer periods save a little power.
  final Duration samplingPeriod;

  /// The time constant of the smoothing filter. Longer is calmer but lags
  /// more. [Duration.zero] disables smoothing.
  final Duration smoothing;

  /// How quickly the neutral position follows the way the phone is held.
  ///
  /// Tilt is measured from this neutral position, so a scene re-centers by
  /// itself after the phone settles into a new angle. Null keeps the neutral
  /// position where it was when the wallpaper became visible.
  final Duration? recenter;

  /// The tilt that maps to 1, as the sine of the angle: 0.35 is about 20
  /// degrees. Larger tilts are clamped.
  final double range;

  @override
  bool operator ==(Object other) =>
      other is WallpaperTiltSettings &&
      other.samplingPeriod == samplingPeriod &&
      other.smoothing == smoothing &&
      other.recenter == recenter &&
      other.range == range;

  @override
  int get hashCode => Object.hash(samplingPeriod, smoothing, recenter, range);
}

/// A source of tilt values that a `WallpaperScope` can provide. The scope
/// tells it how many widgets read tilt, so the sensor runs only while needed.
abstract interface class TiltSource implements ValueListenable<Offset> {
  /// Called with the number of widgets that read tilt through the scope.
  void setWidgetReaders(int count);
}

/// Filters raw samples into tilt values and decides when the sensor runs.
///
/// Native sends the world's up direction projected onto the screen axes. This
/// class re-centers and smooths it on every frame until it settles, then stops
/// ticking.
class TiltController implements TiltSource {
  /// Creates a controller. [onDemandChanged] is called whenever the sensor
  /// should start or stop, or its settings change.
  TiltController({required this.onDemandChanged});

  /// Called with whether tilt is wanted and the current settings.
  final void Function(bool wanted, WallpaperTiltSettings settings)
  onDemandChanged;

  final ValueNotifier<Offset> _value = ValueNotifier(Offset.zero);
  final Map<VoidCallback, int> _listeners = {};
  int _widgetReaders = 0;
  bool _wanted = false;
  bool _visible = false;
  WallpaperTiltSettings _settings = const WallpaperTiltSettings();

  Offset? _raw;
  Offset? _baseline;
  int _quarterTurns = 0;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  /// The current tilt, each axis in -1..1.
  @override
  Offset get value => _value.value;

  /// The current settings.
  WallpaperTiltSettings get settings => _settings;

  set settings(WallpaperTiltSettings settings) {
    if (settings == _settings) return;
    _settings = settings;
    if (_wanted) onDemandChanged(true, settings);
  }

  /// Whether the sensor should be running: someone reads tilt.
  bool get wanted => _wanted;

  /// A listenable for the scope's own use, which doesn't count as a reader.
  ValueListenable<Offset> get scopeValue => _value;

  @override
  void addListener(VoidCallback listener) {
    _listeners.update(listener, (n) => n + 1, ifAbsent: () => 1);
    _value.addListener(listener);
    _updateDemand();
  }

  @override
  void removeListener(VoidCallback listener) {
    final count = _listeners[listener];
    if (count == null) return;
    if (count == 1) {
      _listeners.remove(listener);
    } else {
      _listeners[listener] = count - 1;
    }
    _value.removeListener(listener);
    _updateDemand();
  }

  @override
  void setWidgetReaders(int count) {
    _widgetReaders = count;
    _updateDemand();
  }

  /// Tracks visibility. Hiding stops filtering; showing again re-centers on
  /// the first new sample, since the phone may have moved meanwhile.
  void setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) {
      _ticker?.stop();
      _raw = null;
      _baseline = null;
    }
  }

  /// Adds a raw sample: the up direction projected onto the screen axes.
  ///
  /// [quarterTurns] is the display rotation the axes belong to. When it
  /// changes, the screen axes jump, so the neutral position snaps to the new
  /// sample and the value eases back to zero.
  void addSample(Offset raw, {int quarterTurns = 0}) {
    if (quarterTurns != _quarterTurns) {
      _quarterTurns = quarterTurns;
      _baseline = null;
    }
    _raw = raw;
    _baseline ??= raw;
    if (!_visible) return;
    final ticker = _ticker ??= Ticker(_onTick, debugLabel: 'WallpaperTilt');
    if (!ticker.isActive) {
      _lastTick = Duration.zero;
      ticker.start();
    }
  }

  void _updateDemand() {
    final wanted = _widgetReaders > 0 || _listeners.isNotEmpty;
    if (wanted == _wanted) return;
    _wanted = wanted;
    onDemandChanged(wanted, _settings);
  }

  void _onTick(Duration elapsed) {
    final raw = _raw;
    var baseline = _baseline;
    if (raw == null || baseline == null) {
      _ticker?.stop();
      return;
    }
    final dt = math.min((elapsed - _lastTick).inMicroseconds / 1e6, 0.1);
    _lastTick = elapsed;

    final recenter = _settings.recenter;
    if (recenter != null && recenter > Duration.zero) {
      baseline += (raw - baseline) * _blend(dt, recenter);
      _baseline = baseline;
    }
    final range = _settings.range;
    final target = Offset(
      ((baseline.dx - raw.dx) / range).clamp(-1.0, 1.0),
      ((baseline.dy - raw.dy) / range).clamp(-1.0, 1.0),
    );
    final current = _value.value;
    final next = _settings.smoothing > Duration.zero
        ? current + (target - current) * _blend(dt, _settings.smoothing)
        : target;
    if ((next - current).distance > 1e-4) _value.value = next;

    // Settled once the remaining motion is well under a pixel of parallax.
    // Re-centering stops within half a percent of the neutral position, and
    // the next sample resumes it.
    final settled =
        (target - next).distance < 1e-3 &&
        (recenter == null || (raw - baseline).distance < range * 5e-3);
    if (settled) _ticker?.stop();
  }

  /// The fraction of the way to move in [dt] seconds for time constant [tau].
  static double _blend(double dt, Duration tau) =>
      1 - math.exp(-dt / (tau.inMicroseconds / 1e6));

  /// Releases the ticker. Only tests need this.
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    _value.dispose();
  }
}

/// Provides tilt to the widgets below it and counts how many read it.
class TiltScope extends StatelessWidget {
  /// Creates a scope for [tilt].
  const TiltScope({super.key, required this.tilt, required this.child});

  /// The tilt values.
  final ValueListenable<Offset> tilt;

  /// The widget below this one.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tilt = this.tilt;
    final source = tilt is TiltController ? tilt : null;
    return ValueListenableBuilder<Offset>(
      valueListenable: source?.scopeValue ?? tilt,
      builder: (context, value, child) =>
          TiltModel(value: value, source: source, child: child!),
      child: child,
    );
  }
}

/// The inherited tilt value. Readers register through [of].
class TiltModel extends InheritedWidget {
  /// Creates the model.
  const TiltModel({
    super.key,
    required this.value,
    required this.source,
    required super.child,
  });

  /// The current tilt.
  final Offset value;

  /// Told how many widgets read [value], or null for fixed values.
  final TiltSource? source;

  /// Reads the tilt and registers [context] as a reader. Returns
  /// [Offset.zero] without a scope.
  static Offset of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TiltModel>()?.value ??
      Offset.zero;

  @override
  bool updateShouldNotify(TiltModel oldWidget) => value != oldWidget.value;

  @override
  InheritedElement createElement() => _TiltModelElement(this);
}

class _TiltModelElement extends InheritedElement {
  _TiltModelElement(TiltModel super.widget);

  final Set<Element> _readers = {};
  TiltSource? _reportedTo;

  TiltSource? get _source => (widget as TiltModel).source;

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    super.updateDependencies(dependent, aspect);
    if (_readers.add(dependent)) _report();
  }

  @override
  void removeDependent(Element dependent) {
    super.removeDependent(dependent);
    if (_readers.remove(dependent)) _report();
  }

  @override
  void update(TiltModel newWidget) {
    final oldSource = _source;
    super.update(newWidget);
    if (oldSource != _source) {
      oldSource?.setWidgetReaders(0);
      _report();
    }
  }

  @override
  void unmount() {
    _readers.clear();
    _report();
    super.unmount();
  }

  void _report() {
    final source = _source;
    if (_reportedTo != null && _reportedTo != source) {
      _reportedTo!.setWidgetReaders(0);
    }
    _reportedTo = source;
    source?.setWidgetReaders(_readers.length);
  }
}
