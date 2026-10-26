import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallflower/wallflower.dart';

import 'config.dart';
import 'scenes/scene_view.dart';

/// The demo's settings app, themed from the chosen palette.
class SettingsApp extends StatefulWidget {
  const SettingsApp({super.key});

  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  DemoConfig _config = const DemoConfig();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await LiveWallpaper.getConfig();
    if (mounted) setState(() => _config = DemoConfig.fromJson(saved));
  }

  /// Shows [config] at once; saves it, which also updates the running
  /// wallpaper, unless [save] is false.
  void _update(DemoConfig config, {bool save = true}) {
    setState(() => _config = config);
    if (save) unawaited(LiveWallpaper.setConfig(config.toJson()));
  }

  @override
  Widget build(BuildContext context) {
    final seed = _config.palette.skyBottom;
    return MaterialApp(
      title: 'Wallflower',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: SettingsPage(config: _config, onChanged: _update),
    );
  }
}

/// Scene, colors, intensity and tilt, with a live preview.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final DemoConfig config;
  final void Function(DemoConfig config, {bool save}) onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  late final StreamSubscription<WallpaperMessage> _replies;
  bool? _active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _replies = LiveWallpaper.messages.listen(_onReply);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _replies.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the wallpaper picker, maybe with a new wallpaper.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final active = await LiveWallpaper.isActive();
    if (mounted) setState(() => _active = active);
  }

  Future<void> _checkStatus() async {
    final reached = await LiveWallpaper.send('status');
    if (reached == 0) _showSnackBar('No demo wallpaper is running.');
    // Running wallpapers answer through LiveWallpaper.messages.
  }

  void _onReply(WallpaperMessage message) {
    if (message.name != 'status') return;
    final data = message.data;
    if (data is! Map) return;
    final where = switch (data['target']) {
      'home' => 'the home screen',
      'lock' => 'the lock screen',
      'homeAndLock' => 'the home and lock screens',
      _ => 'an unknown screen',
    };
    final kind = data['preview'] == true ? 'A preview' : 'The wallpaper';
    _showSnackBar('$kind is showing ${data['scene']} on $where.');
  }

  void _showSnackBar(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final preview = Center(child: ScenePreview(config: widget.config));
    final controls = _controls(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Wallflower')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Row(
              children: [
                Expanded(child: preview),
                SizedBox(width: 420, child: ListView(children: controls)),
              ],
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: preview,
              ),
              ...controls,
            ],
          );
        },
      ),
    );
  }

  List<Widget> _controls(BuildContext context) {
    final config = widget.config;
    final theme = Theme.of(context);
    void change(DemoConfig config, {bool save = true}) =>
        widget.onChanged(config, save: save);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card.filled(
          child: ListTile(
            leading: Icon(
              _active == true ? Icons.check_circle : Icons.wallpaper,
              color: theme.colorScheme.primary,
            ),
            title: Text(switch (_active) {
              null => 'Checking your wallpaper…',
              true => 'This is your live wallpaper',
              false => 'Not your wallpaper yet',
            }),
            trailing: FilledButton.tonal(
              onPressed: LiveWallpaper.openPicker,
              child: Text(_active == true ? 'Change' : 'Set'),
            ),
          ),
        ),
      ),
      const _Heading('Scene'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<DemoScene>(
          segments: const [
            ButtonSegment(
              value: DemoScene.parallax,
              icon: Icon(Icons.landscape_outlined),
              label: Text('Parallax'),
            ),
            ButtonSegment(
              value: DemoScene.particles,
              icon: Icon(Icons.grain),
              label: Text('Particles'),
            ),
            ButtonSegment(
              value: DemoScene.clock,
              icon: Icon(Icons.schedule),
              label: Text('Clock'),
            ),
          ],
          selected: {config.scene},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              change(config.copyWith(scene: selection.single)),
        ),
      ),
      const _Heading('Colors'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          children: [
            for (final palette in DemoPalette.values)
              _Swatch(
                palette: palette,
                selected: palette == config.palette,
                onTap: () => change(config.copyWith(palette: palette)),
              ),
          ],
        ),
      ),
      _Heading(switch (config.scene) {
        DemoScene.parallax => 'Depth',
        DemoScene.particles => 'Particles',
        DemoScene.clock => 'Color strength',
      }),
      Slider(
        value: config.intensity,
        // Preview while dragging; save once, when the drag ends.
        onChanged: (value) =>
            change(config.copyWith(intensity: value), save: false),
        onChangeEnd: (value) => change(config.copyWith(intensity: value)),
      ),
      SwitchListTile(
        title: const Text('Follow tilt'),
        subtitle: Text(
          config.scene == DemoScene.clock
              ? 'The clock stays still.'
              : 'Uses the motion sensors while the wallpaper is visible.',
        ),
        value: config.tilt,
        onChanged: config.scene == DemoScene.clock
            ? null
            : (value) => change(config.copyWith(tilt: value)),
      ),
      ListTile(
        title: const Text('Check the running wallpaper'),
        subtitle: const Text('Sends it a message and shows the reply.'),
        trailing: const Icon(Icons.sync_alt),
        onTap: _checkStatus,
      ),
      const SizedBox(height: 16),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final DemoPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: palette.label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: palette.label,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? outline : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.skyTop, palette.skyBottom],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The scene in a phone-shaped frame. Swipe it sideways to change home
/// screen pages and tap it to tap the wallpaper.
///
/// A [WallpaperScope] with made-up [WallpaperData] stands in for the
/// launcher, the same way you'd test a scene.
class ScenePreview extends StatefulWidget {
  const ScenePreview({super.key, required this.config});

  final DemoConfig config;

  @override
  State<ScenePreview> createState() => _ScenePreviewState();
}

class _ScenePreviewState extends State<ScenePreview>
    with SingleTickerProviderStateMixin {
  static const _pages = 5;

  final _data = ValueNotifier(
    const WallpaperData(
      visible: true,
      isPreview: true,
      pageStep: Offset(1 / (_pages - 1), 0),
    ),
  );
  final _taps = StreamController<Offset>.broadcast();
  late final AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController.unbounded(vsync: this)
      ..addListener(() => _setPage(_snap.value));
  }

  double get _page => _data.value.pageOffset.dx;

  void _setPage(double page) => _data.value = _data.value.copyWith(
    pageOffset: Offset(page.clamp(0.0, 1.0), 0),
  );

  @override
  void dispose() {
    _snap.dispose();
    _taps.close();
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    const width = 240.0;
    final scale = width / screen.shortestSide;
    final height = width * screen.longestSide / screen.shortestSide;
    final step = 1 / (_pages - 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapUp: (details) => _taps.add(details.localPosition),
          onHorizontalDragStart: (_) => _snap.stop(),
          onHorizontalDragUpdate: (details) =>
              _setPage(_page - details.delta.dx / width * step),
          onHorizontalDragEnd: (details) {
            // Settle on the nearest page, like a launcher.
            final target = (_page / step).round() * step;
            _snap.value = _page;
            _snap.animateTo(
              target,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          },
          child: Container(
            width: width,
            height: height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 2,
              ),
            ),
            // A scaled-down copy of this phone's status bar padding, so the
            // clock's SafeArea behaves as it will on the home screen.
            child: MediaQuery(
              data: media.copyWith(
                size: Size(width, height),
                padding: EdgeInsets.only(top: media.viewPadding.top * scale),
                viewPadding: EdgeInsets.only(
                  top: media.viewPadding.top * scale,
                ),
              ),
              child: WallpaperScope(
                data: _data,
                child: SceneView(config: widget.config, taps: _taps.stream),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Swipe to change pages · tap to tap',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
