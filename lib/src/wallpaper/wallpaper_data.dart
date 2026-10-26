import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../messages.dart';

/// The screens a live wallpaper is applied to.
enum WallpaperTarget {
  /// Not reported. Android only reports targets on Android 14 (API 34) and
  /// later.
  unknown,

  /// The home screen only.
  home,

  /// The lock screen only.
  lock,

  /// Both the home screen and the lock screen, rendered by one engine.
  homeAndLock;

  /// Decodes Android's `WallpaperManager.FLAG_SYSTEM` (1) and `FLAG_LOCK` (2)
  /// bit flags. Null or 0 decode to [unknown].
  static WallpaperTarget fromFlags(int? flags) {
    if (flags == null) return unknown;
    final home = flags & 1 != 0;
    final lock = flags & 2 != 0;
    if (home && lock) return homeAndLock;
    if (home) return WallpaperTarget.home;
    if (lock) return WallpaperTarget.lock;
    return unknown;
  }

  /// Whether the wallpaper shows on the home screen. False when [unknown].
  bool get includesHome => this == home || this == homeAndLock;

  /// Whether the wallpaper shows on the lock screen. False when [unknown].
  bool get includesLock => this == lock || this == homeAndLock;
}

/// The state of the live wallpaper engine running this widget tree.
///
/// Read it with `Wallpaper.of(context)`, or one field at a time with
/// `Wallpaper.visibleOf(context)` and friends so a widget rebuilds only when
/// that field changes.
@immutable
class WallpaperData {
  /// Creates wallpaper state. All fields have the values a wallpaper has
  /// before the engine reports anything.
  const WallpaperData({
    this.visible = false,
    this.isPreview = false,
    this.target = WallpaperTarget.unknown,
    this.pageOffset = Offset.zero,
    this.pageStep = Offset.zero,
    this.zoom = 0,
    this.config = const {},
  });

  /// Whether the wallpaper is on screen.
  ///
  /// While false the Flutter engine is paused and draws no frames, so there's
  /// no need to stop animations yourself. Use it to pause work that isn't
  /// frame-driven, such as timers or network polling.
  final bool visible;

  /// Whether this engine renders the preview in the system wallpaper picker,
  /// rather than the applied home screen or lock screen wallpaper.
  ///
  /// A preview engine and the applied wallpaper's engine can run at the same
  /// time, each with its own isolate.
  final bool isPreview;

  /// The screens this wallpaper is applied to.
  final WallpaperTarget target;

  /// The launcher's scroll position across its home screen pages, from 0 to 1
  /// on each axis.
  ///
  /// With five pages, `dx` is 0 on the first page, 0.25 on the second and 1 on
  /// the last. Use it for parallax that follows home screen swipes. It's 0 when
  /// the launcher doesn't report offsets.
  final Offset pageOffset;

  /// The [pageOffset] distance between two adjacent pages, or 0 when the
  /// launcher has a single page or doesn't report steps.
  ///
  /// The launcher can change it at any time, for example while a page is
  /// being added or removed during a swipe.
  final Offset pageStep;

  /// How far the launcher has zoomed the wallpaper out, from 0 to 1.
  ///
  /// Pixel Launcher reports about 0.33 with the app drawer open. Android 11
  /// (API 30) and later only; always 0 before that.
  final double zoom;

  /// The config the app set with `LiveWallpaper.setConfig`, or an empty map.
  ///
  /// It's stored on the device, so it's available as soon as the wallpaper
  /// starts, and updates while the wallpaper runs.
  final Map<String, Object?> config;

  /// The number of horizontal home screen pages implied by [pageStep], at
  /// least 1.
  int get pageCount => pageStep.dx > 0 ? (1 / pageStep.dx).round() + 1 : 1;

  /// Returns a copy with the given fields replaced.
  WallpaperData copyWith({
    bool? visible,
    bool? isPreview,
    WallpaperTarget? target,
    Offset? pageOffset,
    Offset? pageStep,
    double? zoom,
    Map<String, Object?>? config,
  }) {
    return WallpaperData(
      visible: visible ?? this.visible,
      isPreview: isPreview ?? this.isPreview,
      target: target ?? this.target,
      pageOffset: pageOffset ?? this.pageOffset,
      pageStep: pageStep ?? this.pageStep,
      zoom: zoom ?? this.zoom,
      config: config ?? this.config,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WallpaperData &&
      other.visible == visible &&
      other.isPreview == isPreview &&
      other.target == target &&
      other.pageOffset == pageOffset &&
      other.pageStep == pageStep &&
      other.zoom == zoom &&
      jsonValueEquals(other.config, config);

  @override
  int get hashCode =>
      Object.hash(visible, isPreview, target, pageOffset, pageStep, zoom);

  @override
  String toString() =>
      'WallpaperData(visible: $visible, isPreview: $isPreview, '
      'target: ${target.name}, pageOffset: (${pageOffset.dx}, '
      '${pageOffset.dy}), pageStep: (${pageStep.dx}, ${pageStep.dy}), '
      'zoom: $zoom${config.isEmpty ? '' : ', config: $config'})';
}
