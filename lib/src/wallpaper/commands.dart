import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// A command the launcher or the system sent to the wallpaper, such as a tap
/// on an empty part of the home screen.
///
/// Listen with `Wallpaper.commands`.
///
/// Touches on the wallpaper also arrive as ordinary pointer events, so
/// `GestureDetector` and `Listener` work as usual and report exact positions.
/// Prefer them for anything position-sensitive: launchers compute command
/// coordinates their own way, and on Pixel Launcher they differ from the
/// touch position by several percent.
@immutable
class WallpaperCommand {
  /// Creates a command.
  const WallpaperCommand({
    required this.action,
    this.position = Offset.zero,
    this.z = 0,
    this.extras = const {},
  });

  /// A tap on an empty part of the home screen
  /// (`WallpaperManager.COMMAND_TAP`).
  static const String tap = 'android.wallpaper.tap';

  /// A secondary tap, such as a second finger
  /// (`WallpaperManager.COMMAND_SECONDARY_TAP`).
  static const String secondaryTap = 'android.wallpaper.secondaryTap';

  /// An item dropped on the home screen (`WallpaperManager.COMMAND_DROP`).
  static const String drop = 'android.home.drop';

  /// The device is waking up. Not part of the public Android SDK; Pixel
  /// devices send it, other devices may not.
  static const String wakingUp = 'android.wallpaper.wakingup';

  /// The device is going to sleep. Not part of the public Android SDK; Pixel
  /// devices send it, other devices may not.
  static const String goingToSleep = 'android.wallpaper.goingtosleep';

  /// The command name, such as [tap]. Unknown commands are delivered too.
  final String action;

  /// Where the command happened, in logical pixels, as reported by the
  /// sender. See the class documentation about its accuracy.
  final Offset position;

  /// The command's z value; usually 0.
  final int z;

  /// Extra values sent with the command. Only booleans, numbers and strings
  /// are kept.
  final Map<String, Object?> extras;

  /// Whether this is a [tap] or a [secondaryTap].
  bool get isTap => action == tap || action == secondaryTap;

  @override
  bool operator ==(Object other) =>
      other is WallpaperCommand &&
      other.action == action &&
      other.position == position &&
      other.z == z &&
      mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(
    action,
    position,
    z,
    Object.hashAllUnordered(
      extras.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'WallpaperCommand($action, position: (${position.dx}, ${position.dy})'
      '${z != 0 ? ', z: $z' : ''}${extras.isNotEmpty ? ', extras: $extras' : ''})';
}
