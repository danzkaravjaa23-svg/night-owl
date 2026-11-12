import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_owl_ub/main.dart';

void main() {
  testWidgets('app locale config gives Mongolian system UI (date picker)',
      (tester) async {
    late BuildContext appContext;
    await tester.pumpWidget(MaterialApp(
      // Яг NightOwlApp-ийн MaterialApp.router-т өгдөг тохиргоо.
      locale: nightOwlLocale,
      supportedLocales: nightOwlSupportedLocales,
      localizationsDelegates: nightOwlLocalizationsDelegates,
      home: Builder(builder: (context) {
        appContext = context;
        return Scaffold(
            body: Center(
                child: TextButton(
                    onPressed: () => showDatePicker(
                        context: context,
                        initialDate: DateTime(2026, 11, 12),
                        firstDate: DateTime(2026),
                        lastDate: DateTime(2027, 12, 31)),
                    child: const Text('Огноо нээх'))));
      }),
    ));
    await tester.pumpAndSettle();
    expect(nightOwlSupportedLocales, const [Locale('mn')]);
    expect(Localizations.localeOf(appContext), const Locale('mn'));
    expect(MaterialLocalizations.of(appContext).cancelButtonLabel, 'Цуцлах');
    expect(MaterialLocalizations.of(appContext).copyButtonLabel, 'Хуулах');
    // Cupertino виджет (жишээ нь iOS-ийн хуулах цэс) асуухад алдаа гарахгүй.
    expect(CupertinoLocalizations.of(appContext), isNotNull);

    await tester.tap(find.text('Огноо нээх'));
    await tester.pumpAndSettle();
    expect(find.text('Огноо сонгох'), findsOneWidget);
    expect(find.text('Цуцлах'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Select date'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
