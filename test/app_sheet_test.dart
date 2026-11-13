import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/widgets/app_sheet.dart';

// DS-02: showAppSheet opens on the ROOT navigator, so a sheet opened from a
// shell tab covers the dock; it has exactly one drag handle; it closes with
// its own context; and its dark variant stays dark in the Day theme.

const _dockKey = Key('dock');

/// A tab page inside the nested (shell) navigator with an "Open" button.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.title, required this.onOpen});

  final String title;
  final void Function(BuildContext pageContext) onOpen;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title),
            TextButton(
                onPressed: () => onOpen(context), child: const Text('Open')),
          ]),
        ),
      );
}

/// Shell like go_router's ShellRoute: tab pages live in a nested navigator,
/// the dock sits outside it in the Scaffold's bottom bar.
Widget _shell({
  required GlobalKey<NavigatorState> shellKey,
  required Widget page,
  VoidCallback? onDock,
}) =>
    Scaffold(
      body: Navigator(
        key: shellKey,
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(settings: settings, builder: (_) => page),
      ),
      bottomNavigationBar: SizedBox(
        key: _dockKey,
        height: 72,
        child: Center(
            child: TextButton(onPressed: onDock, child: const Text('Dock'))),
      ),
    );

Future<void> _pumpShell(
  WidgetTester tester, {
  required ThemeData theme,
  required GlobalKey<NavigatorState> shellKey,
  required Widget page,
  VoidCallback? onDock,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: _shell(shellKey: shellKey, page: page, onDock: onDock),
  ));
  await tester.pumpAndSettle();
}

/// Sheet content: a header, one choice that pops with the SHEET's context,
/// and inert space over the area where the dock sits underneath.
Widget _sheetBody(BuildContext sheetContext) => SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const AppSheetHeader(
            title: 'Сонголтууд', subtitle: 'Туршилтын sheet', showClose: true),
        ListTile(
          title: const Text('Сонгох'),
          onTap: () => Navigator.of(sheetContext).pop('picked'),
        ),
        const SizedBox(height: 120),
      ]),
    );

/// Drag-handle-shaped boxes inside the sheet: 4 px tall, 30-48 px wide,
/// rounded. Matches the Material handle and any hand-drawn 40×4 copy.
List<Element> _handles(WidgetTester tester) => find
    .descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius != null))
    .evaluate()
    .where((element) {
  final box = element.renderObject;
  if (box is! RenderBox || !box.hasSize) return false;
  return box.size.height == 4 && box.size.width >= 30 && box.size.width <= 48;
}).toList();

/// Background of the sheet's Material.
Color _sheetColor(WidgetTester tester) => tester
    .widget<Material>(find
        .descendant(of: find.byType(BottomSheet), matching: find.byType(Material))
        .first)
    .color!;

