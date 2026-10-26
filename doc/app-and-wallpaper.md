# The app and the wallpaper

Your app and its wallpaper run the same Dart code, but in separate Flutter engines and Dart
isolates, and the wallpaper keeps running while the app is closed. They share no Dart state: a
static field set in the app isn't set in the wallpaper. They exchange data in two ways:

- **The config** holds settings. It's saved on the device, the wallpaper reads it as soon as it
  starts, and changes reach a running wallpaper immediately.
- **Messages** are one-off events, delivered to whatever is running at that moment.

This guide also covers setting the wallpaper from the app, and offering several wallpapers from
one app.

## Settings: the config

Describe the settings in a class both sides share:

```dart
/// The wallpaper's settings, saved by the app and read by the wallpaper.
class SkyConfig {
  const SkyConfig({this.night = false, this.speed = 1});

  /// Reads a saved config. A saved config outlives app updates, so treat
  /// every field as optional.
  factory SkyConfig.fromJson(Map<String, Object?> json) => SkyConfig(
    night: json['night'] == true,
    speed: switch (json['speed']) {
      final num speed => speed.toDouble(),
      _ => 1.0,
    },
  );

  final bool night;
  final double speed;

  Map<String, Object?> toJson() => {'night': night, 'speed': speed};
}
```

The app reads the config with `LiveWallpaper.getConfig()` and replaces it with
`LiveWallpaper.setConfig()`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallflower/wallflower.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SkyConfig? _config;

  @override
  void initState() {
    super.initState();
    LiveWallpaper.getConfig().then((json) {
      if (mounted) setState(() => _config = SkyConfig.fromJson(json));
    });
  }

  void _save(SkyConfig config) {
    setState(() => _config = config);
    // Saved on the device and sent to the running wallpaper.
    unawaited(LiveWallpaper.setConfig(config.toJson()));
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) return const SizedBox.shrink();
    return SwitchListTile(
      title: const Text('Night sky'),
      value: config.night,
      onChanged: (night) => _save(SkyConfig(night: night, speed: config.speed)),
    );
  }
}
```

The wallpaper reads it with `Wallpaper.configOf(context)`, which rebuilds the widget when the app
saves a new config:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

class Sky extends StatelessWidget {
  const Sky({super.key});

  @override
  Widget build(BuildContext context) {
    final config = SkyConfig.fromJson(Wallpaper.configOf(context));
    return ColoredBox(
      color: config.night ? const Color(0xFF101830) : const Color(0xFF9BC4E2),
    );
  }
}
```

A config is a map of JSON values: null, bools, numbers, strings, lists and maps with string keys.
`setConfig` replaces the whole map, and an empty map clears it. Each save reaches the wallpaper,
so for a slider, save in `onChangeEnd` rather than on every change.

To show the scene in the app with the config being edited, see
[Testing and previews](testing.md#previews-in-the-app).

## Messages

`LiveWallpaper.send` sends a message from the app to the running wallpaper, which receives it on
`Wallpaper.messages`. `Wallpaper.sendToApp` sends one back, and the app receives it on
`LiveWallpaper.messages`. Both sends return how many receivers got the message: 0 when nothing is
running on the other side.

Here the app asks the wallpaper which sky it shows. On the wallpaper side:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

/// Answers the app's 'status' messages.
class StatusResponder extends StatefulWidget {
  const StatusResponder({super.key, required this.child});

  final Widget child;

  @override
  State<StatusResponder> createState() => _StatusResponderState();
}

class _StatusResponderState extends State<StatusResponder> {
  late final StreamSubscription<WallpaperMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = Wallpaper.messages.listen((message) {
      if (message.name != 'status') return;
      final config = SkyConfig.fromJson(Wallpaper.data.value.config);
      unawaited(
        Wallpaper.sendToApp('status', data: config.night ? 'night' : 'day'),
      );
    });
  }

  @override
  void dispose() {
    _messages.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

And in the app:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallflower/wallflower.dart';

class WallpaperStatus extends StatefulWidget {
  const WallpaperStatus({super.key});

  @override
  State<WallpaperStatus> createState() => _WallpaperStatusState();
}

class _WallpaperStatusState extends State<WallpaperStatus> {
  late final StreamSubscription<WallpaperMessage> _replies;
  String _status = 'Not checked yet';

  @override
  void initState() {
    super.initState();
    _replies = LiveWallpaper.messages.listen((message) {
      if (message.name == 'status') {
        setState(() => _status = 'Showing the ${message.data} sky');
      }
    });
  }

  @override
  void dispose() {
    _replies.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    // Running wallpapers answer on LiveWallpaper.messages.
    final reached = await LiveWallpaper.send('status');
    if (mounted && reached == 0) setState(() => _status = 'Not running');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(_status),
      trailing: TextButton(onPressed: _check, child: const Text('Check')),
    );
  }
}
```

Message data takes the same JSON values as a config. Messages aren't stored: a message sent while
nothing is running on the other side is dropped. Use the config for anything the wallpaper needs
when it starts.

## Setting the wallpaper from the app

`LiveWallpaper.openPicker()` opens the system's preview of the wallpaper, where the user applies
it. Where there's no such preview, it opens the list of live wallpapers instead, and it returns
false if the device has neither.
`LiveWallpaper.isActive()` says whether the wallpaper is applied, to the home screen or the lock
screen. Check again when the user comes back from the picker:

```dart
import 'package:flutter/material.dart';
import 'package:wallflower/wallflower.dart';

class SetWallpaperTile extends StatefulWidget {
  const SetWallpaperTile({super.key});

  @override
  State<SetWallpaperTile> createState() => _SetWallpaperTileState();
}

class _SetWallpaperTileState extends State<SetWallpaperTile> {
  late final AppLifecycleListener _lifecycle;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    // The app resumes when the user comes back from the picker.
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final active = await LiveWallpaper.isActive();
    if (mounted) setState(() => _active = active);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(_active ? 'Your wallpaper is set' : 'Not your wallpaper yet'),
      trailing: FilledButton(
        onPressed: LiveWallpaper.openPicker,
        child: Text(_active ? 'Change' : 'Set'),
      ),
    );
  }
}
```

To put a settings button in the wallpaper picker, name an activity in `res/xml/wallpaper.xml`.
The app's `MainActivity` works:

```xml
<wallpaper xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/wallpaper_description"
    android:thumbnail="@mipmap/ic_launcher"
    android:settingsActivity="com.example.drifting_sky.MainActivity" />
