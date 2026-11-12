import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/core/theme/app_theme.dart';
import 'package:night_owl_ub/core/widgets/bare_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final dark in [true, false]) {
    testWidgets(
        'bareInput draws no inner box over the ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      addTearDown(() => AppColors.isDarkMode = true);
      AppColors.isDarkMode = dark;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 280,
                      child: TextField(
                          focusNode: focus,
                          maxLength: 500,
                          decoration: bareInput(
                              hintText: 'Сэтгэгдэл бичих…',
                              hideCounter: true)))))));
      await tester.pump();

      void expectBare() {
        final decoration =
            tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
        // Theme-ийн inputDecorationTheme (filled + radius-14 outline) дарагдсан
        expect(decoration.filled, isFalse);
        expect(decoration.border, InputBorder.none);
        expect(decoration.enabledBorder, InputBorder.none);
        expect(decoration.focusedBorder, InputBorder.none);
        expect(decoration.disabledBorder, InputBorder.none);
        expect(decoration.errorBorder, InputBorder.none);
        expect(decoration.focusedErrorBorder, InputBorder.none);
        expect(decoration.counterText, '');
      }

      expect(find.text('Сэтгэгдэл бичих…'), findsOneWidget);
      expectBare();

      focus.requestFocus();
      // Focus нь microtask-аар хэрэгжиж, TextField-ийн setState дараагийн
      // frame-д буудаг тул хоёр pump хэрэгтэй.
      await tester.pump();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused,
          isTrue);
      expectBare();
      // 500 тэмдэгтийн тоолуур харагдахгүй
      expect(find.text('0/500'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
