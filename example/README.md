# wallflower example

A live wallpaper with three scenes, and a settings app that switches them while the wallpaper
runs.

- **Parallax**: layered mountain ridges that move with home screen swipes and device tilt.
- **Particles**: a field of particles that ripples where you tap, then settles.
- **Clock**: a minimal clock that keeps clear of the status bar and sets the system's Material You
  colors.

Run it with `flutter run`, then tap **Set** to open the system wallpaper picker.

## Where things are

| File | What it shows |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | The `FlutterWallpaperService` declaration and its `wallflower.entrypoint` meta-data. |
| `android/app/src/main/res/xml/wallpaper.xml` | The picker's description, thumbnail and settings button. |
| `lib/main.dart` | Both entrypoints. `wallpaperMain` runs the wallpaper; it reads the app's config, reports colors and answers messages. |
| `lib/settings_app.dart` | `LiveWallpaper.setConfig`, `openPicker`, `isActive` and `send`, and a `WallpaperScope` preview you can swipe and tap. |
| `lib/scenes/parallax_scene.dart` | Layers translated by page offset and tilt, each painted once and reused. |
| `lib/scenes/particles_scene.dart` | Tap commands paired with pointer events, and springs that stop the ticker once at rest. |
| `lib/scenes/clock_scene.dart` | A timer that runs only while the wallpaper is visible, and `SafeArea`. |
| `test/widget_test.dart` | Driving scenes with a `WallpaperScope`, and checking that each one stops drawing frames. |
