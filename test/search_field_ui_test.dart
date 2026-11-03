import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/features/dm/widgets/search_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Search clear follows a replacement controller and keeps focus',
      (tester) async {
    final first = TextEditingController(text: 'Old draft');
    final next = TextEditingController(text: 'Current draft');
    addTearDown(first.dispose);
    addTearDown(next.dispose);
    final changes = <String>[];
    var cleared = 0;
    Widget frame(TextEditingController controller) => MaterialApp(
        home: Scaffold(
            body: SearchField(
                controller: controller,
                hint: 'Хайх',
                onChanged: changes.add,
                onClear: () => cleared++)));
    await tester.pumpWidget(frame(first));
    await tester.pumpWidget(frame(next));
    await tester.tap(find.byTooltip('Цэвэрлэх'));
    await tester.pumpAndSettle();
    expect(first.text, 'Old draft');
    expect(next.text, isEmpty);
    expect(changes, ['']);
    expect(cleared, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue);
    expect(find.byTooltip('Цэвэрлэх'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Search input remains usable at 320 pixels and doubled text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: 'Улаанбаатар');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SearchField(
                        controller: controller,
                        hint: 'Нэр эсвэл мессежээр хайх'))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final clear = find.byTooltip('Цэвэрлэх');
    expect(clear.hitTestable(), findsOneWidget);
    expect(tester.getSize(clear).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
