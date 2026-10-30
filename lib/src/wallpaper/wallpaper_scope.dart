import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../messages.dart';
import 'commands.dart';
import 'tilt.dart';
import 'wallpaper_controller.dart';
import 'wallpaper_data.dart';

/// Provides [WallpaperData] and tilt to the widgets below it.
///
/// `runWallpaper` inserts one automatically. Insert your own in tests or
/// previews to drive a scene with fixed or scripted state:
///
/// ```dart
/// WallpaperScope(
///   data: ValueNotifier(const WallpaperData(visible: true, zoom: 0.3)),
///   tilt: ValueNotifier(const Offset(0.2, 0)),
///   child: const MyScene(),
/// )
/// ```
class WallpaperScope extends StatelessWidget {
  /// Creates a scope that rebuilds dependents when [data] or [tilt] change.
  const WallpaperScope({
    super.key,
    required this.data,
    this.tilt,
    required this.child,
  });

  /// The state to provide.
  final ValueListenable<WallpaperData> data;

  /// The tilt that [WallpaperTilt.of] returns below this scope, or null for
  /// none ([Offset.zero]).
  final ValueListenable<Offset>? tilt;

  /// The widget below this one.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WallpaperData>(
      valueListenable: data,
      builder: (context, value, child) =>
          _WallpaperModel(data: value, child: child!),
      child: switch (tilt) {
        final tilt? => TiltScope(tilt: tilt, child: child),
        null => child,
      },
    );
  }
}

enum _Aspect { visible, preview, target, page, zoom, config }

class _WallpaperModel extends InheritedModel<_Aspect> {
  const _WallpaperModel({required this.data, required super.child});

  final WallpaperData data;

  @override
  bool updateShouldNotify(_WallpaperModel oldWidget) => data != oldWidget.data;

  @override
  bool updateShouldNotifyDependent(
    _WallpaperModel oldWidget,
    Set<_Aspect> dependencies,
  ) {
    final old = oldWidget.data;
    return dependencies.any(
      (aspect) => switch (aspect) {
        _Aspect.visible => data.visible != old.visible,
        _Aspect.preview => data.isPreview != old.isPreview,
        _Aspect.target => data.target != old.target,
        _Aspect.page =>
          data.pageOffset != old.pageOffset || data.pageStep != old.pageStep,
        _Aspect.zoom => data.zoom != old.zoom,
        _Aspect.config => !jsonValueEquals(data.config, old.config),
      },
    );
  }
}

/// Access to the live wallpaper this widget tree runs in.
///
/// Read state the way you read `MediaQuery`: [of] for everything, or one of
/// the `...Of` methods so a widget rebuilds only when that value changes. Page
/// offsets change every frame during a home screen swipe, so a widget that
/// only needs [visibleOf] shouldn't call [of].
///
/// ```dart
/// class Parallax extends StatelessWidget {
///   const Parallax({super.key});
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
abstract final class Wallpaper {
  /// All wallpaper state. Rebuilds the caller on any change.
  ///
  /// Throws if there's no [WallpaperScope] above [context]; `runWallpaper`
  /// adds one.
  static WallpaperData of(BuildContext context) => _of(context, null);

  /// Like [of], but returns null instead of throwing when there's no
  /// [WallpaperScope].
  static WallpaperData? maybeOf(BuildContext context) =>
      InheritedModel.inheritFrom<_WallpaperModel>(context)?.data;

  /// [WallpaperData.visible]. Rebuilds the caller only when it changes.
  static bool visibleOf(BuildContext context) =>
      _of(context, _Aspect.visible).visible;

  /// [WallpaperData.isPreview]. Rebuilds the caller only when it changes.
  static bool isPreviewOf(BuildContext context) =>
      _of(context, _Aspect.preview).isPreview;

  /// [WallpaperData.target]. Rebuilds the caller only when it changes.
  static WallpaperTarget targetOf(BuildContext context) =>
      _of(context, _Aspect.target).target;

  /// [WallpaperData.pageOffset]. Rebuilds the caller when the page offset or
  /// step changes.
  static Offset pageOffsetOf(BuildContext context) =>
      _of(context, _Aspect.page).pageOffset;

  /// [WallpaperData.pageStep]. Rebuilds the caller when the page offset or
  /// step changes.
  static Offset pageStepOf(BuildContext context) =>
      _of(context, _Aspect.page).pageStep;

