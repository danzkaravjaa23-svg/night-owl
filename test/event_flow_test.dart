import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:night_owl_ub/core/theme/app_fonts.dart';
import 'package:night_owl_ub/features/auth/providers/auth_provider.dart';
import 'package:night_owl_ub/features/events/providers/event_provider.dart';
import 'package:night_owl_ub/features/events/screens/create_event_screen.dart';
import 'package:night_owl_ub/features/events/widgets/events_rail.dart';
import 'package:night_owl_ub/features/post/services/content_publication.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const eventId = '20000000-0000-4000-8000-000000000001';
const venueId = '30000000-0000-4000-8000-000000000001';

http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Map<String, dynamic> draft({DateTime? startsAt, String price = ''}) =>
    eventDraft(
      id: eventId,
      ownerId: owner,
      title: ' Night Owl ',
      description: ' Music ',
      venueId: venueId,
      startsAt: startsAt ?? DateTime.parse('2027-01-01T21:00:00+08:00'),
      price: price,
      now: DateTime.utc(2026, 11, 3),
    );

class FakeSession extends PublicationSession {
  final FakeEventService service;
  final String captured;
  final int generation;
  bool closed = false;
  FakeSession(this.service)
      : captured = service.account,
        generation = service.generation;
  @override
  String get ownerId => captured;
  @override
  String get token => 'fixture-$captured';
  @override
  bool get isCurrent =>
      !closed &&
      captured == service.account &&
      generation == service.generation;
  @override
  void close() => closed = true;
}

class FakeEventService extends EventService {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get sessionChanges => changes.stream;
  String account = owner;
  int generation = 0;
  final rows = <Map<String, dynamic>>[];
  int uploads = 0, mutations = 0, loads = 0;
  EventRsvp rsvp = (going: 4, interested: 2, mine: null);
  bool loadFailure = false;
  Object? uploadFailure;
  Completer<String>? uploadPending;
  Completer<void>? mutationPending;
  Completer<void>? publishPending;
  bool publishSucceeds = false;
  final scopes = <FakeSession>[];
  @override
  PublicationSession captureSession() {
    final session = FakeSession(this);
    scopes.add(session);
    return session;
  }

  @override
  Future<List<Map<String, dynamic>>> ownedVenues(
          PublicationSession session, String query) async =>
      [
        {'id': venueId, 'name': 'Fixture venue'}
      ];
  @override
  Future<Uint8List> prepareStoryImage(Uint8List bytes) async => bytes;
  @override
  Future<String> uploadPost(PublicationSession session, Object blob,
      {required String path,
      required String contentType,
      void Function(double)? onProgress}) async {
    uploads++;
    if (uploadFailure != null) throw uploadFailure!;
    if (uploadPending != null) return await uploadPending!.future;
    return 'https://fixture.test/cover.png';
  }

  @override
  Future<void> publishEvent(
      PublicationSession session, Map<String, dynamic> row) async {
    rows.add(Map.from(row));
    await publishPending?.future;
    if (publishSucceeds) return;
    throw const PublicationFailure('Нийтлэгдсэн байж болно. Дахин шалгана уу.');
  }

  @override
  Future<EventRsvp> loadRsvp(String eventId,
      {PublicationSession? session}) async {
    loads++;
    if (loadFailure) throw const PublicationFailure('Fixture unavailable');
    return rsvp;
  }