```

## Several wallpapers in one app

Each wallpaper in the picker is its own service. Add an empty subclass of
`FlutterWallpaperService` for each, in
`android/app/src/main/kotlin/com/example/drifting_sky/Wallpapers.kt`:

```kotlin
package com.example.drifting_sky

import app.sharpsan.wallflower.FlutterWallpaperService

class SkyWallpaperService : FlutterWallpaperService()

class OceanWallpaperService : FlutterWallpaperService()
```

Declare each one in `AndroidManifest.xml`, with its own label, description and entrypoint:

```xml
<service
    android:name=".SkyWallpaperService"
    android:label="@string/sky_label"
    android:permission="android.permission.BIND_WALLPAPER"
    android:exported="true">
    <intent-filter>
        <action android:name="android.service.wallpaper.WallpaperService" />
    </intent-filter>
    <meta-data android:name="android.service.wallpaper" android:resource="@xml/sky_wallpaper" />
    <meta-data android:name="wallflower.entrypoint" android:value="skyMain" />
</service>

<service
    android:name=".OceanWallpaperService"
    android:label="@string/ocean_label"
    android:permission="android.permission.BIND_WALLPAPER"
    android:exported="true">
    <intent-filter>
        <action android:name="android.service.wallpaper.WallpaperService" />
    </intent-filter>
    <meta-data android:name="android.service.wallpaper" android:resource="@xml/ocean_wallpaper" />
    <meta-data android:name="wallflower.entrypoint" android:value="oceanMain" />
</service>
```

Add an entrypoint for each in `lib/main.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

@pragma('vm:entry-point')
void skyMain() => runWallpaper(const Sky());

@pragma('vm:entry-point')
void oceanMain() => runWallpaper(const ColoredBox(color: Color(0xFF0E4D64)));
```

In the app, pass `service:` to `LiveWallpaper` to pick one, by its simple or fully qualified class
name:

```dart
import 'package:wallflower/wallflower.dart';

Future<void> setUpOcean() async {
  await LiveWallpaper.setConfig({'waves': 3}, service: 'OceanWallpaperService');
  await LiveWallpaper.openPicker(service: 'OceanWallpaperService');
}
```

Each service has its own config. Without `service:`, `setConfig`, `send` and `isActive` apply to
all of the app's wallpapers, and `getConfig` and `openPicker` use the first one.

A subclass can also override `getFallbackColor()`, the color drawn if the Flutter engine fails to
start, which is black by default.

### Entrypoints in another file

Entrypoints are looked up in the app's main library unless the service says otherwise. To keep
them in another file, add its URI as meta-data, and import that file from `lib/main.dart` so it's
part of the app:

```xml
<meta-data android:name="wallflower.entrypointLibrary" android:value="package:drifting_sky/wallpapers.dart" />
```