  /// [WallpaperData.zoom]. Rebuilds the caller only when it changes.
  static double zoomOf(BuildContext context) => _of(context, _Aspect.zoom).zoom;

  /// [WallpaperData.config]. Rebuilds the caller only when it changes.
  static Map<String, Object?> configOf(BuildContext context) =>
      _of(context, _Aspect.config).config;

  /// The current state outside the widget tree, for example in a game loop.
  /// Listen to it to react to changes.
  static ValueListenable<WallpaperData> get data =>
      WallpaperController.instance.data;

  /// Commands from the launcher or the system, such as taps on empty home
  /// screen space. A broadcast stream.
  static Stream<WallpaperCommand> get commands =>
      WallpaperController.instance.commands;

  /// Messages the app sent with `LiveWallpaper.send`. A broadcast stream.
  static Stream<WallpaperMessage> get messages =>
      WallpaperController.instance.messages;

  /// Sends a message to the app, which receives it on
  /// `LiveWallpaper.messages`. Returns how many app engines received it: 0
  /// when the app's UI isn't running.
  ///
  /// [data] can be null, a bool, number or string, or lists and string-keyed
  /// maps of those.
  static Future<int> sendToApp(String name, {Object? data}) =>
      WallpaperController.instance.sendToApp(name, data);

  /// Tells Android the wallpaper's main colors, which it uses for Material
  /// You theming (on Android 12 and later) and to pick light or dark text over
  /// the wallpaper.
  ///
  /// Report again when the scene's look changes, not every frame: Android
  /// recomputes the system theme each time. Requires Android 8.1 (API 27);
  /// the hints require Android 12 (API 31) and are ignored before that.
  static Future<void> reportColors(
    Color primary, {
    Color? secondary,
    Color? tertiary,
    bool supportsDarkText = false,
    bool supportsDarkTheme = false,
  }) {
    return WallpaperController.instance.reportColors(
      primary: primary.toARGB32(),
      secondary: secondary?.toARGB32(),
      tertiary: tertiary?.toARGB32(),
      hints: (supportsDarkText ? 1 : 0) | (supportsDarkTheme ? 2 : 0),
    );
  }

  static WallpaperData _of(BuildContext context, _Aspect? aspect) {
    final model = InheritedModel.inheritFrom<_WallpaperModel>(
      context,
      aspect: aspect,
    );
    if (model == null) {
      throw FlutterError.fromParts([
        ErrorSummary('No WallpaperScope found.'),
        ErrorDescription(
          '${context.widget.runtimeType} read wallpaper state, but there is '
          'no WallpaperScope above it.',
        ),
        ErrorHint(
          'Start the wallpaper with runWallpaper(), which adds a '
          'WallpaperScope, or wrap the widget in a WallpaperScope yourself '
          '(for example in a test).',
        ),
      ]);
    }
    return model.data;
  }
}

/// Device tilt for parallax, smoothed and re-centered, each axis in -1..1.
///
/// `dx` grows as the right edge of the screen dips, and `dy` grows as the top
/// edge tips away from the viewer. Shift background layers against it:
///
/// ```dart
/// final tilt = WallpaperTilt.of(context);
/// return Transform.translate(
///   offset: Offset(-tilt.dx * 24, -tilt.dy * 24),
///   child: const Background(),
/// );
/// ```
///
/// The sensor runs only while something reads tilt *and* the wallpaper is
/// visible: a widget that called [of] and is still mounted, or a listener on
/// [listenable]. Each sample makes dependents rebuild, so read it only in
/// the widgets that move.
abstract final class WallpaperTilt {
  /// The current tilt. Rebuilds [context] when it changes and keeps the
  /// sensor on while [context] is mounted, even if a later build stops
  /// calling this. To turn tilt off, read it in a small widget of its own and
  /// leave that widget out. [Offset.zero] outside a wallpaper.
  static Offset of(BuildContext context) => TiltModel.of(context);

  /// The current tilt outside the widget tree, for example in a game loop.
  /// The sensor runs while it has listeners and the wallpaper is visible.
  static ValueListenable<Offset> get listenable => _controller;

  /// How the sensor samples and how values are filtered.
  static WallpaperTiltSettings get settings => _controller.settings;

  static set settings(WallpaperTiltSettings value) =>
      _controller.settings = value;

  static TiltController get _controller => WallpaperController.instance.tilt;
}
