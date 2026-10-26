## 0.1.0

First release: Android live wallpapers built from Flutter widgets.

* `FlutterWallpaperService` runs a Dart entrypoint (`wallflower.entrypoint` meta-data, default
  `wallpaperMain`) in a Flutter engine that renders into the live wallpaper surface. Engines come
  from a shared engine group, and a failing engine draws a fallback color instead of crashing the
  wallpaper process.
* `runWallpaper` and `Wallpaper`: visibility, picker preview, home or lock screen target, page
  offsets, launcher zoom and config, through `Wallpaper.of` and per-value methods such as
  `pageOffsetOf` that rebuild only when their own value changes. `WallpaperScope` previews and
  tests scenes.
* Launcher commands: `Wallpaper.commands` and `WallpaperCommand`. Touches arrive as ordinary
  pointer events.
* Device tilt: `WallpaperTilt` and `WallpaperTiltSettings`, smoothed and re-centering, including
  when the display rotates. The sensor runs only while the wallpaper is visible and something
  reads tilt, and drops to 10 samples a second while the phone rests.
* Material You: `Wallpaper.reportColors`.
* App side: `LiveWallpaper.isActive` and `openPicker`, a persisted config pushed to running
  wallpapers (`getConfig`, `setConfig`, `Wallpaper.configOf`), and messages in both directions
  (`LiveWallpaper.send` and `messages`, `Wallpaper.messages` and `sendToApp`).
* Hidden wallpapers draw no frames. System bar padding, display cutouts and rounded corners reach
  `MediaQuery`, and memory pressure and configuration changes (dark mode, font scale, locale) are
  forwarded.
* Example: a wallpaper with parallax, particles and clock scenes, and a settings app that switches
  them live.
