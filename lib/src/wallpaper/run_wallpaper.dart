import 'dart:async';

import 'package:flutter/widgets.dart';

import 'wallpaper_controller.dart';
import 'wallpaper_scope.dart';

/// Runs [child] as the live wallpaper. Call it from the wallpaper's Dart
/// entrypoint instead of `runApp`.
///
/// ```dart
/// @pragma('vm:entry-point')
/// void wallpaperMain() => runWallpaper(const MyScene());
/// ```
///
/// The entrypoint needs `@pragma('vm:entry-point')` so release builds keep
/// it, and its name must match the service's `wallflower.entrypoint`
/// meta-data (default `wallpaperMain`).
///
/// [child] is placed under a [WallpaperScope], a left-to-right
/// [Directionality] and a [background] fill. There's no `MaterialApp` or
/// `WidgetsApp`; add one inside [child] if the scene needs themes,
/// localizations or Material widgets.
///
/// Called from an ordinary app instead of a wallpaper engine, it still runs
/// the scene, with [WallpaperData.visible] true and every other value at its
/// default. That's handy for developing a scene.
void runWallpaper(Widget child, {Color background = const Color(0xFF000000)}) {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = WallpaperController.instance;
  unawaited(controller.attach());
  runApp(
    WallpaperScope(
      data: controller.data,
      tilt: controller.tilt,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(color: background, child: child),
      ),
    ),
  );
}
