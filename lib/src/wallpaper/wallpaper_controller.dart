import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../messages.dart';
import '../protocol.dart';
import 'commands.dart';
import 'tilt.dart';
import 'wallpaper_data.dart';

/// Connects this isolate to the native wallpaper engine that spawned it.
///
/// There is one per isolate; `runWallpaper` attaches it, and `Wallpaper`
/// reads from it.
class WallpaperController {
  /// Creates a controller. Tests can pass their own [channel].
  WallpaperController({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(wallpaperChannelName) {
    _data.addListener(() => tilt.setVisible(_data.value.visible));
  }

  static WallpaperController? _instance;

  /// The controller for this isolate.
  static WallpaperController get instance =>
      _instance ??= WallpaperController();

  /// Replaces [instance], for tests. Pass null to reset.
  @visibleForTesting
  static set debugInstance(WallpaperController? controller) {
    _instance?.dispose();
    _instance = controller;
  }

  final MethodChannel _channel;
  final ValueNotifier<WallpaperData> _data = ValueNotifier(
    const WallpaperData(),
  );
  final StreamController<WallpaperCommand> _commands =
      StreamController.broadcast();
  final StreamController<WallpaperMessage> _messages =
      StreamController.broadcast();
  Future<void>? _attaching;
  Map<String, Object?>? _colors;

  /// Tilt values and sensor demand for this isolate.
  late final TiltController tilt = TiltController(
    onDemandChanged: _onTiltDemandChanged,
  );

  /// The current state; updates as the engine reports changes.
  ValueListenable<WallpaperData> get data => _data;

  /// Commands from the launcher or system, such as taps.
  Stream<WallpaperCommand> get commands => _commands.stream;

  /// Messages from the app.
  Stream<WallpaperMessage> get messages => _messages.stream;

  /// The native engine's id, unique within the process. Null until attached.
  int? get engineId => _engineId;
  int? _engineId;

  /// Whether a native wallpaper engine answered [attach].
  bool get isAttached => _engineId != null;

  /// Starts listening to the native engine and fetches its current state.
  ///
  /// Safe to call more than once. When no wallpaper engine is listening, for
  /// example when the scene runs inside an ordinary app during development,
  /// the state stays at its defaults with [WallpaperData.visible] set to true.
  Future<void> attach() => _attaching ??= _attach();

  Future<void> _attach() async {
    _channel.setMethodCallHandler(_onMethodCall);
    try {
      final snapshot = await _channel.invokeMapMethod<Object?, Object?>(
        ProtocolMethod.ready,
        {ProtocolKey.protocol: protocolVersion},
      );
      if (snapshot == null) return;
      final nativeVersion = snapshot[ProtocolKey.protocol];
      if (nativeVersion != protocolVersion) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError(
              'wallflower: the native side speaks protocol $nativeVersion, '
              'Dart speaks $protocolVersion. Rebuild the app.',
            ),
            library: 'wallflower',
          ),
        );
      }
      final id = snapshot[ProtocolKey.engineId];
      _engineId = id is int ? id : -1;
      _data.value = applyUpdate(_data.value, snapshot);
      // Tilt readers and color reports may predate the engine's answer.
      if (tilt.wanted) _onTiltDemandChanged(true, tilt.settings);
      final colors = _colors;
      if (colors != null) {
        await _channel.invokeMethod<void>(ProtocolMethod.colors, colors);
      }
    } on MissingPluginException {
      // Not running in a wallpaper engine. Behave like a visible wallpaper so
      // scenes can be developed inside an ordinary app.
      _data.value = _data.value.copyWith(visible: true);
    }
  }

  /// Sends [name] and [data] to the app. Returns how many app engines got
  /// it; 0 when not running in a wallpaper engine.
  Future<int> sendToApp(String name, Object? data) async {
    if (!isAttached) return 0;
    return await _channel.invokeMethod<int>(ProtocolMethod.send, {
          ProtocolKey.name: name,
          ProtocolKey.data: data,
        }) ??
        0;
  }

  /// Reports the wallpaper's colors to the system. A report made before the
  /// engine answers [attach] is sent once it does.
  Future<void> reportColors({
    required int? primary,
    int? secondary,
    int? tertiary,
    int hints = 0,
  }) async {
    final colors = _colors = {
      ProtocolKey.primary: primary,
      ProtocolKey.secondary: secondary,
      ProtocolKey.tertiary: tertiary,
      ProtocolKey.hints: hints,
    };
    if (!isAttached) return;
    await _channel.invokeMethod<void>(ProtocolMethod.colors, colors);
  }

  void _onTiltDemandChanged(bool wanted, WallpaperTiltSettings settings) {
    if (!isAttached) return;
    unawaited(
      _channel.invokeMethod<bool>(ProtocolMethod.tilt, {
        ProtocolKey.enabled: wanted,
        ProtocolKey.samplingPeriod: settings.samplingPeriod.inMicroseconds,
      }),
    );
  }

  Future<Object?> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case ProtocolMethod.update:
        final update = call.arguments;
        if (update is Map) {
          _data.value = applyUpdate(_data.value, update);
          final sample = decodeTilt(update);
          if (sample != null) {
            tilt.addSample(sample.up, quarterTurns: sample.quarterTurns);
          }
        }
      case ProtocolMethod.command:
        final command = call.arguments;
        if (command is Map) {
          _commands.add(
            decodeCommand(command, devicePixelRatio: _devicePixelRatio()),
          );
        }
      case ProtocolMethod.message:
        final message = call.arguments;
        if (message is Map && message[ProtocolKey.name] is String) {
          _messages.add(
            WallpaperMessage(
              message[ProtocolKey.name] as String,
              message[ProtocolKey.data],
            ),
          );
        }
      default:
        throw MissingPluginException(
          'wallflower: unknown method ${call.method}',
        );
    }
    return null;
  }

  double _devicePixelRatio() =>
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;

  /// Stops listening. Only tests need this.
  @visibleForTesting
  void dispose() {
    _channel.setMethodCallHandler(null);
    _commands.close();
    _messages.close();
    tilt.dispose();
    _data.dispose();
  }
}
