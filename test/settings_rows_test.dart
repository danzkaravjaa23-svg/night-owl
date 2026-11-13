import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/widgets/settings_rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 390, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: app!),
        home: Scaffold(
            body: ListView(
                padding: const EdgeInsets.all(20), children: [child]))));
    await tester.pumpAndSettle();
  }

  Finder toggle() => find.descendant(
      of: find.byType(SettingsSwitch),
      matching: find.byWidgetPredicate((widget) =>
          widget is Semantics && widget.properties.toggled != null));

  testWidgets('tappable row shows a chevron and runs onTap', (tester) async {
    var taps = 0;
    await pump(
        tester,
        SettingsCard(children: [
          SettingsRow(
              icon: Icons.person_outline,
              title: 'Профайл засах',
              subtitle: 'Нэр, зураг, танилцуулга',
              onTap: () => taps++),
          const SettingsDivider(),
          const SettingsRow(
              icon: Icons.account_tree_outlined,
              title: 'Хувилбар · Үнэгүй',
              value: '1.0.0',
              monospaceValue: true),
        ]));
    // Only the tappable row gets a chevron; the static version row does not.
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.person_outline)).color,
        AppColors.accentText);
    expect(find.text('Нэр, зураг, танилцуулга'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    await tester.tap(find.text('Профайл засах'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled row is dimmed, has no chevron and ignores taps',
      (tester) async {
    var taps = 0;
    await pump(
        tester,
        SettingsRow(
            icon: Icons.lock_person_outlined,
            title: 'Нууцлал, хүсэлтүүд',
            onTap: () => taps++,
            enabled: false));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(tester.widget<Icon>(find.byIcon(Icons.lock_person_outlined)).color,
        AppColors.textTertiary);
    final opacity = tester.widget<Opacity>(find
        .ancestor(
            of: find.text('Нууцлал, хүсэлтүүд'),
            matching: find.byType(Opacity))
        .first);
    expect(opacity.opacity, 0.55);
    await tester.tap(find.text('Нууцлал, хүсэлтүүд'));
    await tester.pump();
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch row: 44 px target, semantics, switch wins its own tap',
      (tester) async {
    final handle = tester.ensureSemantics();
    final calls = <String>[];
    await pump(
        tester,
        SettingsRow(
            icon: Icons.notifications_none,
            title: 'Апп доторх мэдэгдэл',
            onTap: () => calls.add('row'),
            trailing: SettingsSwitch(
                value: false,
                onChanged: (value) => calls.add('switch:$value'))));
    // Like SwitchListTile, a screen reader gets one node with the title, the
    // on/off state and a tap action (not a nameless switch).
    expect(
        tester.getSemantics(find.text('Апп доторх мэдэгдэл')),
        containsSemantics(
            label: 'Апп доторх мэдэгдэл',
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true));
    // A trailing widget replaces the chevron.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    final semantics = tester.widget<Semantics>(toggle()).properties;
    expect(semantics.toggled, isFalse);
    expect(semantics.enabled, isTrue);
    expect(tester.getSize(toggle()).height, greaterThanOrEqualTo(44));
    await tester.tap(toggle());
    await tester.pump();
    expect(calls, ['switch:true']);
    await tester.tap(find.text('Апп доторх мэдэгдэл'));
    await tester.pump();
    expect(calls, ['switch:true', 'row']);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('switch without onChanged reports disabled and ignores taps',
      (tester) async {
    await pump(tester, const SettingsSwitch(value: true, onChanged: null));
    final semantics = tester.widget<Semantics>(toggle()).properties;
    expect(semantics.toggled, isTrue);
    expect(semantics.enabled, isFalse);
    await tester.tap(toggle());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale, compact) in const [
    (390.0, 1.0, false),
    (320.0, 2.0, true),
  ]) {
    testWidgets('icon tile and divider inset at ${width}px, ${scale}x text',
        (tester) async {
      await pump(
          tester,
          SettingsCard(children: [
            SettingsRow(
                icon: Icons.help_outline, title: 'Тусламж', onTap: () {}),
            const SettingsDivider(),
            SettingsRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Нууцлалын бодлого',
                onTap: () {}),
          ]),
          width: width,
          scale: scale);
      expect(find.byIcon(Icons.help_outline),
          compact ? findsNothing : findsOneWidget);
      final inset = tester.widget<Padding>(find
          .ancestor(of: find.byType(Divider), matching: find.byType(Padding))
          .first);
      expect(inset.padding,
          EdgeInsets.only(left: compact ? 12 : 56, right: 12));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('section label uses the secondary text colour', (tester) async {
    await pump(tester, const SettingsSectionLabel('Таны бүртгэл'));
    expect(tester.widget<Text>(find.text('Таны бүртгэл')).style?.color,
        AppColors.textSecondary);
    expect(tester.takeException(), isNull);
  });
}
