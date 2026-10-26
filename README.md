# wallflower: Flutter live wallpapers for Android

Build an Android live wallpaper from ordinary Flutter widgets: animated scenes, parallax that
follows home screen swipes and device tilt, and tap effects.

![A layered mountain wallpaper on an Android home screen, shifting with parallax as the pages change](https://raw.githubusercontent.com/sharpsan/wallflower/main/doc/screenshots/parallax.webp)

Other wallpaper packages set a static image, a video wallpaper or a shader as the wallpaper.
wallflower runs your widget tree *as* the live wallpaper: Android's `WallpaperService` starts a
Flutter engine that renders straight into the home screen and lock screen wallpaper surface, so an
animated wallpaper is just a widget.

## Features

- **Any widget tree as the wallpaper**, rendered by Impeller on Vulkan or OpenGL ES.
- **Parallax** from home screen page offsets and from **device tilt**. Tilt is smoothed and
  re-centers by itself, and the motion sensor runs only while the wallpaper is visible and a widget
  reads it.
- **Taps and launcher zoom**: touches arrive as ordinary pointer events, launcher commands (such
  as a tap on empty home screen space) as a stream, and the app drawer's zoom as a value.
- **Settings from your app**: a persisted config that the running wallpaper sees immediately, and
  messages in both directions.
- **Material You**: report the scene's colors, and the system theme and status bar follow them.
- **Home screen, lock screen or both**, and the system picker's preview. Each running wallpaper
  gets its own isolate.
- **`SafeArea` and `MediaQuery` work**: status bar and navigation bar padding, display cutouts and
  rounded corners are reported.
- **Battery-aware**: no frames while the wallpaper is hidden, and no tilt sampling unless asked.
- **Fails safe**: if the Flutter engine can't start, the wallpaper draws a solid color instead of
  crashing, so Android doesn't reset the user's wallpaper.

## Setup

Add the package:

```sh
flutter pub add wallflower
```

**1. Declare the wallpaper service** in `android/app/src/main/AndroidManifest.xml`, inside
`<application>`:

```xml
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
```

Also add `<uses-feature android:name="android.software.live_wallpaper" android:required="false" />`
inside `<manifest>`, so the app still installs on devices without live wallpaper support.

**2. Describe the wallpaper** for the system picker in `android/app/src/main/res/xml/wallpaper.xml`:

```xml
<wallpaper xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/wallpaper_description"
    android:thumbnail="@drawable/wallpaper_thumbnail"
    android:settingsActivity="com.example.my_app.MainActivity" />
```

Define `wallpaper_label` and `wallpaper_description` in `res/values/strings.xml`. The optional
`settingsActivity` puts a settings button in the picker; the activity must be exported, which the
app's `MainActivity` already is.

**3. Add the Dart entrypoint**, next to `main` in `lib/main.dart`:

```dart
import 'package:wallflower/wallflower.dart';

@pragma('vm:entry-point')
void wallpaperMain() => runWallpaper(const MyScene());
```

`@pragma('vm:entry-point')` keeps the function in release builds, and its name must match the
`wallflower.entrypoint` meta-data. To put the entrypoint in another file, also set the
`wallflower.entrypointLibrary` meta-data to that library's URI, such as
`package:my_app/wallpaper.dart`, and make sure the app imports it.

**4. Let users set it.** `LiveWallpaper.openPicker()` opens the system's preview of the wallpaper,
where the user applies it. Users can also find it in their wallpaper settings.

## Guides

Step by step, with complete code:

- [Getting started](https://github.com/sharpsan/wallflower/blob/main/doc/getting-started.md):
  from `flutter create` to a wallpaper on your home screen.
- [Writing scenes](https://github.com/sharpsan/wallflower/blob/main/doc/scenes.md): parallax,
  launcher zoom, visibility and battery, the lock screen, and Material You colors.
- [Motion and touch](https://github.com/sharpsan/wallflower/blob/main/doc/motion-and-touch.md):
  device tilt, taps and launcher commands.
- [The app and the wallpaper](https://github.com/sharpsan/wallflower/blob/main/doc/app-and-wallpaper.md):
  settings, messages, and several wallpapers in one app.
- [Testing and previews](https://github.com/sharpsan/wallflower/blob/main/doc/testing.md): widget
  tests, and showing a scene inside your app.

The rest of this page is a quick reference.

## Usage

### The scene

`runWallpaper` runs a widget the way `runApp` does. There's no `MaterialApp` above it, so add one
inside the scene if it needs Material widgets or themes.

```dart
class MyScene extends StatelessWidget {
  const MyScene({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when the home screen page changes.
    final page = Wallpaper.pageOffsetOf(context).dx; // 0 on the first page, 1 on the last
    return Transform.translate(
      offset: Offset((0.5 - page) * 80, 0),
      child: const MyLayers(),
    );
  }
}
```

`Wallpaper.of(context)` returns everything as a `WallpaperData`:

| Field | Meaning |
|---|---|
| `visible` | Whether the wallpaper is on screen. Frames stop while it's hidden. |
| `isPreview` | Whether this is the system picker's preview rather than the applied wallpaper. |
| `target` | Home screen, lock screen or both (Android 14+; `unknown` before). |
| `pageOffset`, `pageStep`, `pageCount` | The launcher's scroll position across home screen pages. |
| `zoom` | 0 normally, toward 1 as the launcher zooms out for the app drawer or recents. |
| `config` | The settings the app saved with `LiveWallpaper.setConfig`. |

`Wallpaper.visibleOf`, `pageOffsetOf`, `zoomOf`, `configOf` and the other `...Of` methods rebuild
a widget only when that one value changes, like `MediaQuery.sizeOf`.

### Tilt

```dart
final tilt = WallpaperTilt.of(context); // Offset, each axis -1..1
```

The value measures how far the phone has tilted from the way it's being held, and drifts back to
zero when the phone settles at a new angle. `WallpaperTilt.settings` sets the sampling rate,
smoothing, re-centering speed and range.

The motion sensor runs while the wallpaper is visible and at least one mounted widget has read
`WallpaperTilt.of`. A widget counts until it unmounts, even if it stops reading, so put the read in
its own small widget and leave that widget out when a scene doesn't need tilt. Outside the widget
tree, listeners on `WallpaperTilt.listenable` count instead.

### Taps

Touches on the wallpaper arrive as ordinary pointer events, so `GestureDetector` and `Listener`
work. Launchers also send commands on `Wallpaper.commands`, such as `WallpaperCommand.tap` for a
tap on empty home screen space (not on an icon, and not a swipe). Command coordinates come from
the launcher and can be a few percent off, so for precise positions pair a command with the
pointer event from the same tap.

### Settings and messages from your app

```dart
// In the app:
await LiveWallpaper.setConfig({'scene': 'aurora', 'speed': 2}); // persisted, pushed live
await LiveWallpaper.send('celebrate');                          // one-off message
LiveWallpaper.messages.listen((message) => debugPrint(message.name));

// In the wallpaper:
final config = Wallpaper.configOf(context); // {'scene': 'aurora', 'speed': 2}
Wallpaper.messages.listen((message) { /* 'celebrate' */ });
await Wallpaper.sendToApp('done', data: {'frames': 120});
```

Configs are JSON-compatible maps, saved on the device and delivered to running wallpapers at
once. Messages are delivered only to wallpapers and app screens that are running at that moment.

`LiveWallpaper` also has `isActive()` and `openPicker()`. Every method takes an optional `service:`
for apps that offer several wallpapers, each as its own `FlutterWallpaperService` subclass.

### Material You colors

```dart
await Wallpaper.reportColors(
  const Color(0xFFE8876B),
  secondary: const Color(0xFF1B2340),
  supportsDarkTheme: true,
);
```

Android derives the system theme from these colors when the user's theme follows the wallpaper.
With `supportsDarkText`, the status bar and Pixel Launcher switch to dark text and icons over a
light wallpaper. Report only when the colors change: each report makes the system recompute its
theme.

### Previews and tests

`WallpaperScope` provides wallpaper state to a subtree. Use it to show a scene inside your app,
or to drive one in widget tests:

```dart
final data = ValueNotifier(const WallpaperData(visible: true, pageStep: Offset(0.25, 0)));

WallpaperScope(data: data, child: const MyScene());

data.value = data.value.copyWith(pageOffset: const Offset(0.5, 0)); // "swipe" to page 3
```

Called from an ordinary app, `runWallpaper` runs the scene full screen as if visible, which is
handy while developing it.

## Limitations

- Android only. iOS has no live wallpaper API.
- The wallpaper runs in the app's process, in its own Dart isolate, so it shares no Dart state
  with the app. Use the config and messages instead.
- Plugins are registered in the wallpaper's engine too, but plugins that need an `Activity` won't
  get one.
- No platform views, text input or accessibility semantics inside the wallpaper.
- Each running engine costs memory, mostly GPU buffers for the full-screen surface. With a simple
  animated scene on a Pixel 10 Pro, the process used about 185 MB (PSS) with one engine, about
  100 MB of it graphics memory, and about 75 MB more while the picker preview was open.
- Memory isn't fully returned when an engine shuts down: about half a megabyte of native memory
  per engine, inside Flutter itself. It adds up only when the picker preview is opened many times
  without the process restarting.

## Battery

A live wallpaper is on screen whenever the home screen is, so its cost adds up.

- **The engine draws nothing while the wallpaper is hidden**, but Dart timers and streams keep
  running. Pause timer-driven work when `Wallpaper.visibleOf(context)` is false.
- **Prefer animations that settle.** A scene that changes only on swipes, tilt or taps draws no
  frames in between. On a Pixel 10 Pro, a static scene used 0.1% of a CPU core while visible, and
  a simple gradient animating at 60 fps used about a third of a core.
- **Read tilt only when you use it.** The sensor runs only while the wallpaper is visible and
  something reads tilt. While the phone lies still, the sensor drops to 10 samples a second; on a
  Pixel 10 Pro, a static scene reading tilt then used under 1% of a CPU core.
- **Report colors only on changes**, since each report re-themes the system.

## Troubleshooting

- **The wallpaper stays black.** Check logcat for the tag `Wallflower`. A warning appears if no
  frame arrives within 5 seconds of the wallpaper becoming visible. Usually the entrypoint name
  doesn't match the meta-data, the function lacks `@pragma('vm:entry-point')`, or it doesn't call
  `runWallpaper`.
- **The first frame is slow.** Debug builds start the wallpaper in JIT mode, which takes seconds.
  Judge startup in profile or release builds: on a Pixel 10 Pro, the first frame appeared 30–110 ms
  after the wallpaper's surface did.
- **The wallpaper reset to the system default.** Android removes a live wallpaper when its app is
  force-stopped, including from the app info screen, or uninstalled, or when it crashes repeatedly.
  Updating the app keeps it.
- **Tilt stays at zero.** Tilt measures movement away from how the phone is held, so it returns to
  zero whenever the phone is still. Devices and emulators without a motion sensor always report
  zero.

## FAQ

**Does it work with Flame or other game engines?** Any widget works, including `GameWidget`. Pause
the game while `Wallpaper.visibleOf(context)` is false, and use `Wallpaper.data` and
`WallpaperTilt.listenable` from game code outside the widget tree.

**Can one app offer several wallpapers?** Yes. Subclass `FlutterWallpaperService` once per
wallpaper, declare each subclass as its own service with its own entrypoint, and pass `service:`
to `LiveWallpaper` methods.

**Can the wallpaper be different on the lock screen?** On Android 14 and later, users can apply a
live wallpaper to the home screen, the lock screen or both, and `Wallpaper.targetOf(context)` says
which.

## Example

[`example/`](https://github.com/sharpsan/wallflower/tree/main/example) is a wallpaper with three scenes and a settings app that switches them
live:

- **Parallax**: layered mountain ridges that move with page swipes and device tilt.
- **Particles**: a field of particles that ripples where you tap, and settles again.
- **Clock**: a minimal clock that keeps clear of the status bar with `SafeArea` and sets the
  system's Material You colors.

The settings app previews each scene in a `WallpaperScope`, with the preview standing in for the
launcher.
