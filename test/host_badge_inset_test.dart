import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/core/utils/host_badge_inset.dart';

void main() {
  group('hostBadgeInset', () {
    // Live сайт дээр хэмжсэн "Powered by Netlify" iframe ≈ 196×63 CSS px,
    // баруун доод буланд.
    Rect badgeAt(Size window) =>
        Rect.fromLTWH(window.width - 196, window.height - 63, 196, 63);

    test('phone width: badge over the app column reserves its height + gap',
        () {
      const window = Size(390, 844);
      expect(
          hostBadgeInset(
              window: window, columnWidth: 390, badge: badgeAt(window)),
          63 + hostBadgeGap);
    });

    test('320x640 phone also gets the inset', () {
      const window = Size(320, 640);
      expect(
          hostBadgeInset(
              window: window, columnWidth: 320, badge: badgeAt(window)),
          63 + hostBadgeGap);
    });

    test('wide window, narrow (420) route: badge in the gutter needs no inset',
        () {
      const window = Size(1440, 900);
      // MobileFrame голлуулсан 420px багана: [510, 930].
      expect(
          hostBadgeInset(
              window: window, columnWidth: 420, badge: badgeAt(window)),
          0);
    });

    test('wide window, wideLayout route (1120 column): badge overlaps', () {
      const window = Size(1440, 900);
      // feed/explore/profile/map/reels/DM: (1440-48).clamp(420,1120) = 1120
      // багана [160, 1280], badge [1244, 1440] — давхцана.
      expect(
          hostBadgeInset(
              window: window, columnWidth: 1120, badge: badgeAt(window)),
          63 + hostBadgeGap);
    });

    test('medium window: badge partly over the centred column', () {
      const window = Size(600, 800);
      // Багана [90, 510], badge [404, 600] — давхцана.
      expect(
          hostBadgeInset(
              window: window, columnWidth: 420, badge: badgeAt(window)),
          63 + hostBadgeGap);
    });

    test('no badge, empty or implausible badge gives zero', () {
      const window = Size(390, 844);
      expect(hostBadgeInset(window: window, columnWidth: 390, badge: null), 0);
      expect(
          hostBadgeInset(
              window: window,
              columnWidth: 390,
              badge: const Rect.fromLTWH(300, 844, 0, 0)),
          0);
      expect(
          hostBadgeInset(
              window: window,
              columnWidth: 390,
              badge: const Rect.fromLTWH(0, 300, 390, 544)),
          0);
    });
  });

  group('HostBadgeInset', () {
    const body = Key('app-body');

    Future<void> pumpApp(WidgetTester tester, ValueNotifier<Rect?> badge,
        {bool enabled = true}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            HostBadgeInset(enabled: enabled, badge: badge, child: child!),
        home: const Scaffold(body: SizedBox.expand(key: body)),
      ));
      await tester.pump();
    }

    testWidgets('adds no padding without a badge', (tester) async {
      final badge = ValueNotifier<Rect?>(null);
      addTearDown(badge.dispose);
      await pumpApp(tester, badge);
      expect(tester.getSize(find.byKey(body)), const Size(390, 844));
      expect(MediaQuery.sizeOf(tester.element(find.byKey(body))),
          const Size(390, 844));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reserves room while the badge covers the app and releases it',
        (tester) async {
      final badge = ValueNotifier<Rect?>(null);
      addTearDown(badge.dispose);
      await pumpApp(tester, badge);
      badge.value = const Rect.fromLTWH(194, 781, 196, 63);
      await tester.pump();
      const inset = 63 + hostBadgeGap;
      expect(tester.getSize(find.byKey(body)), const Size(390, 844 - inset));
      expect(tester.getBottomLeft(find.byKey(body)).dy, 844 - inset);
      final context = tester.element(find.byKey(body));
      expect(MediaQuery.sizeOf(context).height, 844 - inset);
      expect(MediaQuery.paddingOf(context).bottom, 0);
      badge.value = null;
      await tester.pump();
      expect(tester.getSize(find.byKey(body)), const Size(390, 844));
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the app subtree state while the badge comes and goes',
        (tester) async {
      final badge = ValueNotifier<Rect?>(null);
      addTearDown(badge.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            HostBadgeInset(enabled: true, badge: badge, child: child!),
        home: const Scaffold(body: _Counter()),
      ));
      await tester.tap(find.byKey(_Counter.button));
      await tester.pump();
      final state = tester.state<_CounterState>(find.byType(_Counter));
      expect(find.text('1'), findsOneWidget);

      badge.value = const Rect.fromLTWH(194, 781, 196, 63);
      await tester.pump();
      expect(tester.getSize(find.byType(Scaffold)).height,
          844 - (63 + hostBadgeGap));
      expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
      expect(find.text('1'), findsOneWidget);

      badge.value = null;
      await tester.pump();
      expect(tester.getSize(find.byType(Scaffold)).height, 844);
      expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard: the body still ends at the keyboard top',
        (tester) async {
      final badge =
          ValueNotifier<Rect?>(const Rect.fromLTWH(194, 781, 196, 63));
      addTearDown(badge.dispose);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await pumpApp(tester, badge);
      expect(tester.getBottomLeft(find.byKey(body)).dy, 844 - 300);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does nothing off the web even if a rect is reported',
        (tester) async {
      final badge =
          ValueNotifier<Rect?>(const Rect.fromLTWH(194, 781, 196, 63));
      addTearDown(badge.dispose);
      await pumpApp(tester, badge, enabled: false);
      expect(tester.getSize(find.byKey(body)), const Size(390, 844));
      expect(tester.takeException(), isNull);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  static const button = Key('counter-button');
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _n = 0;
  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          key: _Counter.button,
          onPressed: () => setState(() => _n++),
          child: Text('$_n'),
        ),
      );
}
