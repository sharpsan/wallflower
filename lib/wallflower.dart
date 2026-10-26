/// Live wallpapers for Android built from Flutter widgets.
///
/// wallflower runs a Flutter widget tree as an Android live wallpaper: the
/// wallpaper service spawns a Flutter engine that renders straight into the
/// home screen (and lock screen) wallpaper surface. Animated scenes, parallax
/// that follows home screen swipes, and tap effects are ordinary widgets.
///
/// The wallpaper runs in its own isolate, started from a Dart entrypoint:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void wallpaperMain() => runWallpaper(const MyScene());
///
/// class MyScene extends StatelessWidget {
///   const MyScene({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     final page = Wallpaper.pageOffsetOf(context);
///     return Transform.translate(
///       offset: Offset(-page.dx * 40, 0),
///       child: const MyLayers(),
///     );
///   }
/// }
/// ```
///
/// The app declares `app.sharpsan.wallflower.FlutterWallpaperService` (an
/// Android `WallpaperService`) in its manifest; see the README for setup.
///
/// In the wallpaper:
/// * [runWallpaper] starts the scene.
/// * [Wallpaper] reads wallpaper state ([WallpaperData]: visibility, page
///   offsets, zoom, config), receives [WallpaperCommand]s and app
///   [WallpaperMessage]s, and reports colors for Material You theming.
/// * [WallpaperTilt] gives smoothed device tilt for parallax.
/// * [WallpaperScope] provides state, for example to drive a scene in tests.
///
/// In the app:
/// * [LiveWallpaper] checks whether the wallpaper is active, opens the system
///   picker, stores the wallpaper's config and sends it messages.
library;

export 'src/app/live_wallpaper.dart' show LiveWallpaper;
export 'src/messages.dart' show WallpaperMessage;
export 'src/wallpaper/commands.dart' show WallpaperCommand;
export 'src/wallpaper/run_wallpaper.dart' show runWallpaper;
export 'src/wallpaper/tilt.dart' show WallpaperTiltSettings;
export 'src/wallpaper/wallpaper_data.dart' show WallpaperData, WallpaperTarget;
export 'src/wallpaper/wallpaper_scope.dart'
    show Wallpaper, WallpaperScope, WallpaperTilt;
