import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../messages.dart';

/// Controls this app's live wallpaper from the app itself: whether it's
/// active, opening the system picker, its config, and messages.
///
/// Every method takes an optional `service`, the class name of a
/// `FlutterWallpaperService` subclass declared in the manifest, for apps
/// that offer several wallpapers. Fully qualified (`com.example.Ocean`) and
/// simple (`Ocean`) names both work. Without it, a method applies to all of
/// the app's wallpaper services ([openPicker] and [getConfig] use the first).
///
/// Every method throws a `PlatformException` if the manifest declares no
/// matching wallpaper service.
///
/// Android only. Call these from the app, not from the wallpaper's isolate.
abstract final class LiveWallpaper {
  static const MethodChannel _channel = MethodChannel('wallflower/app');
  static StreamController<WallpaperMessage>? _messages;

  /// Whether one of this app's wallpapers is the current home screen or lock
  /// screen live wallpaper.
  static Future<bool> isActive({String? service}) async =>
      await _channel.invokeMethod<bool>('isActive', {'service': service}) ??
      false;

  /// Opens the system's preview of the live wallpaper, from which the user
  /// can apply it. Falls back to the system's list of live wallpapers.
  ///
  /// Returns false if the device offers neither screen.
  static Future<bool> openPicker({String? service}) async =>
      await _channel.invokeMethod<bool>('openPicker', {'service': service}) ??
      false;

  /// The wallpaper's persisted config, or an empty map if none was set.
  static Future<Map<String, Object?>> getConfig({String? service}) async {
    final json = await _channel.invokeMethod<String>('getConfig', {
      'service': service,
    });
    if (json == null) return const {};
    final decoded = jsonDecode(json);
    return decoded is Map<String, Object?> ? decoded : const {};
  }

  /// Replaces the wallpaper's config and pushes it to running wallpapers,
  /// which see it in `WallpaperData.config`.
  ///
  /// The config is stored on the device and survives restarts, so use it for
  /// settings such as which scene to show. Values must be JSON-encodable:
  /// null, bools, numbers, strings, lists and string-keyed maps. Pass an empty
  /// map to clear it.
  static Future<void> setConfig(
    Map<String, Object?> config, {
    String? service,
  }) {
    return _channel.invokeMethod<void>('setConfig', {
      'service': service,
      'config': config.isEmpty ? null : jsonEncode(config),
    });
  }

  /// Sends a transient message to the running wallpapers, which receive it on
  /// `Wallpaper.messages`.
  ///
  /// [data] can be null, a bool, number or string, or lists and string-keyed
  /// maps of those. Returns how many wallpaper engines received it; 0 if none
  /// is running.
  static Future<int> send(String name, {Object? data, String? service}) async =>
      await _channel.invokeMethod<int>('send', {
        'service': service,
        'name': name,
        'data': data,
      }) ??
      0;

  /// Messages that wallpapers send with `Wallpaper.sendToApp`. A broadcast
  /// stream.
  static Stream<WallpaperMessage> get messages {
    final controller = _messages ??= StreamController.broadcast(
      onListen: () => _channel.setMethodCallHandler(_onMethodCall),
    );
    return controller.stream;
  }

  static Future<Object?> _onMethodCall(MethodCall call) async {
    if (call.method == 'message') {
      final arguments = call.arguments;
      if (arguments is Map && arguments['name'] is String) {
        _messages?.add(
          WallpaperMessage(arguments['name'] as String, arguments['data']),
        );
      }
      return null;
    }
    throw MissingPluginException('wallflower: unknown method ${call.method}');
  }
}
