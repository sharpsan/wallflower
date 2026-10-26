import 'package:flutter/widgets.dart';

/// The scenes the demo wallpaper can show.
enum DemoScene {
  /// Layered mountain ridges that move with page swipes and device tilt.
  parallax('Parallax'),

  /// A field of particles that ripples where you tap.
  particles('Particles'),

  /// A minimal clock that sets the system's Material You colors.
  clock('Clock');

  const DemoScene(this.label);

  /// A short name for the settings screen.
  final String label;
}

/// A color scheme every scene draws from.
enum DemoPalette {
  dusk(
    label: 'Dusk',
    skyTop: Color(0xFF1B2340),
    skyBottom: Color(0xFFE8876B),
    light: Color(0xFFFFD6A0),
    haze: Color(0xFFA9707C),
    deep: Color(0xFF0E1222),
  ),
  dawn(
    label: 'Dawn',
    skyTop: Color(0xFF5D6FA8),
    skyBottom: Color(0xFFF7C9A8),
    light: Color(0xFFFFF4E0),
    haze: Color(0xFFC0909F),
    deep: Color(0xFF2E2440),
  ),
  forest(
    label: 'Forest',
    skyTop: Color(0xFF1F3A42),
    skyBottom: Color(0xFFB9CFB5),
    light: Color(0xFFF2F5E8),
    haze: Color(0xFF7FA08E),
    deep: Color(0xFF0B1C17),
  ),
  desert(
    label: 'Desert',
    skyTop: Color(0xFF2E4A7D),
    skyBottom: Color(0xFFF2B66D),
    light: Color(0xFFFFF0C9),
    haze: Color(0xFFC47F58),
    deep: Color(0xFF3A1D13),
  ),
  night(
    label: 'Night',
    skyTop: Color(0xFF04060E),
    skyBottom: Color(0xFF1F2B57),
    light: Color(0xFFE6EBFF),
    haze: Color(0xFF2B396A),
    deep: Color(0xFF02040A),
  ),
  glacier(
    label: 'Glacier',
    skyTop: Color(0xFF9DBDE3),
    skyBottom: Color(0xFFEAF2FA),
    light: Color(0xFFFFFFFF),
    haze: Color(0xFF9AB2CE),
    deep: Color(0xFF33465D),
  );

  const DemoPalette({
    required this.label,
    required this.skyTop,
    required this.skyBottom,
    required this.light,
    required this.haze,
    required this.deep,
  });

  /// A short name for the settings screen.
  final String label;

  /// The top of the sky.
  final Color skyTop;

  /// The sky at the horizon: the palette's signature color.
  final Color skyBottom;

  /// The sun or moon, and other highlights.
  final Color light;

  /// The farthest ridge, faded by distance.
  final Color haze;

  /// The nearest, darkest shade.
  final Color deep;

  /// Whether light text reads better on this palette's backgrounds.
  bool get isDark => skyTop.computeLuminance() < 0.3;
}

/// The settings the app saves and the wallpaper reads, as a JSON-friendly
/// config map (`LiveWallpaper.setConfig` / `Wallpaper.configOf`).
@immutable
class DemoConfig {
  const DemoConfig({
    this.scene = DemoScene.parallax,
    this.palette = DemoPalette.dusk,
    this.intensity = 0.6,
    this.tilt = true,
  });

  /// Reads a config map, falling back to defaults for anything missing or
  /// unknown, such as values written by an older version of the app.
  factory DemoConfig.fromJson(Map<String, Object?> json) {
    const defaults = DemoConfig();
    final intensity = json['intensity'];
    return DemoConfig(
      scene: _byName(DemoScene.values, json['scene']) ?? defaults.scene,
      palette: _byName(DemoPalette.values, json['palette']) ?? defaults.palette,
      intensity: intensity is num
          ? intensity.toDouble().clamp(0.0, 1.0)
          : defaults.intensity,
      tilt: json['tilt'] is bool ? json['tilt']! as bool : defaults.tilt,
    );
  }

  final DemoScene scene;
  final DemoPalette palette;

  /// 0..1. Each scene uses it its own way: parallax depth, particle count,
  /// or color strength.
  final double intensity;

  /// Whether scenes may follow device tilt. Off keeps the sensor off.
  final bool tilt;

  Map<String, Object?> toJson() => {
    'scene': scene.name,
    'palette': palette.name,
    'intensity': intensity,
    'tilt': tilt,
  };

  DemoConfig copyWith({
    DemoScene? scene,
    DemoPalette? palette,
    double? intensity,
    bool? tilt,
  }) => DemoConfig(
    scene: scene ?? this.scene,
    palette: palette ?? this.palette,
    intensity: intensity ?? this.intensity,
    tilt: tilt ?? this.tilt,
  );

  @override
  bool operator ==(Object other) =>
      other is DemoConfig &&
      other.scene == scene &&
      other.palette == palette &&
      other.intensity == intensity &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(scene, palette, intensity, tilt);

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
