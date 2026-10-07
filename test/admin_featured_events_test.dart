import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/admin/screens/admin_featured_events_screen.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/events/providers/event_provider.dart';
import 'package:night_owl_ub/features/events/providers/featured_events_provider.dart';
import 'package:night_owl_ub/models/user_profile.dart';

class _FeatureService extends EventFeatureService {
  _FeatureService(SupabaseClient client) : super(client: client);

  final selected = <String>{};
  final mutations = <({String id, bool featured})>[];
  Completer<void>? pending;
  int loads = 0;

  @override
  Future<List<FeaturedEventSelection>> loadSelections() async {
    loads++;
    return [
      for (final id in selected) FeaturedEventSelection(eventId: id, rank: 0),
    ];
  }

  @override
  Future<List<EventItem>> loadFeatured() async => [];

  @override
  Future<void> setFeatured(String eventId,
      {required bool featured, int rank = 0}) async {
    mutations.add((id: eventId, featured: featured));
    await pending?.future;
    if (featured) {
      selected.add(eventId);
    } else {
      selected.remove(eventId);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late _FeatureService service;
  late int candidateLoads;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    candidateLoads = 0;
    client = SupabaseClient('https://example.test', 'fixture-public-key',
        httpClient: MockClient(
            (request) async => http.Response('[]', 200, request: request)));
    service = _FeatureService(client);
  });
  tearDown(() => client.dispose());

  Future<void> render(WidgetTester tester, {bool admin = true}) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('fixture-user'),
        currentProfileProvider.overrideWith(
            (ref) async => UserProfile(id: 'fixture-user', isAdmin: admin)),
        upcomingEventsProvider.overrideWith((ref) async {
          candidateLoads++;
          return [
            EventItem(
                id: 'first', title: 'Acoustic night', startsAt: DateTime(2030)),
            EventItem(
                id: 'second', title: 'DJ night', startsAt: DateTime(2030)),
          ];
        }),
        eventFeatureServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!),
        home: const AdminFeaturedEventsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ordinary users cannot load admin selections or see controls',
      (tester) async {
    await render(tester, admin: false);
    expect(find.text('Энэ хэсэг зөвхөн Night Owl-ийн админд нээлттэй.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('feature-event-first')), findsNothing);
    expect(candidateLoads, 0);
    expect(service.loads, 0);
    expect(service.mutations, isEmpty);
  });

  testWidgets('select and remove wait for server and disable duplicate actions',
      (tester) async {
    await render(tester);
    final first = find.byKey(const ValueKey('feature-event-first'));
    final second = find.byKey(const ValueKey('feature-event-second'));
    service.pending = Completer<void>();
    await tester.tap(first);
    await tester.pump();
    expect(find.text('Хадгалж байна…'), findsOneWidget);
    expect(service.selected, isEmpty, reason: 'No optimistic selection.');
    expect(tester.widget<FilledButton>(first).onPressed, isNull);
    expect(tester.widget<FilledButton>(second).onPressed, isNull);
    expect(service.mutations, hasLength(1));
    service.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Онцлохоос хасах'), findsOneWidget);
    expect(service.selected, {'first'});

    service.pending = Completer<void>();
    await tester.tap(first);
    await tester.pump();
    expect(service.selected, {'first'}, reason: 'No optimistic removal.');
    service.pending!.complete();
    await tester.pumpAndSettle();
    expect(service.selected, isEmpty);
    expect(find.text('Онцлохоос хасах'), findsNothing);
    expect(service.mutations, [
      (id: 'first', featured: true),
      (id: 'first', featured: false),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server rejection retains selection state and offers retry',
      (tester) async {
    await render(tester);
    final first = find.byKey(const ValueKey('feature-event-first'));
    service.pending = Completer<void>();
    await tester.tap(first);
    await tester.pump();
    service.pending!.completeError(
        const PostgrestException(message: 'Permission denied', code: '42501'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Өөрчлөлтийг хадгалж чадсангүй.'), findsOneWidget);
    expect(service.selected, isEmpty);
    expect(find.text('Онцлохоос хасах'), findsNothing);
    expect(tester.widget<FilledButton>(first).onPressed, isNotNull);
    service.pending = null;
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(service.selected, {'first'});
    expect(find.textContaining('Өөрчлөлтийг хадгалж чадсангүй.'), findsNothing);
  });

  testWidgets('admin can remove a selection missing from upcoming candidates',
      (tester) async {
    service.selected.add('expired');
    await render(tester);
    final old = find.byKey(const ValueKey('feature-event-expired'));
    await tester.ensureVisible(old);
    await tester.tap(old);
    await tester.pumpAndSettle();
    expect(service.mutations.single, (id: 'expired', featured: false));
    expect(service.selected, isEmpty);
    expect(old, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
