import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallflower/wallflower.dart';

/// Counts its builds and records what it read.
class _Probe extends StatelessWidget {
  const _Probe(this.read, this.builds);

  final Object? Function(BuildContext context) read;
  final List<Object?> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(read(context));
    return const SizedBox();
  }
}

void main() {
  late ValueNotifier<WallpaperData> data;

  setUp(() {
    data = ValueNotifier(const WallpaperData(visible: true));
  });

  tearDown(() => data.dispose());

  Widget scope(List<Widget> children) => WallpaperScope(
    data: data,
    child: Column(children: children),
  );

  testWidgets('aspect readers rebuild only for their own field', (
    tester,
  ) async {
    final visible = <Object?>[];
    final page = <Object?>[];
    final zoom = <Object?>[];
    final all = <Object?>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: scope([
          _Probe(Wallpaper.visibleOf, visible),
          _Probe(Wallpaper.pageOffsetOf, page),
          _Probe(Wallpaper.zoomOf, zoom),
          _Probe(Wallpaper.of, all),
        ]),
      ),
    );

    data.value = data.value.copyWith(pageOffset: const Offset(0.5, 0));
    await tester.pump();
    data.value = data.value.copyWith(pageOffset: const Offset(0.75, 0));
    await tester.pump();
    data.value = data.value.copyWith(zoom: 0.33);
    await tester.pump();
    data.value = data.value.copyWith(visible: false);
    await tester.pump();

    expect(visible, [true, false]);
    expect(page, [Offset.zero, const Offset(0.5, 0), const Offset(0.75, 0)]);
    expect(zoom, [0.0, 0.33]);
    expect(all, hasLength(5));
  });

  testWidgets('configOf rebuilds only when the config changes', (tester) async {
    final configs = <Object?>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: scope([_Probe(Wallpaper.configOf, configs)]),
      ),
    );
    data.value = data.value.copyWith(zoom: 0.5);
    await tester.pump();
    data.value = data.value.copyWith(config: {'scene': 'aurora'});
    await tester.pump();
    // An equal config in a new map doesn't count as a change.
    data.value = data.value.copyWith(config: {'scene': 'aurora'});
    await tester.pump();

    expect(configs, [
      <String, Object?>{},
      {'scene': 'aurora'},
    ]);
  });

  testWidgets('pageStepOf rebuilds when the step changes', (tester) async {
    final steps = <Object?>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: scope([_Probe(Wallpaper.pageStepOf, steps)]),
      ),
    );
    data.value = data.value.copyWith(pageStep: const Offset(1 / 3, 0));
    await tester.pump();

    expect(steps, [Offset.zero, const Offset(1 / 3, 0)]);
  });

  testWidgets('of throws a helpful error without a scope', (tester) async {
    late FlutterError error;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          try {
            Wallpaper.of(context);
          } on FlutterError catch (e) {
            error = e;
          }
          return const SizedBox();
        },
      ),
    );

    expect(error.message, contains('No WallpaperScope found'));
    expect(error.toString(), contains('runWallpaper'));
  });

  testWidgets('maybeOf returns null without a scope', (tester) async {
    WallpaperData? found = const WallpaperData();

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          found = Wallpaper.maybeOf(context);
          return const SizedBox();
        },
      ),
    );

    expect(found, isNull);
  });
}
