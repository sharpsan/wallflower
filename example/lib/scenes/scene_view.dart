import 'package:flutter/widgets.dart';

import '../config.dart';
import 'clock_scene.dart';
import 'particles_scene.dart';
import 'parallax_scene.dart';

/// The scene [config] picks, cross-fading when the scene changes. Used by
/// both the wallpaper and the settings app's preview.
class SceneView extends StatelessWidget {
  const SceneView({super.key, required this.config, this.taps});

  final DemoConfig config;

  /// Taps for scenes that react to them, in the preview. The wallpaper
  /// leaves this null and uses the launcher's tap commands.
  final Stream<Offset>? taps;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 500),
    child: KeyedSubtree(
      key: ValueKey(config.scene),
      child: switch (config.scene) {
        DemoScene.parallax => ParallaxScene(config: config),
        DemoScene.particles => ParticlesScene(config: config, taps: taps),
        DemoScene.clock => ClockScene(config: config),
      },
    ),
  );
}
