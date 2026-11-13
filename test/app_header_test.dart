import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/router/app_router.dart' show AppRoutes;
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_icons.dart';
import 'package:night_owl_ub/core/theme/app_spacing.dart';
import 'package:night_owl_ub/core/theme/app_text_styles.dart';
import 'package:night_owl_ub/core/widgets/app_header.dart';
import 'package:night_owl_ub/core/widgets/glass_icon_button.dart';
import 'package:night_owl_ub/core/widgets/night_owl_brand.dart';
import 'package:night_owl_ub/core/widgets/premium_surface.dart';

/// Дэлгэцийг өгсөн өргөн ба текстийн масштабаар зурна (dpr 1 — пиксел = dp).
Future<void> _pump(WidgetTester tester, Widget home,
    {double width = 390, double scale = 1}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: home,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pumpRouter(WidgetTester tester, GoRouter router) async {
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

GlassIconButton _action(IconData icon, String tooltip) =>
    GlassIconButton(icon: icon, tooltip: tooltip, onTap: () {});

final _badgeFill = find.byWidgetPredicate((widget) =>
    widget is Container &&
    widget.decoration is BoxDecoration &&
    (widget.decoration! as BoxDecoration).color == AppColors.dangerFill);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('AppHeader', () {
    testWidgets('brand: one logo size at any text scale, edges on the gutter',
        (tester) async {
      Widget screen() => Scaffold(
            body: Column(children: [
              AppHeader.brand(actions: [_action(Icons.search, 'Хайх')]),
              const Expanded(child: SizedBox()),
            ]),
          );
      await _pump(tester, screen());

      expect(find.byType(NightOwlBrand), findsOneWidget);
      expect(tester.widget<NightOwlBrand>(find.byType(NightOwlBrand)).size,
          AppHeader.brandSize);
      expect(
          find.descendant(
              of: find.byType(AppHeader),
              matching: find.byType(NightOwlAtmosphere)),
          findsOneWidget);
      expect(tester.getSize(find.byType(AppHeader)).height, AppHeader.height);
      // Шар шувууны зурагт ~2px тунгалаг зах бий — үзэгдэх ирмэг нь 20px дээр.
      expect(tester.getTopLeft(find.byType(NightOwlBrand)).dx,
          AppSpacing.page - 2);
      // 44px хүрэх талбар 40px дискийг 2px-ээр тойрно: диск 390 − 20 дээр дуусна.
      expect(tester.getTopRight(find.byType(GlassIconButton)).dx,
          390 - AppSpacing.page + 2);
      final logo = tester.getSize(find.byType(NightOwlBrand));

      // Лого нь текстийн масштабаар томрохгүй — tab хооронд үсрэхгүй.
      await _pump(tester, screen(), scale: 1.6);
      expect(tester.getSize(find.byType(NightOwlBrand)), logo);
      expect(tester.takeException(), isNull);
    });

    testWidgets('title: pageTitle, caption subtitle, chevron back on gutter',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
          tester,
          const Scaffold(
            appBar: AppHeader.title(title: 'Тохиргоо', subtitle: '3 пост'),
            body: SizedBox(),
          ));

      expect(tester.widget<Text>(find.text('Тохиргоо')).style,
          AppTextStyles.pageTitle);
      expect(tester.widget<Text>(find.text('3 пост')).style,
          AppTextStyles.caption);
      expect(find.byIcon(AppIcons.back), findsOneWidget);
      expect(find.byTooltip('Буцах'), findsOneWidget);
      expect(find.bySemanticsLabel('Буцах'), findsOneWidget);
      // Буцах дискний зүүн ирмэг gutter дээр, гарчиг дискээс 12px зайтай.
      expect(tester.getTopLeft(find.byType(GlassIconButton)).dx,
          AppSpacing.page - 2);
      expect(tester.getTopLeft(find.text('Тохиргоо')).dx,
          AppSpacing.page + 40 + 12);
      expect(tester.getSemantics(find.text('Тохиргоо')),
          containsSemantics(label: 'Тохиргоо', isHeader: true));
      semantics.dispose();
    });

    testWidgets('title: compact uses the title token; no back hugs the gutter',
        (tester) async {
      await _pump(
          tester,
          const Scaffold(
            body: Column(children: [
              AppHeader.title(
                  title: 'Газрын мэдээлэл', compact: true, showBack: false),
            ]),
          ));

      expect(tester.widget<Text>(find.text('Газрын мэдээлэл')).style,
          AppTextStyles.title);
      expect(find.byTooltip('Буцах'), findsNothing);
      expect(tester.getTopLeft(find.text('Газрын мэдээлэл')).dx,
          AppSpacing.page);
    });

    testWidgets('back pops when there is a page underneath', (tester) async {
      final router = GoRouter(initialLocation: '/home', routes: [
        GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('Нүүр хуудас'))),
        GoRoute(
            path: '/fallback',
            builder: (_, __) => const Scaffold(body: Text('Нөөц хуудас'))),
        GoRoute(
            path: '/detail',
            builder: (_, __) => const Scaffold(
                appBar: AppHeader.title(
                    title: 'Дэлгэрэнгүй', fallbackLocation: '/fallback'),
                body: SizedBox())),
      ]);
      await _pumpRouter(tester, router);
      router.push('/detail');
      await tester.pumpAndSettle();
      expect(find.text('Дэлгэрэнгүй'), findsOneWidget);

      await tester.tap(find.byTooltip('Буцах'));
      await tester.pumpAndSettle();
      expect(find.text('Нүүр хуудас'), findsOneWidget);
      expect(find.text('Дэлгэрэнгүй'), findsNothing);
      expect(find.text('Нөөц хуудас'), findsNothing);
    });

    testWidgets('back goes to fallbackLocation when nothing can pop',
        (tester) async {
      // Deep link / refresh: stack-д ганц хуудас.
      final router = GoRouter(initialLocation: '/detail', routes: [
        GoRoute(
            path: '/fallback',
            builder: (_, __) => const Scaffold(body: Text('Нөөц хуудас'))),
        GoRoute(
            path: '/detail',
            builder: (_, __) => const Scaffold(
                appBar: AppHeader.title(
                    title: 'Дэлгэрэнгүй', fallbackLocation: '/fallback'),
                body: SizedBox())),
      ]);
      await _pumpRouter(tester, router);

      await tester.tap(find.byTooltip('Буцах'));
      await tester.pumpAndSettle();
      expect(find.text('Нөөц хуудас'), findsOneWidget);
      expect(find.text('Дэлгэрэнгүй'), findsNothing);
    });

    testWidgets('back defaults to the feed; onBack replaces the default',
        (tester) async {
      var taps = 0;
      final router = GoRouter(initialLocation: '/detail', routes: [
        GoRoute(
            path: AppRoutes.feed,
            builder: (_, __) => const Scaffold(body: Text('Нийтлэл хуудас'))),
        GoRoute(
            path: '/detail',
            builder: (_, __) => const Scaffold(
                appBar: AppHeader.title(title: 'Дэлгэрэнгүй'),
                body: SizedBox())),
        GoRoute(
            path: '/custom',
            builder: (_, __) => Scaffold(
                appBar: AppHeader.title(
                    title: 'Тусгай', onBack: () => taps++),
                body: const SizedBox())),
      ]);
      await _pumpRouter(tester, router);

      await tester.tap(find.byTooltip('Буцах'));
      await tester.pumpAndSettle();
      expect(find.text('Нийтлэл хуудас'), findsOneWidget);

      router.go('/custom');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Буцах'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.text('Тусгай'), findsOneWidget);
    });

    testWidgets('media: transparent, onMedia buttons, light title in both themes',
        (tester) async {
      addTearDown(() => AppColors.isDarkMode = true);
      for (final dark in [true, false]) {
        AppColors.isDarkMode = dark;
        await _pump(
            tester,
            Scaffold(
              body: Stack(children: [
                const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF808080))),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AppHeader.media(
                    title: 'Миний профайл',
                    centerTitle: true,
                    actions: [
                      GlassIconButton(
                          icon: Icons.settings_outlined,
                          onMedia: true,
                          tooltip: 'Тохиргоо',
                          onTap: () {}),
                    ],
                  ),
                ),
              ]),
            ));

        final buttons =
            tester.widgetList<GlassIconButton>(find.byType(GlassIconButton));
        expect(buttons, hasLength(2));
        expect(buttons.every((button) => button.onMedia), isTrue);
        final style = tester.widget<Text>(find.text('Миний профайл')).style!;
        expect(style.color, AppColors.textPrimaryDark);
        expect(style.fontSize, AppTextStyles.title.fontSize);
        expect(
            find.descendant(
                of: find.byType(AppHeader),
                matching: find.byType(NightOwlAtmosphere)),
            findsNothing);
        // centerTitle: бүх өргөний төвд.
        expect(tester.getCenter(find.text('Миний профайл')).dx,
            moreOrLessEquals(195, epsilon: .5));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Scaffold.appBar and inline: the header pads the status bar',
        (tester) async {
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPadding);
      expect(const AppHeader.title(title: 'Админ').preferredSize,
          const Size.fromHeight(AppHeader.height));

      // Scaffold.appBar: 64 + status bar; body нь доор нь эхэлнэ.
      await _pump(
          tester,
          const Scaffold(
            appBar: AppHeader.title(title: 'Админ панел'),
            body: Align(alignment: Alignment.topLeft, child: Text('Агуулга')),
          ));
      expect(tester.getSize(find.byType(AppHeader)).height, 24 + 64);
      expect(tester.getTopLeft(find.byType(GlassIconButton)).dy, 24 + 10);
      expect(tester.getTopLeft(find.text('Агуулга')).dy, 24 + 64);

      // Bottom (TabBar) нь preferredSize-д нэмэгдэнэ.
      const tabs = TabBar(tabs: [Tab(text: 'Хүмүүс'), Tab(text: 'Газрууд')]);
      const withTabs =
          AppHeader.title(title: 'Нээх', compact: true, bottom: tabs);
      expect(withTabs.preferredSize.height,
          AppHeader.height + tabs.preferredSize.height);
      await _pump(
          tester,
          const DefaultTabController(
              length: 2,
              child: Scaffold(appBar: withTabs, body: SizedBox())));
      expect(tester.getSize(find.byType(AppHeader)).height,
          24 + AppHeader.height + tabs.preferredSize.height);

      // Inline, SafeArea-ийн ГАДНА: status bar-ыг өөрөө авч, гэрэл доогуур нь.
      await _pump(
          tester,
          const Scaffold(
              body: Column(children: [AppHeader.brand()])));
      expect(tester.getSize(find.byType(AppHeader)).height, 24 + 64);

      // Inline, SafeArea-ийн ДОТОР: давхар зай авахгүй.
      await _pump(
          tester,
          const Scaffold(
              body: SafeArea(
                  child: Column(
                      children: [AppHeader.title(title: 'Хадгалсан')]))));
      expect(tester.getSize(find.byType(AppHeader)).height, 64);
      expect(tester.getTopLeft(find.byType(AppHeader)).dy, 24);

      // primary: false — status bar-ыг үл тооно (sheet, карт дотор).
      await _pump(
          tester,
          const Scaffold(
              body: Column(children: [
            AppHeader.title(title: 'Карт', primary: false),
          ])));
      expect(tester.getSize(find.byType(AppHeader)).height, 64);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every variant fits 320px with doubled text', (tester) async {
      await _pump(
          tester,
          Scaffold(
            body: Column(children: [
              AppHeader.brand(showDivider: true, actions: [
                _action(Icons.search, 'Хайх'),
                _action(Icons.notifications_none_rounded, 'Мэдэгдэл'),
                _action(Icons.chat_bubble_outline_rounded, 'Мессеж'),
              ]),
              AppHeader.title(
                title: 'Мэдэгдэл ба дагах хүсэлтүүдийн жагсаалт',
                subtitle: 'Танд хамаатай шинэ мэдээ',
                actions: [
                  _action(Icons.person_add_outlined, 'Дагах хүсэлтүүд'),
                  _action(Icons.refresh_rounded, 'Дахин ачаалах'),
                ],
              ),
              AppHeader.media(
                title: 'Миний профайл',
                centerTitle: true,
                scrim: true,
                leading: _action(Icons.more_horiz_rounded, 'Үйлдлүүд'),
                actions: [_action(Icons.settings_outlined, 'Тохиргоо')],
              ),
              const Expanded(child: SizedBox()),
            ]),
          ),
          width: 320,
          scale: 2);

      expect(tester.takeException(), isNull);
      final headers = tester.renderObjectList<RenderBox>(find.byType(AppHeader));
      expect(headers, hasLength(3));
      for (final header in headers) {
        expect(header.size.height, AppHeader.height);
      }
      // Урт гарчиг нэг мөрт үлдэж, 64px мөрөөс хэтрэхгүй.
      final title =
          tester.getRect(find.text('Мэдэгдэл ба дагах хүсэлтүүдийн жагсаалт'));
      final row = tester.getRect(find.byType(AppHeader).at(1));
      expect(title.top, greaterThanOrEqualTo(row.top));
      expect(title.bottom, lessThanOrEqualTo(row.bottom));
      expect(title.right, lessThanOrEqualTo(320 - AppSpacing.page));
    });

    testWidgets('a title too wide for 320px at 1.5x shrinks instead of "…"',
        (tester) async {
      // 36px-д ≈271px, slot нь 228px: 1.0x хэмжээнээс доош оролгүй жигд
      // жижгэрч, нэр бүтэн харагдана.
      await _pump(
          tester,
          const Scaffold(
              appBar: AppHeader.title(title: 'Бүртгэл устгах'),
              body: SizedBox()),
          width: 320,
          scale: 1.5);

      expect(tester.takeException(), isNull);
      expect(
          tester
              .renderObject<RenderParagraph>(find.text('Бүртгэл устгах'))
              .didExceedMaxLines,
          isFalse);
      expect(tester.getSize(find.byType(AppHeader)).height, AppHeader.height);
    });
  });

  group('GlassIconButton badge', () {
    testWidgets('shows the count on a contrast-safe pill and announces it',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await _pump(
          tester,
          Scaffold(
            body: Center(
              child: GlassIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Мэдэгдэл',
                  badgeCount: 3,
                  onTap: () => taps++),
            ),
          ));

      expect(find.text('3'), findsOneWidget);
      final count = tester.widget<Text>(find.text('3'));
      expect(count.style?.color, Colors.white);
      expect(count.style?.fontSize, 10);
      expect(count.style?.fontWeight, FontWeight.w700);
      expect(_badgeFill, findsOneWidget);
      expect(find.bySemanticsLabel('Мэдэгдэл, 3 шинэ'), findsOneWidget);
      // Tooltip тоогүй хэвээр — find.byTooltip-д тулгуурласан тестүүд ажилласаар.
      expect(find.byTooltip('Мэдэгдэл'), findsOneWidget);

      // Badge layout-ийг өөрчлөхгүй; дискийн 45°-ийн цэг дээр төвтэй.
      final hit = tester.getRect(find.byType(GlassIconButton));
      expect(hit.size, const Size(44, 44));
      const corner = 20 * (1 - math.sqrt1_2);
      final pill = tester.getRect(_badgeFill);
      expect(pill.top, moreOrLessEquals(hit.top + 2 + corner - 9.5));
      expect(pill.right, moreOrLessEquals(hit.right - 2 - corner + 9.5));
      expect(pill.height, greaterThanOrEqualTo(19));

      // Badge дарахад саад болохгүй.
      await tester.tap(find.byType(GlassIconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      semantics.dispose();
    });

    testWidgets('caps at 99+, announces the real count, dot has no number',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
          tester,
          Scaffold(
            body: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                GlassIconButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Мэдэгдэл',
                    badgeCount: 120,
                    onTap: () {}),
                GlassIconButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    tooltip: 'Мессеж',
                    showBadgeDot: true,
                    onTap: () {}),
                _action(Icons.search, 'Хайх'),
              ]),
            ),
          ),
          scale: 2);

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('120'), findsNothing);
      expect(_badgeFill, findsNWidgets(2));
      expect(find.bySemanticsLabel('Мэдэгдэл, 120 шинэ'), findsOneWidget);
      expect(find.bySemanticsLabel('Мессеж, шинэ'), findsOneWidget);
      expect(find.bySemanticsLabel('Хайх'), findsOneWidget);
      // Том текстэд badge 1.3×-ээс илүү томрохгүй (40px дискийг бүрхэхгүй).
      expect(tester.widget<Text>(find.text('99+')).textScaler!.scale(10),
          moreOrLessEquals(13));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  });
}
