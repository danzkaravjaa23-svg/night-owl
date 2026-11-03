import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_colors.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/auth/services/account_metadata_service.dart';
import 'package:night_owl_ub/features/profile/screens/settings_screen.dart';
import 'package:night_owl_ub/models/user_profile.dart';

const owner = 'fixture-owner';
const other = 'fixture-other';
const label = 'Хэрэглээний статистик';
const consentKey = 'discovery_analytics_consent';
final fixtureUserProvider = StateProvider<User?>((_) => null);

User user(String id, {Object? consent, bool includeConsent = true}) => User(
    id: id,
    appMetadata: const {},
    userMetadata: {
      'full_name': 'Fixture person',
      if (includeConsent) consentKey: consent,
    },
    aud: 'authenticated',
    createdAt: '2026-11-03T00:00:00Z');

class MetadataRequest {
  final String ownerId;
  final Map<String, dynamic> data;
  final result = Completer<bool>();
  MetadataRequest(this.ownerId, this.data);
}

class FakeMetadataService extends AccountMetadataService {
  final requests = <MetadataRequest>[];

  @override
  Future<bool> update(Map<String, dynamic> data, {required String ownerId}) {
    final request = MetadataRequest(ownerId, Map.of(data));
    requests.add(request);
    return request.result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<
          ({
            ProviderContainer container,
            FakeMetadataService service,
            Widget app
          })>
      render(WidgetTester tester,
          {User? initial,
          bool signedOut = false,
          double width = 390,
          double scale = 1,
          Brightness brightness = Brightness.dark}) async {
    SharedPreferences.setMockInitialValues({'theme_mode': brightness.name});
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => AppColors.isDarkMode = true);
    final service = FakeMetadataService();
    final container = ProviderContainer(overrides: [
      fixtureUserProvider.overrideWith((_) =>
          signedOut ? null : initial ?? user(owner, includeConsent: false)),
      sessionUserIdProvider
          .overrideWith((ref) => ref.watch(fixtureUserProvider)?.id),
      authUserProvider
          .overrideWith((ref) => Stream.value(ref.watch(fixtureUserProvider))),
      currentProfileProvider.overrideWith((ref) async {
        final id = ref.watch(fixtureUserProvider)?.id;
        return id == null
            ? null
            : UserProfile(id: id, username: 'fixture', name: 'Fixture person');
      }),
    ]);
    addTearDown(container.dispose);
    final app = UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: SettingsScreen(metadataService: service)));
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(label), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    return (container: container, service: service, app: app);
  }

  Finder toggle() {
    final row =
        find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
    return find.descendant(
        of: row,
        matching: find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.toggled != null));
  }

  void expectToggle(WidgetTester tester,
      {required bool value, required bool enabled}) {
    final semantics = tester.widget<Semantics>(toggle()).properties;
    expect(semantics.toggled, value);
    expect(semantics.enabled, enabled);
  }

  for (final consent in [null, false, 'true', 1, true]) {
    testWidgets('only explicit boolean true enables consent: $consent',
        (tester) async {
      final fixture =
          await render(tester, initial: user(owner, consent: consent));
      expectToggle(tester, value: consent == true, enabled: true);
      expect(fixture.service.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('missing consent defaults off and signed-out control is disabled',
      (tester) async {
    final fixture = await render(tester, signedOut: true);
    expectToggle(tester, value: false, enabled: false);
    await tester.tap(find.text(label));
    await tester.tap(toggle());
    await tester.pump();
    expect(fixture.service.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending save has no optimistic value and rejects duplicate taps',
      (tester) async {
    final fixture = await render(tester);
    expectToggle(tester, value: false, enabled: true);
    await tester.tap(toggle());
    await tester.pump();
    expect(fixture.service.requests, hasLength(1));
    expect(fixture.service.requests.single.ownerId, owner);
    expect(fixture.service.requests.single.data, {consentKey: true});
    expectToggle(tester, value: false, enabled: false);
    await tester.tap(find.text(label));
    await tester.tap(toggle());
    await tester.pump();
    expect(fixture.service.requests, hasLength(1));
    fixture.service.requests.single.result.complete(true);
    await tester.pumpAndSettle();
    // The service result is not used as an optimistic UI truth. The actual
    // auth metadata event must supply the stored preference.
    expectToggle(tester, value: false, enabled: true);
    fixture.container.read(fixtureUserProvider.notifier).state =
        user(owner, consent: true);
    await tester.pumpAndSettle();
    expectToggle(tester, value: true, enabled: true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failure leaves consent unchanged, then opt-in and opt-out can retry',
      (tester) async {
    final fixture = await render(tester);
    await tester.tap(find.text(label));
    await tester.pump();
    fixture.service.requests.single.result
        .completeError(StateError('fixture-private-failure'));
    await tester.pumpAndSettle();
    expectToggle(tester, value: false, enabled: true);
    expect(find.text('Зөвшөөрлийг хадгалж чадсангүй. Дахин оролдоорой.'),
        findsOneWidget);
    expect(find.textContaining('fixture-private'), findsNothing);
    for (final value in [true, false]) {
      await tester.tap(toggle());
      await tester.pump();
      final request = fixture.service.requests.last;
      expect(request.data, {consentKey: value});
      expectToggle(tester, value: !value, enabled: false);
      fixture.container.read(fixtureUserProvider.notifier).state =
          user(owner, consent: value);
      request.result.complete(true);
      await tester.pumpAndSettle();
      expectToggle(tester, value: value, enabled: true);
    }
    expect(fixture.service.requests, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('confirmed metadata remains visible when Settings is reopened',
      (tester) async {
    final fixture = await render(tester);
    await tester.tap(toggle());
    await tester.pump();
    fixture.container.read(fixtureUserProvider.notifier).state =
        user(owner, consent: true);
    fixture.service.requests.single.result.complete(true);
    await tester.pumpAndSettle();
    expectToggle(tester, value: true, enabled: true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(fixture.app);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(label), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    expectToggle(tester, value: true, enabled: true);
    expect(fixture.service.requests, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final outcome in ['stale', 'failure']) {
    testWidgets(
        'account switch ignores late $outcome and releases pending state',
        (tester) async {
      final fixture = await render(tester);
      await tester.tap(toggle());
      await tester.pump();
      fixture.container.read(fixtureUserProvider.notifier).state =
          user(other, consent: false);
      await tester.pumpAndSettle();
      final old = fixture.service.requests.single;
      if (outcome == 'failure') {
        old.result.completeError(StateError('fixture-private-error'));
      } else {
        old.result.complete(false);
      }
      await tester.pumpAndSettle();
      expectToggle(tester, value: false, enabled: true);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(toggle());
      await tester.pump();
      expect(fixture.service.requests.last.ownerId, other);
      fixture.service.requests.last.result.complete(false);
      await tester.pumpAndSettle();
      expectToggle(tester, value: false, enabled: true);
      expect(find.text('Хаяг өөрчлөгдсөн байна. Дахин нэвтэрч оролдоорой.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('disposing Settings safely ignores a pending save failure',
      (tester) async {
    final fixture = await render(tester);
    await tester.tap(toggle());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    fixture.service.requests.single.result
        .completeError(StateError('fixture-private-error'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
        'consent control remains usable at 320px and 2x text in $brightness',
        (tester) async {
      final fixture =
          await render(tester, width: 320, scale: 2, brightness: brightness);
      expectToggle(tester, value: false, enabled: true);
      expect(tester.getSize(toggle()).height, greaterThanOrEqualTo(44));
      await tester.ensureVisible(toggle());
      await tester.pumpAndSettle();
      await tester.tap(toggle());
      await tester.pump();
      expect(fixture.service.requests, hasLength(1));
      fixture.container.read(fixtureUserProvider.notifier).state =
          user(owner, consent: true);
      fixture.service.requests.single.result.complete(true);
      await tester.pumpAndSettle();
      expectToggle(tester, value: true, enabled: true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
