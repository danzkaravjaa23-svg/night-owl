import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/features/profile/screens/profile_screen.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final kind in ProfileContentKind.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
          '$kind empty state has the correct next action in $brightness',
          (tester) async {
        AppColors.isDarkMode = brightness == Brightness.dark;
        tester.view.physicalSize = const Size(320, 680);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          AppColors.isDarkMode = true;
        });
        var created = 0;
        var browsed = 0;
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
                body: MediaQuery(
                    data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.5)),
                    child: SingleChildScrollView(
                        child: ProfileEmptyContent(
                            kind: kind,
                            onCreate: () => created++,
                            onBrowse: () => browsed++))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final isSaved = kind == ProfileContentKind.saved;
        final action = find.text(isSaved ? 'Постууд үзэх' : 'Нийтлэл нэмэх');
        await tester.ensureVisible(action);
        await tester.tap(action);
        expect(created, isSaved ? 0 : 1);
        expect(browsed, isSaved ? 1 : 0);
        expect(find.text('Хадгалсан нийтлэл алга'),
            isSaved ? findsOneWidget : findsNothing);
        expect(find.text('Бичлэг хараахан алга'),
            kind == ProfileContentKind.videos ? findsOneWidget : findsNothing);
      });
    }
  }
}