  @override
  Future<void> setRsvp(
      PublicationSession session, String eventId, String? status) async {
    mutations++;
    await mutationPending?.future;
    session.check();
    rsvp = (going: status == 'going' ? 5 : 4, interested: 2, mine: status);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppFonts.configure();

  test('event timestamps preserve UTC+8 instant and query has explicit UTC',
      () {
    final row = draft();
    expect(row['starts_at'], '2027-01-01T13:00:00.000Z');
    expect(row['title'], 'Night Owl');
    expect(upcomingSince(DateTime.parse('2026-11-03T21:00:00+08:00')),
        '2026-11-03T10:00:00.000Z');
    expect(() => row['title'] = 'changed', throwsUnsupportedError);
  });

  test('past/current dates and invalid admission prices cannot form a draft',
      () {
    for (final date in [DateTime.utc(2026, 11, 2), DateTime.utc(2026, 11, 3)]) {
      expect(() => draft(startsAt: date), throwsA(isA<PublicationFailure>()));
    }
    for (final price in ['-1', '1.5', '2147483648', 'free']) {
      expect(() => draft(price: price), throwsA(isA<PublicationFailure>()));
    }
    expect(draft(price: '0')['price'], 0);
  });

  group('events isolated transport', () {
    late SupabaseClient client;
    late EventService service;
    late List<http.Request> requests;
    late Future<http.Response> Function(http.Request) respond;
    Future<void> signIn(String id) async {
      final token = 'fixture.${base64Url.encode(utf8.encode(jsonEncode({
                'sub': id,
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              }))).replaceAll('=', '')}.fixture';
      await client.auth.setInitialSession(jsonEncode({
        'access_token': token,
        'refresh_token': 'fixture-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': id,
          'aud': 'authenticated',
          'created_at': '2026-11-03T00:00:00Z'
        },
      }));
      await Future<void>.delayed(Duration.zero);
    }

    setUp(() async {
      requests = [];
      respond = (_) async => http.Response('', 201);
      final transport = MockClient((request) async {
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(response.bodyBytes, response.statusCode,
            headers: response.headers, request: request);
      });
      client = SupabaseClient('https://fixture.test', 'fixture-key',
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      service = EventService(
          client: client,
          httpClient: transport,
          requestTimeout: const Duration(milliseconds: 100));
      await signIn(owner);
    });
    tearDown(() => client.dispose());

    test('publication pins account/token and exact payload', () async {
      final session = service.captureSession();
      addTearDown(session.close);
      final token = session.token;
      await service.publishEvent(session, draft());
      expect(requests.single.headers['authorization'], 'Bearer $token');
      expect(requests.single.headers['apikey'], 'fixture-key');
      expect(jsonDecode(requests.single.body), draft());
      expect(requests.single.url.path, '/rest/v1/events');
    });

    test('lost response retries the same ID and exact payload', () async {
      var attempts = 0;
      respond = (request) async {
        if (request.method == 'POST') {
          if (++attempts == 1) throw Exception('private backend detail');
          return jsonResponse({'code': '23505'}, 409);
        }
        expect(request.url.queryParameters['id'], 'eq.$eventId');
        expect(request.url.queryParameters['organizer_id'], 'eq.$owner');
        return jsonResponse([
          {...draft(), 'starts_at': '2027-01-01T13:00:00+00:00'}
        ]);
      };
      final session = service.captureSession();
      addTearDown(session.close);
      await expectLater(
          service.publishEvent(session, draft()),
          throwsA(isA<PublicationFailure>().having((e) => e.message,
              'uncertain', contains('Нийтлэгдсэн байж болно'))));
      await service.publishEvent(session, draft());
      expect(
          requests.where((r) => r.method == 'POST').map((r) => r.body).toSet(),
          hasLength(1));
    });

    for (final result in [
      [],
      [
        {...draft(), 'organizer_id': other}
      ],
      [
        {...draft(), 'title': 'other payload'}
      ]
    ]) {
      test(
          'duplicate lookup cannot confirm an empty/foreign/different event: $result',
          () async {
        respond = (request) async => request.method == 'POST'
            ? jsonResponse({'code': '23505'}, 409)
            : jsonResponse(result);
        final session = service.captureSession();
        addTearDown(session.close);
        await expectLater(service.publishEvent(session, draft()),
            throwsA(isA<PublicationFailure>()));
      });
    }

    test('account change suppresses late success and blocks later writes',
        () async {
      final waiting = Completer<http.Response>();
      respond = (_) => waiting.future;
      final session = service.captureSession();
      addTearDown(session.close);
      final result = expectLater(service.publishEvent(session, draft()),
          throwsA(isA<PublicationFailure>()));
      await Future<void>.delayed(Duration.zero);
      await signIn(other);
      waiting.complete(http.Response('', 201));
      await result;
      await expectLater(service.setRsvp(session, eventId, 'going'),
          throwsA(isA<PublicationFailure>()));
      expect(requests, hasLength(1));
    });

    test('RSVP reads HEAD counts and own status with captured owner', () async {
      respond = (request) async {
        if (request.method == 'HEAD') {
          expect(request.headers['prefer'], 'count=exact');
          return http.Response('', 200, headers: {
            'content-range': request.url.queryParameters['status'] == 'eq.going'
                ? '0-3/4'
                : '0-1/2'
          });
        }
        expect(request.url.queryParameters['user_id'], 'eq.$owner');
        return jsonResponse([
          {'status': 'interested'}
        ]);
      };
      final session = service.captureSession();
      addTearDown(session.close);
      expect(await service.loadRsvp(eventId, session: session),
          (going: 4, interested: 2, mine: 'interested'));
    });

    test('missing counts and failed mine lookup never become false zero data',
        () async {
      final session = service.captureSession();
      addTearDown(session.close);
      respond = (_) async => http.Response('', 200);
      await expectLater(service.loadRsvp(eventId, session: session),
          throwsA(isA<PublicationFailure>()));
      respond = (request) async => request.method == 'HEAD'
          ? http.Response('', 200, headers: {'content-range': '*/0'})
          : jsonResponse({'message': 'private'}, 403);
      await expectLater(service.loadRsvp(eventId, session: session),
          throwsA(isA<PublicationFailure>()));
    });

    test(
        'RSVP invalid status is rejected, removal is scoped to owner and event',
        () async {
      final session = service.captureSession();
      addTearDown(session.close);
      await expectLater(service.setRsvp(session, eventId, 'invalid'),
          throwsA(isA<PublicationFailure>()));
      expect(requests, isEmpty);
      respond = (_) async => http.Response('', 204);
      await service.setRsvp(session, eventId, null);
      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.queryParameters,
          {'event_id': 'eq.$eventId', 'user_id': 'eq.$owner'});
    });
  });

  Future<void> composer(WidgetTester tester, FakeEventService service,
      {Future<Uint8List?> Function()? picker}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue(owner),
          eventServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
            home: CreateEventScreen(service: service, coverPicker: picker))));
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'Original event');
    await tester.tap(find.text('Газар сонгох'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixture venue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Огноо · цаг сонгох'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final future = DateTime.now().add(const Duration(days: 2));
    await tester.enterText(
        find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextField)),
        '${future.month.toString().padLeft(2, '0')}/${future.day.toString().padLeft(2, '0')}/${future.year}');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'cover picker blocks duplicate actions and handles plugin failure safely',
      (tester) async {
    final service = FakeEventService();
    final pending = Completer<Uint8List?>();
    var calls = 0;
    await composer(tester, service, picker: () {
      calls++;
      return pending.future;
    });
    await tester.tap(find.text('Cover зураг'));
    await tester.tap(find.text('Cover зураг'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse);
    pending.completeError(Exception('private path and token'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Зургийг нээж чадсангүй'), findsOneWidget);
    expect(find.textContaining('private path'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled, isTrue);
  });

  testWidgets('idle account change hides draft and closes owner venue picker',
      (tester) async {
    final service = FakeEventService();
    await composer(tester, service);
    await tester.enterText(find.byType(TextField).first, 'Private draft');
    service.changes
        .add(null); // Same-owner refresh does not invalidate the draft.
    await tester.pump();
    expect(find.text('Private draft'), findsOneWidget);
    await tester.tap(find.text('Газар сонгох'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture venue'), findsOneWidget);
    service.account = other;
    service.generation++;
    service.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Fixture venue'), findsNothing);
    expect(find.text('Private draft'), findsNothing);
    expect(find.textContaining('өмнөх нооргийг хаалаа'), findsOneWidget);
  });

  testWidgets(
      'auth stream failure hides draft and dismisses private venue sheet',
      (tester) async {
    final service = FakeEventService();
    await composer(tester, service);
    await tester.enterText(find.byType(TextField).first, 'Private draft');
    await tester.tap(find.text('Газар сонгох'));
    await tester.pumpAndSettle();
    service.changes.addError(Exception('fixture auth interruption'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture venue'), findsNothing);
    expect(find.text('Private draft'), findsNothing);
    expect(find.textContaining('өмнөх нооргийг хаалаа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'event uncertainty freezes draft and retries same row without another upload',
      (tester) async {
    final png =
        Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 4)));
    final pending = Completer<void>();
    final service = FakeEventService()..publishPending = pending;
    await composer(tester, service, picker: () async => png);
    await tester.tap(find.text('Cover зураг'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.text('Эвент нийтлэх'));
    await tester.tap(find.text('Эвент нийтлэх'));
    await tester.pump();
    expect(service.rows, hasLength(1));
    expect(service.uploads, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(service.rows.single['title'], 'Original event');
    expect((service.rows.single['starts_at'] as String).endsWith('Z'), isTrue);
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
        isFalse);
    await tester.tap(find.text('Дахин шалгах'));
    await tester.pumpAndSettle();
    expect(service.rows, hasLength(2));
    expect(service.rows[0], service.rows[1]);
    expect(service.uploads, 1);
  });

  testWidgets(
      'failed cover upload preserves draft and cannot publish an event without cover',
      (tester) async {
    final png =
        Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 4)));
    final service = FakeEventService()
      ..uploadFailure = const PublicationFailure('Зураг илгээгээгүй');
    await composer(tester, service, picker: () async => png);
    await tester.tap(find.text('Cover зураг'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.text('Эвент нийтлэх'));
    await tester.pumpAndSettle();
    expect(service.uploads, 1);
    expect(service.rows, isEmpty);
    expect(find.text('Зураг илгээгээгүй'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).enabled, isTrue);
  });

  testWidgets(
      'published event says it is in review and never claims it is public',
      (tester) async {
    final png =
        Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 4)));
    final service = FakeEventService()..publishSucceeds = true;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (context, _) => Scaffold(
              body: TextButton(
                  onPressed: () => context.push('/create'),
                  child: const Text('Open composer')))),
      GoRoute(
          path: '/create',
          builder: (_, __) => CreateEventScreen(
              service: service, coverPicker: () async => png)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue(owner),
          eventServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cover зураг'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.text('Эвент нийтлэх'));
    await tester.pumpAndSettle();
    expect(service.rows, hasLength(1));
    // Composer closed back to the opener; its snackbar is the only feedback.
    expect(find.text('Open composer'), findsOneWidget);
    expect(
        find.text('Эвентийг шалгалтад илгээлээ. '
            'Модератор баталсны дараа бусдад харагдана.'),
        findsOneWidget);
    expect(find.textContaining('нийтлэгдлээ'), findsNothing);
    expect(find.textContaining('Нийтлэгдлээ'), findsNothing);
    // A second, queued snackbar would only appear once the first times out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('нийтлэгдлээ'), findsNothing);
    expect(find.textContaining('Нийтлэгдлээ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account change during cover upload prevents event insert',
      (tester) async {
    final png =
        Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 4)));
    final pending = Completer<String>();
    final service = FakeEventService()..uploadPending = pending;
    await composer(tester, service, picker: () async => png);
    await tester.tap(find.text('Cover зураг'));
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await fillForm(tester);
    await tester.tap(find.text('Эвент нийтлэх'));
    await tester.pump();
    service.account = other;
    service.generation++;
    service.changes.add(null);
    pending.complete('https://fixture.test/upload.png');
    await tester.pumpAndSettle();
    expect(service.rows, isEmpty);
    expect(find.textContaining('өмнөх нооргийг хаалаа'), findsOneWidget);
  });

  Future<void> detail(WidgetTester tester, FakeEventService service,
      {StateProvider<String?>? account}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          eventServiceProvider.overrideWithValue(service),
          sessionUserIdProvider.overrideWith(
              (ref) => account == null ? owner : ref.watch(account)),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () => showEventDetailSheet(
                              context,
                              EventItem(
                                  id: eventId,
                                  title: 'Fixture event',
                                  startsAt: DateTime.utc(2027))),
                          child: const Text('Open'),
                        ))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('RSVP failure exposes retry without invented zero counts',
      (tester) async {
    final service = FakeEventService()..loadFailure = true;
    await detail(tester, service);
    expect(find.text('Оролцооны мэдээллийг ачаалж чадсангүй.'), findsOneWidget);
    expect(find.text('0 очно · 0 сонирхож байна'), findsNothing);
    await tester.tap(find.text('Очно'));
    expect(service.mutations, 0);
    service.loadFailure = false;
    await tester.tap(find.text('Дахин оролдох'));
    await tester.pumpAndSettle();
    expect(find.text('4 очно · 2 сонирхож байна'), findsOneWidget);
  });

  testWidgets('RSVP serializes double taps and waits for authoritative counts',
      (tester) async {
    final pending = Completer<void>();
    final service = FakeEventService()..mutationPending = pending;
    await detail(tester, service);
    await tester.tap(find.text('Очно  ·  4'));
    await tester.tap(find.text('Очно  ·  4'));
    await tester.pump();
    expect(service.mutations, 1);
    expect(find.text('4 очно · 2 сонирхож байна'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('5 очно · 2 сонирхож байна'), findsOneWidget);
  });
}
