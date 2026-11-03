import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:night_owl_ub/core/theme/app_fonts.dart';
import 'package:night_owl_ub/features/feed/screens/create_story_screen.dart';
import 'package:night_owl_ub/features/discovery/services/discovery_service.dart';
import 'package:night_owl_ub/features/map/providers/venue_story_activity_provider.dart';
import 'package:night_owl_ub/features/post/screens/create_post_screen.dart';
import 'package:night_owl_ub/features/post/services/content_publication.dart';
import 'package:night_owl_ub/features/post/utils/post_media.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const owner = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const postId = '20000000-0000-4000-8000-000000000001';

http.Response jsonResponse(Object? data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json'});

class DraftSession extends PublicationSession {
  bool active = true;
  @override
  String get ownerId => owner;
  @override
  String get token => 'captured-token';
  @override
  bool get isCurrent => active;
  @override
  void close() => active = false;
}

class ComposerService extends ContentPublicationService {
  final scope = DraftSession();
  final Uint8List imageBytes;
  final rows = <Map<String, dynamic>>[];
  int uploads = 0;
  Completer<String>? pendingUpload;
  Completer<void>? pendingPublish;
  Object? failure;
  ComposerService(this.imageBytes);
  @override
  PublicationSession captureSession() => scope;
  @override
  Future<Object> preparePostImage(PickedMediaFile media) async => imageBytes;
  @override
  Future<Uint8List> prepareStoryImage(Uint8List bytes) async => bytes;
  Future<String> upload() async {
    uploads++;
    if (pendingUpload != null) return await pendingUpload!.future;
    return 'https://fixture.test/media.png';
  }

  @override
  Future<String> uploadPost(PublicationSession session, Object blob,
          {required String path,
          required String contentType,
          void Function(double)? onProgress}) =>
      upload();
  @override
  Future<String> uploadStory(PublicationSession session, Uint8List bytes,
          {required String path, required String contentType}) =>
      upload();
  @override
  Future<void> publish(PublicationSession session, String table,
      Map<String, dynamic> row) async {
    rows.add(jsonDecode(jsonEncode(row)) as Map<String, dynamic>);
    await pendingPublish?.future;
    if (failure != null) throw failure!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppFonts.configure();
  final pixels = image.Image(width: 8, height: 8);
  final png = Uint8List.fromList(image.encodePng(pixels));

  group('publication service using isolated HTTP and auth', () {
    late SupabaseClient client;
    late ContentPublicationService service;
    late String initialToken;
    late List<http.Request> requests;
    late Future<http.Response> Function(http.Request) respond;

    Future<void> signIn(String id,
        {String token = 'token', bool expired = false}) async {
      await client.auth.setInitialSession(jsonEncode({
        'access_token': 'fixture.${base64Url.encode(utf8.encode(jsonEncode({
                  'sub': id,
                  'label': token,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 +
                      (expired ? -3600 : 3600),
                }))).replaceAll('=', '')}.fixture',
        'refresh_token': 'refresh-$token',
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
      final httpClient = MockClient((request) async {
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(response.bodyBytes, response.statusCode,
            headers: response.headers, request: request);
      });
      client = SupabaseClient('https://fixture.test', 'fixture-public',
          httpClient: httpClient,
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      service = ContentPublicationService(
          client: client,
          httpClient: httpClient,
          requestTimeout: const Duration(milliseconds: 100));
      await signIn(owner, token: 'owner-token');
      initialToken = client.auth.currentSession!.accessToken;
    });
    tearDown(() async => client.dispose());

    Map<String, dynamic> row() => {
          'id': postId,
          'user_id': owner,
          'caption': 'original draft',
          'media_url': 'https://fixture.test/media.png'
        };

    test('publish pins owner token and row ID', () async {
      final scope = service.captureSession();
      addTearDown(scope.close);
      await service.publish(scope, 'posts', row());
      expect(requests.single.headers['authorization'], 'Bearer $initialToken');
      expect(requests.single.headers['apikey'], 'fixture-public');
      expect(jsonDecode(requests.single.body), row());
    });

    test('publication uses its injected transport, not ambient auth transport',
        () async {
      final sent = <http.Request>[];
      final direct = MockClient((request) async {
        sent.add(request);
        return http.Response('', 201);
      });
      addTearDown(direct.close);
      service = ContentPublicationService(client: client, httpClient: direct);
      final scope = service.captureSession();
      addTearDown(scope.close);
      await service.publish(scope, 'posts', row());
      expect(sent.single.url.path, '/rest/v1/posts');
      expect(requests, isEmpty);
    });

    test('expired publication cannot refresh or sign out the ambient login',
        () async {
      await signIn(owner, expired: true);
      final initial = client.auth.currentSession!;
      expect(initial.isExpired, isTrue);
      respond = (_) async => jsonResponse({'message': 'expired fixture'}, 401);
      final scope = service.captureSession();
      addTearDown(scope.close);
      await expectLater(service.publish(scope, 'posts', row()),
          throwsA(isA<PublicationFailure>()));
      expect(requests.single.url.path, '/rest/v1/posts');
      expect(client.auth.currentSession, same(initial));
    });

    test('a late insert response cannot modify a newer login', () async {
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      final scope = service.captureSession();
      addTearDown(scope.close);
      final assertion = expectLater(service.publish(scope, 'posts', row()),
          throwsA(isA<PublicationFailure>()));
      await Future<void>.delayed(Duration.zero);
      await signIn(other, token: 'other-token');
      final newer = client.auth.currentSession;
      pending.complete(http.Response('', 201));
      await assertion;
      expect(requests.single.headers['authorization'], 'Bearer $initialToken');
      expect(client.auth.currentSession, same(newer));
    });

    test('story uploads replace inherited header casing with the draft token',
        () async {
      client.auth.headers['authorization'] = 'Bearer wrong-fixture-token';
      client.auth.headers['content-type'] = 'text/plain';
      final scope = service.captureSession();
      addTearDown(scope.close);
      await service.uploadStory(scope, png,
          path: '$owner/$postId.png', contentType: 'image/png');
      expect(requests.single.headers['authorization'], 'Bearer $initialToken');
      expect(requests.single.headers['content-type'], 'image/png');
      expect(requests.single.headers['apikey'], 'fixture-public');
    });

    test(
        'lost response retry recovers exactly the original row without another ID',
        () async {
      var postCalls = 0;
      respond = (request) async {
        if (request.method == 'POST') {
          if (++postCalls == 1) {
            throw const SocketException('private-token-and-url');
          }
          return jsonResponse(
              {'code': '23505', 'message': 'duplicate key'}, 409);
        }
        expect(request.url.queryParameters['id'], 'eq.$postId');
        expect(request.url.queryParameters['user_id'], 'eq.$owner');
        return jsonResponse([
          {'id': postId, 'user_id': owner}
        ]);
      };
      final scope = service.captureSession();
      addTearDown(scope.close);
      await expectLater(
          service.publish(scope, 'posts', row()),
          throwsA(isA<PublicationFailure>().having((e) => e.message,
              'safe uncertainty', contains('Нийтлэгдсэн байж болно'))));
      await service.publish(scope, 'posts', row());
      expect(
          requests.where((r) => r.method == 'POST').map((r) => r.body).toSet(),
          hasLength(1));
    });

    for (final existing in [
      <Object>[],
      [
        {'id': postId, 'user_id': other}
      ],
      [
        {'id': 'wrong-id', 'user_id': owner}
      ],
      [
        {'id': postId, 'user_id': owner},
        {'id': postId, 'user_id': other}
      ]
    ]) {
      test(
          'duplicate recovery never accepts missing or wrong-owned row $existing',
          () async {
        respond = (request) async => request.method == 'POST'
            ? jsonResponse({'code': '23505', 'message': 'duplicate'}, 409)
            : jsonResponse(existing);
        final scope = service.captureSession();
        addTearDown(scope.close);
        await expectLater(service.publish(scope, 'stories', row()),
            throwsA(isA<PublicationFailure>()));
      });
    }

    test(
        'account switch and switch back permanently invalidate the original draft',
        () async {
      final scope = service.captureSession();
      addTearDown(scope.close);
      await signIn(other, token: 'other-token');
      await signIn(owner, token: 'new-owner-token');
      expect(scope.isCurrent, isFalse);
      await expectLater(service.publish(scope, 'posts', row()),
          throwsA(isA<PublicationFailure>()));
      expect(requests, isEmpty);
    });

    test(
        'session change during upload rejects late result and keeps original token',
        () async {
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      final scope = service.captureSession();
      addTearDown(scope.close);
      final uploading = service.uploadStory(scope, png,
          path: '$owner/$postId.png', contentType: 'image/png');
      final assertion =
          expectLater(uploading, throwsA(isA<PublicationFailure>()));
      await Future<void>.delayed(Duration.zero);
      await signIn(other, token: 'other-token');
      pending.complete(http.Response('', 200));
      await assertion;
      expect(requests.single.headers['authorization'], 'Bearer $initialToken');
    });

    test('foreign owner payload is rejected before network', () async {
      final scope = service.captureSession();
      addTearDown(scope.close);
      await expectLater(
          service.publish(scope, 'posts', {...row(), 'user_id': other}),
          throwsA(isA<PublicationFailure>()));
      expect(requests, isEmpty);
    });

    test('unknown response and HTTP timeout are sanitized', () async {
      respond = (_) => Completer<http.Response>().future;
      final scope = service.captureSession();
      addTearDown(scope.close);
      await expectLater(
          service.publish(scope, 'stories', row()),
          throwsA(isA<PublicationFailure>().having((e) => e.message,
              'uncertainty', contains('Нийтлэгдсэн байж болно'))));
    });
  });

  test('image MIME identifies actual bytes and rejects unsupported data', () {
    expect(ContentPublicationService.imageType(png),
        (ext: 'png', mime: 'image/png'));
    expect(
        ContentPublicationService.imageType(
            Uint8List.fromList(image.encodeJpg(pixels))),
        (ext: 'jpg', mime: 'image/jpeg'));
    expect(
        () =>
            ContentPublicationService.imageType(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<PublicationFailure>()));
  });

  group('composer draft and async lifecycle', () {
    late Directory temp;
    late PickedMediaFile media;
    late ComposerService publisher;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('nightowl-compose-test-');
      final path = '${temp.path}/photo.png';
      await File(path).writeAsBytes(png);
      media = PickedMediaFile(null, path, false);
      publisher = ComposerService(png);
    });
    tearDown(() async {
      await temp.delete(recursive: true);
    });
    Future<void> pump(WidgetTester tester, Widget screen) async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: screen)));
      await tester.pumpAndSettle();
    }

    Future<void> pickPost(WidgetTester tester) async {
      await tester.tap(find.text('Зураг (10 хүртэл) эсвэл видео сонгох'));
      await tester.pumpAndSettle();
    }

    Future<void> pickStoryImage(WidgetTester tester) async {
      await tester.tap(find.text('Зургийн сан'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    final storyVenues = <JsonRow>[
      {'ref': other, 'venue_id': other, 'name': 'Community газар'},
      {'ref': 'osm:node:123', 'name': 'Газрын зураг дахь газар'},
    ];
    Future<List<JsonRow>> storyVenueLoader(
            {required String query,
            required int offset,
            required int limit}) async =>
        storyVenues;

    Future<void> chooseStoryVenue(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const ValueKey('story-location-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'story location can change and be removed before optional publish',
        (tester) async {
      publisher.failure = const PublicationFailure('fixture publish error');
      await pump(
          tester,
          CreateStoryScreen(
              publicationService: publisher,
              imagePicker: () async => png,
              venueLoader: storyVenueLoader));
      await pickStoryImage(tester);
      await chooseStoryVenue(tester, 'Community газар');
      expect(find.text('Community газар'), findsOneWidget);
      await chooseStoryVenue(tester, 'Газрын зураг дахь газар');
      expect(find.text('Community газар'), findsNothing);
      expect(find.text('Газрын зураг дахь газар'), findsOneWidget);
      await tester.tap(find.byTooltip('Байршлыг хасах'));
      await tester.pumpAndSettle();
      expect(find.text('Байршил нэмэх (сонголтоор)'), findsOneWidget);
      await tester.tap(find.text('Story-д хуваалцах'));
      await tester.pumpAndSettle();
      expect(publisher.rows, hasLength(1));
      expect(publisher.rows.single.containsKey('venue_ref'), isFalse);
      expect(publisher.rows.single.containsKey('venue_id'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('OSM story location freezes canonical ref across publish retry',
        (tester) async {
      publisher.failure = const PublicationFailure('fixture publish error');
      await pump(
          tester,
          CreateStoryScreen(
              publicationService: publisher,
              imagePicker: () async => png,
              venueLoader: storyVenueLoader));
      await pickStoryImage(tester);
      await chooseStoryVenue(tester, 'Газрын зураг дахь газар');
      await tester.tap(find.text('Story-д хуваалцах'));
      await tester.pumpAndSettle();
      expect(publisher.rows.single['venue_ref'], 'osm:node:123');
      expect(publisher.rows.single.containsKey('venue_id'), isFalse);
      final remove = tester.widget<IconButton>(find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Байршлыг хасах'));
      expect(remove.onPressed, isNull);
      await tester.tap(find.text('Дахин шалгах'));
      await tester.pumpAndSettle();
      expect(publisher.uploads, 1);
      expect(publisher.rows, hasLength(2));
      expect(publisher.rows[0], publisher.rows[1]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('successful community location publish refreshes map activity',
        (tester) async {
      var loads = 0;
      final container = ProviderContainer(overrides: [
        venueStoryActivityProvider.overrideWith((ref) async {
          loads++;
          return {};
        }),
      ]);
      addTearDown(container.dispose);
      final activity = container.listen(venueStoryActivityProvider, (_, __) {});
      addTearDown(activity.close);
      await container.read(venueStoryActivityProvider.future);
      final router = GoRouter(initialLocation: '/story', routes: [
        GoRoute(
            path: '/story',
            builder: (_, __) => CreateStoryScreen(
                publicationService: publisher,
                imagePicker: () async => png,
                venueLoader: storyVenueLoader)),
        GoRoute(
            path: '/feed',
            builder: (_, __) => const Scaffold(body: Text('Feed fixture'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      await pickStoryImage(tester);
      await chooseStoryVenue(tester, 'Community газар');
      await tester.tap(find.text('Story-д хуваалцах'));
      await tester.pumpAndSettle();
      expect(publisher.rows.single['venue_ref'], other);
      expect(publisher.rows.single['venue_id'], other);
      expect(publisher.uploads, 1);
      expect(loads, 2);
      expect(find.text('Feed fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'account switch while choosing location cannot attach or publish',
        (tester) async {
      final locations = Completer<List<JsonRow>>();
      Future<List<JsonRow>> loader(
              {required String query,
              required int offset,
              required int limit}) =>
          locations.future;
      await pump(
          tester,
          CreateStoryScreen(
              publicationService: publisher,
              imagePicker: () async => png,
              venueLoader: loader));
      await pickStoryImage(tester);
      await tester.tap(find.byKey(const ValueKey('story-location-picker')));
      await tester.pump();
      publisher.scope.active = false;
      locations.complete(storyVenues);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community газар'));
      await tester.pumpAndSettle();
      expect(find.text('Community газар'), findsNothing);
      await tester.tap(find.text('Story-д хуваалцах'));
      await tester.pumpAndSettle();
      expect(publisher.rows, isEmpty);
      expect(publisher.uploads, 0);
      expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'post picker prevents duplicate opens and ignores completion after dispose',
        (tester) async {
      final pending = Completer<List<PickedMediaFile>>();
      var picks = 0;
      await pump(
          tester,
          CreatePostScreen(
              publicationService: publisher,
              mediaPicker: ({bool multiple = true}) {
                picks++;
                return pending.future;
              }));
      await tester.tap(find.text('Зураг (10 хүртэл) эсвэл видео сонгох'));
      await tester.tap(find.text('Зураг (10 хүртэл) эсвэл видео сонгох'));
      expect(picks, 1);
      await tester.pumpWidget(const SizedBox());
      pending.complete([media]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'post draft cancel preserves caption and pending insert retries frozen row once',
        (tester) async {
      publisher.pendingPublish = Completer<void>();
      publisher.failure =
          const PublicationFailure('Нийтлэгдсэн байж болно. Дахин шалгана уу.');
      await pump(
          tester,
          CreatePostScreen(
              publicationService: publisher,
              mediaPicker: ({bool multiple = true}) async => [media]));
      await pickPost(tester);
      await tester.enterText(
          find.byType(TextField).first, 'my original caption');
      await tester.tap(find.byTooltip('Хаах'));
      await tester.pumpAndSettle();
      expect(find.text('Нооргоос гарах уу?'), findsOneWidget);
      await tester.tap(find.text('Үргэлжлүүлэх'));
      await tester.pumpAndSettle();
      expect(find.text('my original caption'), findsOneWidget);
      final share = find.widgetWithText(TextButton, 'Хуваалцах');
      await tester.tap(share);
      await tester.tap(share);
      await tester.pump();
      expect(publisher.uploads, 1);
      expect(publisher.rows, hasLength(1));
      expect(tester.widget<TextField>(find.byType(TextField).first).enabled,
          isFalse);
      publisher.pendingPublish!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Дахин шалгах'));
      await tester.pumpAndSettle();
      expect(publisher.uploads, 1);
      expect(publisher.rows, hasLength(2));
      expect(publisher.rows[0], publisher.rows[1]);
      expect(publisher.rows.last['caption'], 'my original caption');
      expect(tester.takeException(), isNull);
    });

    testWidgets('account switch during post upload never inserts a row',
        (tester) async {
      publisher.pendingUpload = Completer<String>();
      await pump(
          tester,
          CreatePostScreen(
              publicationService: publisher,
              mediaPicker: ({bool multiple = true}) async => [media]));
      await pickPost(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Хуваалцах'));
      await tester.pump();
      publisher.scope.active = false;
      publisher.pendingUpload!.complete('https://fixture.test/media.png');
      await tester.pumpAndSettle();
      expect(publisher.rows, isEmpty);
      expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'story upload preserves media on error and freezes a single publish attempt',
        (tester) async {
      publisher.pendingPublish = Completer<void>();
      publisher.failure =
          const PublicationFailure('Нийтлэгдсэн байж болно. Дахин шалгана уу.');
      await pump(
          tester,
          CreateStoryScreen(
              publicationService: publisher, imagePicker: () async => png));
      await tester.tap(find.text('Зургийн сан'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Story-д хуваалцах'), findsOneWidget);
      await tester.tap(find.text('Story-д хуваалцах'));
      await tester.tap(find.text('Story-д хуваалцах'));
      await tester.pump();
      expect(publisher.uploads, 1);
      expect(publisher.rows, hasLength(1));
      publisher.pendingPublish!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      await tester.tap(find.text('Дахин шалгах'));
      await tester.pumpAndSettle();
      expect(publisher.uploads, 1);
      expect(publisher.rows, hasLength(2));
      expect(publisher.rows[0], publisher.rows[1]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'small story picker wraps at large text and late picker result is ignored',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final pending = Completer<Uint8List?>();
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: MediaQuery(
                  data: const MediaQueryData(
                      size: Size(320, 640), textScaler: TextScaler.linear(1.6)),
                  child: CreateStoryScreen(
                      publicationService: publisher,
                      imagePicker: () => pending.future)))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Зургийн сан'));
      await tester.pumpWidget(const SizedBox());
      pending.complete(png);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