/// Sends Android's system back through the platform channel.
Future<void> _systemBack(WidgetTester tester) async {
  final message =
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

/// Router whose back handling copies go_router 13: the deepest navigator
/// that can pop gets the back press, even under a sheet on the root.
class _ShellRouterDelegate extends RouterDelegate<Object> with ChangeNotifier {
  _ShellRouterDelegate({required this.shellKey, required this.home});

  final GlobalKey<NavigatorState> shellKey;
  final Widget home;
  final _rootKey = GlobalKey<NavigatorState>();

  @override
  Future<bool> popRoute() async {
    final shell = shellKey.currentState;
    if (shell != null && shell.canPop()) return shell.maybePop();
    return await _rootKey.currentState?.maybePop() ?? false;
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {}

  @override
  Widget build(BuildContext context) => Navigator(
        key: _rootKey,
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(settings: settings, builder: (_) => home),
      );
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => AppColors.isDarkMode = true);

  testWidgets('opens on the root navigator, so the dock is covered',
      (tester) async {
    final shellKey = GlobalKey<NavigatorState>();
    var dockTaps = 0;
    String? result = 'not closed';
    await _pumpShell(tester,
        theme: AppTheme.dark,
        shellKey: shellKey,
        onDock: () => dockTaps++,
        page: _TabPage(
            title: 'Tab page',
            onOpen: (pageContext) async {
              result = await showAppSheet<String>(
                  context: pageContext, builder: _sheetBody);
            }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    // The sheet route belongs to the root navigator, not the shell one.
    final root = Navigator.of(tester.element(find.byKey(_dockKey)));
    final sheetRoute = ModalRoute.of(tester.element(find.text('Сонгох')))!;
    expect(sheetRoute.navigator, same(root));
    expect(shellKey.currentState!.canPop(), isFalse);

    // The sheet's barrier spans the dock and the sheet reaches the bottom of
    // the screen, over the dock, so a tap where the dock is does not reach it.
    final dock = tester.getRect(find.byKey(_dockKey));
    final barrier = tester.getRect(find.byType(ModalBarrier).last);
    expect(barrier.contains(dock.center), isTrue);
    expect(tester.getRect(find.byType(BottomSheet)).bottom,
        greaterThanOrEqualTo(dock.bottom));
    await tester.tap(find.text('Dock'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(dockTaps, 0);
    expect(find.byType(BottomSheet), findsOneWidget);

    // The barrier above the sheet dims the page and dismisses on tap.
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(result, isNull);
    expect(dockTaps, 0);
  });

  testWidgets('control: a sheet on the nested navigator leaves the dock live',
      (tester) async {
    final shellKey = GlobalKey<NavigatorState>();
    var dockTaps = 0;
    await _pumpShell(tester,
        theme: AppTheme.dark,
        shellKey: shellKey,
        onDock: () => dockTaps++,
        page: _TabPage(
            title: 'Tab page',
            onOpen: (pageContext) => showAppSheet<String>(
                context: pageContext,
                useRootNavigator: false,
                builder: _sheetBody)));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(shellKey.currentState!.canPop(), isTrue);
    final dock = tester.getRect(find.byKey(_dockKey));
    final barrier = tester.getRect(find.byType(ModalBarrier).last);
    expect(barrier.contains(dock.center), isFalse);
    await tester.tap(find.text('Dock'));
    await tester.pumpAndSettle();
    // This is the DS-02 defect showAppSheet's default avoids.
    expect(dockTaps, 1);
  });

  for (final dark in [true, false]) {
    final mode = dark ? 'Night' : 'Day';

    testWidgets('shows exactly one drag handle ($mode)', (tester) async {
      AppColors.isDarkMode = dark;
      final shellKey = GlobalKey<NavigatorState>();
      await _pumpShell(tester,
          theme: dark ? AppTheme.dark : AppTheme.light,
          shellKey: shellKey,
          page: _TabPage(
              title: 'Tab page',
              onOpen: (pageContext) => showAppSheet<void>(
                  context: pageContext, builder: _sheetBody)));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Сонголтууд'), findsOneWidget);
      expect(find.text('Туршилтын sheet'), findsOneWidget);
      expect(_handles(tester), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('popping with the sheet context returns the value, page stays',
      (tester) async {
    final shellKey = GlobalKey<NavigatorState>();
    String? result;
    await _pumpShell(tester,
        theme: AppTheme.dark,
        shellKey: shellKey,
        page: _TabPage(
            title: 'Tab page',
            onOpen: (pageContext) async {
              result = await showAppSheet<String>(
                  context: pageContext, builder: _sheetBody);
            }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сонгох'));
    await tester.pumpAndSettle();

    expect(result, 'picked');
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Tab page'), findsOneWidget);
    expect(Navigator.of(tester.element(find.byKey(_dockKey))).canPop(),
        isFalse);
  });

  testWidgets('AppSheetHeader close button closes only the sheet',
      (tester) async {
    final shellKey = GlobalKey<NavigatorState>();
    String? result = 'not closed';
    await _pumpShell(tester,
        theme: AppTheme.light,
        shellKey: shellKey,
        page: _TabPage(
            title: 'Tab page',
            onOpen: (pageContext) async {
              result = await showAppSheet<String>(
                  context: pageContext, builder: _sheetBody);
            }));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Сонголтууд'), findsOneWidget);
    await tester.tap(find.byTooltip('Хаах'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(result, isNull);
    expect(find.text('Tab page'), findsOneWidget);
  });

  testWidgets('dark variant stays dark in the Day theme', (tester) async {
    AppColors.isDarkMode = false;
    final shellKey = GlobalKey<NavigatorState>();
    var openDark = true;
    await _pumpShell(tester,
        theme: AppTheme.light,
        shellKey: shellKey,
        page: _TabPage(
            title: 'Reels',
            onOpen: (pageContext) => showAppSheet<String>(
                context: pageContext, dark: openDark, builder: _sheetBody)));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(ThemeData.estimateBrightnessForColor(_sheetColor(tester)),
        Brightness.dark);
    final handle = _handles(tester).single;
    expect(Theme.of(handle).brightness, Brightness.dark);
    final handleColor =
        ((handle.widget as DecoratedBox).decoration as BoxDecoration).color;
    final darkHandle = AppTheme.dark.bottomSheetTheme.dragHandleColor;
    if (darkHandle != null) expect(handleColor, darkHandle);
    expect(Theme.of(tester.element(find.text('Сонгох'))).brightness,
        Brightness.dark);
    final title = tester.widget<Text>(find.text('Сонголтууд'));
    expect(ThemeData.estimateBrightnessForColor(title.style!.color!),
        Brightness.light,
        reason: 'the header title is light text on the dark sheet');

    // Control: the same sheet without `dark` follows the Day theme.
    await tester.tap(find.byTooltip('Хаах'));
    await tester.pumpAndSettle();
    openDark = false;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(ThemeData.estimateBrightnessForColor(_sheetColor(tester)),
        Brightness.light);
    expect(Theme.of(_handles(tester).single).brightness, Brightness.light);
  });

  testWidgets('Android back closes a root sheet, not the nested page under it',
      (tester) async {
    final shellKey = GlobalKey<NavigatorState>();
    final delegate = _ShellRouterDelegate(
      shellKey: shellKey,
      home: _shell(
          shellKey: shellKey,
          page: _TabPage(title: 'Feed', onOpen: (_) {})),
    );
    addTearDown(delegate.dispose);
    await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.dark, routerDelegate: delegate));
    await tester.pumpAndSettle();

    // A second page inside the shell, like context.push('/reels') from feed.
    shellKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => _TabPage(
            title: 'Reels',
            onOpen: (pageContext) => showAppSheet<String>(
                context: pageContext, builder: _sheetBody))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await _systemBack(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Reels'), findsOneWidget,
        reason: 'back must close the sheet, not the page under it');

    // With the sheet gone, back reaches the nested navigator again.
    await _systemBack(tester);
    expect(find.text('Reels'), findsNothing);
    expect(find.text('Feed'), findsOneWidget);
  });
}
