import 'package:flutter/foundation.dart';

/// A message between the app and its live wallpapers.
///
/// The app sends with `LiveWallpaper.send` and the wallpaper receives on
/// `Wallpaper.messages`; the wallpaper sends with `Wallpaper.sendToApp` and the
/// app receives on `LiveWallpaper.messages`. Messages are transient: one sent
/// while nobody is listening is dropped. Use the wallpaper config for state
/// that must survive restarts.
@immutable
class WallpaperMessage {
  /// Creates a message.
  const WallpaperMessage(this.name, [this.data]);

  /// What the message is about, chosen by the app.
  final String name;

  /// The payload: null, a bool, number or string, or lists and string-keyed
  /// maps of those.
  final Object? data;

  @override
  bool operator ==(Object other) =>
      other is WallpaperMessage &&
      other.name == name &&
      jsonValueEquals(other.data, data);

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() =>
      'WallpaperMessage($name${data == null ? '' : ', $data'})';
}

/// Deep equality for JSON-like values: maps, lists and primitives.
bool jsonValueEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonValueEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonValueEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
