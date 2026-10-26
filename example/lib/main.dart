import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

import 'config.dart';
import 'scenes/clock_scene.dart';
import 'scenes/scene_view.dart';
import 'settings_app.dart';

/// The settings app: pick a scene, colors and intensity, and set the live
/// wallpaper. Changes reach the running wallpaper immediately.
void main() => runApp(const SettingsApp());

/// The live wallpaper. It runs in its own Flutter engine inside the
/// wallpaper service, which finds this function through the
/// `wallflower.entrypoint` meta-data in `AndroidManifest.xml`.
@pragma('vm:entry-point')
void wallpaperMain() => runWallpaper(const DemoWallpaper());

/// Shows the scene from the app's config, reports its colors to Android for
/// Material You, and answers status requests from the app.
class DemoWallpaper extends StatefulWidget {
  const DemoWallpaper({super.key});

  @override
  State<DemoWallpaper> createState() => _DemoWallpaperState();
}

class _DemoWallpaperState extends State<DemoWallpaper> {
  late final StreamSubscription<WallpaperMessage> _messages;
  DemoConfig? _config;

  @override
  void initState() {
    super.initState();
    _messages = Wallpaper.messages.listen(_onMessage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The config the app saved with LiveWallpaper.setConfig. Rebuilds when
    // the app changes it.
    final config = DemoConfig.fromJson(Wallpaper.configOf(context));
    if (config != _config) {
      _config = config;
      _reportColors(config);
    }
  }

  @override
  void dispose() {
    _messages.cancel();
    super.dispose();
  }

  /// Tells Android which colors the wallpaper shows, for Material You and
  /// for the status bar's icon color. Only on changes: every report makes
  /// the system recompute its theme.
  void _reportColors(DemoConfig config) {
    final palette = config.palette;
    final (top, bottom) = switch (config.scene) {
      DemoScene.clock => ClockScene.colors(config),
      _ => (palette.skyTop, palette.skyBottom),
    };
    unawaited(
      Wallpaper.reportColors(
        bottom,
        secondary: top,
        tertiary: palette.light,
        supportsDarkText: !palette.isDark,
        supportsDarkTheme: palette.isDark,
      ),
    );
  }

  void _onMessage(WallpaperMessage message) {
    if (message.name != 'status') return;
    final data = Wallpaper.data.value;
    unawaited(
      Wallpaper.sendToApp(
        'status',
        data: {
          'scene': _config?.scene.name,
          'target': data.target.name,
          'preview': data.isPreview,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SceneView(config: _config!);
}
