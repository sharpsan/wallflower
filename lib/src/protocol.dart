/// The method channel protocol between a wallpaper engine and its Dart
/// isolate.
///
/// Keep in sync with `WallpaperProtocol.kt`. Bump [protocolVersion] on any
/// incompatible change.
///
/// Flow:
/// 1. Dart calls [ProtocolMethod.ready] with its [protocolVersion].
/// 2. Native replies with a full snapshot (every state key, plus
///    [ProtocolKey.protocol] and [ProtocolKey.engineId]).
/// 3. Native then pushes partial [ProtocolMethod.update] maps, at most one per
///    frame, and [ProtocolMethod.command] and [ProtocolMethod.message] maps as
///    they happen.
/// 4. Dart can call [ProtocolMethod.tilt], [ProtocolMethod.colors] and
///    [ProtocolMethod.send].
library;

import 'dart:convert';
import 'dart:ui' show Offset;

import 'wallpaper/commands.dart';
import 'wallpaper/wallpaper_data.dart';

/// The protocol version this Dart code speaks.
const int protocolVersion = 1;

/// The channel each wallpaper engine registers on its own messenger.
const String wallpaperChannelName = 'wallflower/wallpaper';

/// Method names.
abstract final class ProtocolMethod {
  /// Dart to native: start receiving state. Returns a snapshot.
  static const String ready = 'ready';

  /// Dart to native: start or stop tilt samples. Returns whether the device
  /// has a tilt sensor.
  static const String tilt = 'tilt';

  /// Dart to native: colors for `onComputeColors`.
  static const String colors = 'colors';

  /// Dart to native: a message to the app. Returns how many app engines got
  /// it.
  static const String send = 'send';

  /// Native to Dart: a partial state map.
  static const String update = 'update';

  /// Native to Dart: a wallpaper command.
  static const String command = 'command';

  /// Native to Dart: a message from the app.
  static const String message = 'message';
}

/// Map keys.
abstract final class ProtocolKey {
  static const String protocol = 'protocol';
  static const String engineId = 'engineId';
  static const String preview = 'preview';
  static const String visible = 'visible';
  static const String offset = 'offset';
  static const String offsetStep = 'offsetStep';
  static const String zoom = 'zoom';
  static const String target = 'target';
  static const String config = 'config';
  static const String tilt = 'tilt';
  static const String enabled = 'enabled';
  static const String samplingPeriod = 'samplingPeriodUs';
  static const String primary = 'primary';
  static const String secondary = 'secondary';
  static const String tertiary = 'tertiary';
  static const String hints = 'hints';
  static const String name = 'name';
  static const String data = 'data';
  static const String action = 'action';
  static const String x = 'x';
  static const String y = 'y';
  static const String z = 'z';
  static const String extras = 'extras';
}

/// Returns [data] with the fields present in [update] replaced. Used for both
/// the snapshot and partial updates; unknown keys are ignored.
WallpaperData applyUpdate(WallpaperData data, Map<Object?, Object?> update) {
  return data.copyWith(
    visible: _bool(update[ProtocolKey.visible]),
    isPreview: _bool(update[ProtocolKey.preview]),
    target: update.containsKey(ProtocolKey.target)
        ? WallpaperTarget.fromFlags(_int(update[ProtocolKey.target]))
        : null,
    pageOffset: _offset(update[ProtocolKey.offset]),
    pageStep: _offset(update[ProtocolKey.offsetStep]),
    zoom: _double(update[ProtocolKey.zoom]),
    config: update.containsKey(ProtocolKey.config)
        ? decodeConfig(update[ProtocolKey.config])
        : null,
  );
}

/// Decodes a config JSON string. Null, malformed JSON and non-objects decode
/// to an empty map.
Map<String, Object?> decodeConfig(Object? json) {
  if (json is! String) return const {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, Object?>) return Map.unmodifiable(decoded);
  } on FormatException {
    // Fall through.
  }
  return const {};
}

/// Decodes the tilt sample in [update], if any: the up direction on the
/// screen axes and the display rotation, in quarter turns, it was mapped with.
({Offset up, int quarterTurns})? decodeTilt(Map<Object?, Object?> update) {
  final value = update[ProtocolKey.tilt];
  if (value is! List || value.length < 2) return null;
  final up = _offset(value.sublist(0, 2));
  if (up == null) return null;
  final turns = value.length > 2 ? value[2] : null;
  return (up: up, quarterTurns: turns is int ? turns : 0);
}

/// Decodes a command map. Native sends physical pixels; [devicePixelRatio]
/// converts them to logical pixels.
WallpaperCommand decodeCommand(
  Map<Object?, Object?> map, {
  required double devicePixelRatio,
}) {
  final ratio = devicePixelRatio > 0 ? devicePixelRatio : 1.0;
  final x = _double(map[ProtocolKey.x]) ?? 0;
  final y = _double(map[ProtocolKey.y]) ?? 0;
  final extras = <String, Object?>{};
  final rawExtras = map[ProtocolKey.extras];
  if (rawExtras is Map) {
    for (final entry in rawExtras.entries) {
      if (entry.key is String) extras[entry.key as String] = entry.value;
    }
  }
  return WallpaperCommand(
    action: map[ProtocolKey.action] as String? ?? '',
    position: Offset(x / ratio, y / ratio),
    z: _int(map[ProtocolKey.z]) ?? 0,
    extras: Map.unmodifiable(extras),
  );
}

bool? _bool(Object? value) => value is bool ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;

Offset? _offset(Object? value) {
  if (value is List && value.length == 2) {
    final x = _double(value[0]);
    final y = _double(value[1]);
    if (x != null && y != null) return Offset(x, y);
  }
  return null;
}
