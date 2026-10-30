# Getting started

This guide turns a new Flutter app into a live wallpaper: a dusk sky whose sun drifts as you swipe
between home screen pages. You need a device or emulator with Android 7.0 (API 24) or later.

## 1. Create the app

```sh
flutter create --platforms=android drifting_sky
cd drifting_sky
flutter pub add wallflower
```

## 2. Declare the wallpaper service

Android runs live wallpapers as a `WallpaperService`. wallflower's `FlutterWallpaperService` runs
a Dart function from your app in a Flutter engine of its own and draws it as the wallpaper.

In `android/app/src/main/AndroidManifest.xml`, add `<uses-feature>` inside `<manifest>`, and
`<service>` inside `<application>`, after the `<activity>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-feature android:name="android.software.live_wallpaper" android:required="false" />

    <application ...>
        <activity android:name=".MainActivity" ...>
            ...
        </activity>

        <service
            android:name="app.sharpsan.wallflower.FlutterWallpaperService"
            android:label="@string/wallpaper_label"
            android:permission="android.permission.BIND_WALLPAPER"
            android:exported="true">
            <intent-filter>
                <action android:name="android.service.wallpaper.WallpaperService" />
            </intent-filter>
            <meta-data android:name="android.service.wallpaper" android:resource="@xml/wallpaper" />
            <meta-data android:name="wallflower.entrypoint" android:value="wallpaperMain" />
        </service>
    </application>
</manifest>
```

- `BIND_WALLPAPER` lets only the system start the wallpaper.
- `android.service.wallpaper` points to the wallpaper's description for the picker (step 3).
- `wallflower.entrypoint` names the Dart function the wallpaper runs (step 4).
- `required="false"` keeps the app installable on devices without live wallpapers.

## 3. Describe the wallpaper

Create `android/app/src/main/res/xml/wallpaper.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<wallpaper xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/wallpaper_description"
    android:thumbnail="@mipmap/ic_launcher" />
```

and `android/app/src/main/res/values/strings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="wallpaper_label">Drifting sky</string>
    <string name="wallpaper_description">A dusk sky that drifts as you swipe between home screens.</string>
</resources>
```

The picker shows the label, description and thumbnail. The app icon will do as a thumbnail for
now; later, point `android:thumbnail` at a screenshot in `res/drawable-nodpi/`.

## 4. Write the wallpaper

Replace `lib/main.dart` with:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:wallflower/wallflower.dart';

/// The app: one screen with a button that sets the wallpaper.
void main() => runApp(const MyApp());

/// The wallpaper. Its name matches the `wallflower.entrypoint` meta-data.
@pragma('vm:entry-point')
void wallpaperMain() => runWallpaper(const DriftingSky());

class DriftingSky extends StatelessWidget {
  const DriftingSky({super.key});

  @override
  Widget build(BuildContext context) {
    // 0 on the first home screen page, 1 on the last.
    final page = Wallpaper.pageOffsetOf(context).dx;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2340), Color(0xFFE8876B)],
        ),
      ),
      // The sun crosses part of the sky from the first page to the last.
      child: Align(
        alignment: Alignment(0.6 - 1.2 * page, 0.3),
        child: const SizedBox.square(
          dimension: 120,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFFFD27F),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Drifting sky')),
        body: const Center(
          child: FilledButton(
            onPressed: LiveWallpaper.openPicker,
            child: Text('Set as wallpaper'),
          ),
        ),
      ),
    );
  }
}
```

`main` runs the app as usual. `wallpaperMain` runs in the wallpaper's own engine and Dart isolate
while the wallpaper is applied, even when the app isn't open. No Dart code calls it, so
`@pragma('vm:entry-point')` keeps release builds from removing it.

`runWallpaper` works like `runApp`, and `Wallpaper.pageOffsetOf` reads the page offset the way
`MediaQuery.sizeOf` reads the screen size.

## 5. Run it

```sh
flutter run
```

Tap **Set as wallpaper** and apply the wallpaper in Android's preview, choosing the home screen or
both screens if asked. Then swipe between home screen pages: the sun drifts.

Debug builds take a few seconds to show the wallpaper, because the engine compiles Dart code as it
starts. Profile and release builds show it at once; apply the wallpaper again after running one:

```sh
flutter run --release
```

If the sun stays put, the launcher may not scroll the wallpaper; look for a wallpaper scrolling
option in its settings.

## 6. Work on the scene

The wallpaper runs the installed code, so it picks up changes when you reinstall the app. But
`flutter run` force-stops the app as it starts and when you quit with `q`, and Android removes the
live wallpaper of a force-stopped app. Apply the wallpaper again after each `flutter run`, and
press `d` to detach instead of quitting. Updates installed with `adb install -r` keep it applied.

For faster changes, run the scene on its own, with hot reload. Add `lib/scene_dev.dart`:

```dart
// lib/scene_dev.dart
import 'package:wallflower/wallflower.dart';

import 'main.dart';

void main() => runWallpaper(const DriftingSky());
```

The wallpaper looks for `wallpaperMain` in the file `flutter run` builds, so while a build of
`scene_dev.dart` is installed, it can't find it. Name the file that declares it, in the manifest's
`<service>` element:

```xml
<meta-data android:name="wallflower.entrypointLibrary" android:value="package:drifting_sky/main.dart" />
```

Then run `flutter run -t lib/scene_dev.dart`. Outside a wallpaper, `runWallpaper` shows the scene
full screen as if visible, with every other value at its default. To try other values, such as
another page, use a `WallpaperScope`; see [Testing and previews](testing.md#previews-in-the-app).

To see the wallpaper's logs, including `print` and `debugPrint` output:

```sh
adb logcat -s flutter Wallflower
```

If the wallpaper stays black, check the log. Usually the entrypoint's name doesn't match the
meta-data, or `@pragma('vm:entry-point')` is missing.

## Next

- [Writing scenes](scenes.md): page offsets, launcher zoom, visibility and battery, the lock
  screen, and colors for Material You.
- [Motion and touch](motion-and-touch.md): device tilt, taps and launcher commands.
- [The app and the wallpaper](app-and-wallpaper.md): settings, messages, and several wallpapers in
  one app.
- [Testing and previews](testing.md): driving scenes in widget tests and showing them in the app.
