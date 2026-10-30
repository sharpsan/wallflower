# The app and the wallpaper

Your app and its wallpaper run the same Dart code, but in separate Flutter engines and Dart
isolates, and the wallpaper keeps running while the app is closed. They share no Dart state: a
static field set in the app isn't set in the wallpaper. Instead they share:

- **The config**, for settings. It's saved on the device, the wallpaper reads it when it starts,
  and changes reach a running wallpaper immediately.
- **Messages**, for one-off events, delivered to whatever is running at the moment.

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
`setConfig` replaces the whole map, and an empty map clears it. Every save reaches the wallpaper,
so for a slider, save in `onChangeEnd` rather than on every change.

To show the scene in the app with the config being edited, see
[Testing and previews](testing.md#previews-in-the-app).

## Messages

The app sends with `LiveWallpaper.send`, and the wallpaper receives on `Wallpaper.messages`. The
wallpaper replies with `Wallpaper.sendToApp`, and the app receives on `LiveWallpaper.messages`.
Both sends return how many Flutter engines received the message: 0 if nothing is running on the
other side.

Here the app asks the wallpaper which sky it shows. The wallpaper side:

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

The app side:

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

Message data takes the same JSON values as a config. Messages aren't stored, so use the config for
anything the wallpaper needs when it starts.

## Setting the wallpaper from the app

`LiveWallpaper.openPicker()` opens the system's preview of the wallpaper, where the user applies
it. On devices without that preview, it opens the list of live wallpapers instead, and it returns
false if there's neither.

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

To put a settings button in the wallpaper picker, name an exported activity in
`res/xml/wallpaper.xml`, by its full class name. The app's `MainActivity` works:

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

Declare them in `AndroidManifest.xml` in place of the `FlutterWallpaperService` entry, each with
its own label, description and entrypoint:

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

Create the descriptions (`res/xml/sky_wallpaper.xml` and `res/xml/ocean_wallpaper.xml`) and
strings as in [Getting started](getting-started.md#3-describe-the-wallpaper). Then add an
entrypoint for each in `lib/main.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:wallflower/wallflower.dart';

@pragma('vm:entry-point')
void skyMain() => runWallpaper(const Sky());

@pragma('vm:entry-point')
void oceanMain() => runWallpaper(const ColoredBox(color: Color(0xFF0E4D64)));
```

In the app, pass `service:` to `LiveWallpaper` methods to pick one, by simple or fully qualified
class name:

```dart
import 'package:wallflower/wallflower.dart';

Future<void> setUpOcean() async {
  await LiveWallpaper.setConfig({'waves': 3}, service: 'OceanWallpaperService');
  await LiveWallpaper.openPicker(service: 'OceanWallpaperService');
}
```

Each service has its own config. Without `service:`, `setConfig`, `send` and `isActive` apply to
all of the app's wallpapers, and `getConfig` and `openPicker` use the first one. A `service:` that
matches no declared service throws a `PlatformException`.

A subclass can also override `getFallbackColor()`, the color drawn if the Flutter engine fails to
start, which is black by default.

### Entrypoints in another file

Entrypoints are looked up in the file `flutter run` builds, normally `lib/main.dart`. To keep them
in another file, add its URI to the service's meta-data, and import the file from `lib/main.dart`
so it's part of the app:

```xml
<meta-data android:name="wallflower.entrypointLibrary" android:value="package:drifting_sky/wallpapers.dart" />
```
