import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/widgets/network_video.dart';
import 'package:night_owl_ub/features/feed/providers/reels_provider.dart';
import 'package:night_owl_ub/features/feed/widgets/explore_reels_section.dart';

final _reels = List.generate(
    3,
    (i) => <String, dynamic>{
          'id': 'clip-$i',
          'user_id': 'author-$i',
          'media_url': 'https://media.test/clip-$i.mp4',
          'caption': 'Бодит газрын богино бичлэг $i',
          'profiles': {'username': 'venue_$i'},
        });

void main() {
  Future<void> render(
      WidgetTester tester, Future<List<Map<String, dynamic>>> Function() load,
      {ValueChanged<String?>? onOpen,
      Brightness brightness = Brightness.dark,
      double width = 390,
      double textScale = 1}) async {
    AppColors.isDarkMode = brightness == Brightness.dark;
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AppColors.isDarkMode = true;
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [reelsProvider.overrideWith((_) => load())],
      child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ExploreReelsSection(onOpenReel: onOpen)))),
    ));
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'real previews are paused and open the exact selected ID in $brightness',
        (tester) async {
      final opened = <String?>[];
      await render(tester, () async => _reels,
          brightness: brightness, onOpen: opened.add);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final videos = tester.widgetList<NetworkVideo>(find.byType(NetworkVideo));
      expect(videos, isNotEmpty);
      for (final video in videos) {
        expect(video.posterOnly, isTrue);
        expect(video.autoplay, isFalse);
        expect(video.active, isFalse);
      }
      await tester.tap(find.byKey(const ValueKey('explore-reel-clip-0')));
      expect(opened, ['clip-0']);
      await tester.tap(find.text('Бүгдийг үзэх'));
      expect(opened, ['clip-0', null]);
    });
  }

  testWidgets(
      'narrow width and large text keep gallery controls inside the screen',
      (tester) async {
    final opened = <String?>[];
    await render(tester, () async => _reels,
        width: 320, textScale: 1.5, onOpen: opened.add);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Бүгдийг үзэх'));
    expect(opened, [null]);
    await tester.tap(find.byKey(const ValueKey('explore-reel-clip-0')));
    expect(opened, [null, 'clip-0']);
  });

  testWidgets('pending load is shown honestly then resolves to the empty state',
      (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    await render(tester, () => pending.future);
    await tester.pump();
    expect(find.text('Бичлэгүүдийг ачаалж байна'), findsOneWidget);
    expect(find.text('Шинэ бичлэгүүд удахгүй'), findsNothing);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Бичлэгүүдийг ачаалж байна'), findsNothing);
    expect(find.text('Шинэ бичлэгүүд удахгүй'), findsOneWidget);
    expect(find.byType(NetworkVideo), findsNothing);
  });

  testWidgets('failure offers a retry that loads actual clips', (tester) async {
    var attempts = 0;
    await render(tester, () async {
      if (++attempts == 1) throw StateError('offline');
      return _reels;
    });
    await tester.pumpAndSettle();
    expect(find.text('Бичлэгүүдийг ачаалж чадсангүй'), findsOneWidget);
    expect(find.text('Шинэ бичлэгүүд удахгүй'), findsNothing);
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(NetworkVideo), findsWidgets);
    expect(find.text('Бичлэгүүдийг ачаалж чадсангүй'), findsNothing);
  });
}
