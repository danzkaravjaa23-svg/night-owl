import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/core/theme/app_fonts.dart';
import 'package:night_owl_ub/core/widgets/content_review_notice.dart';
import 'package:night_owl_ub/features/post/services/content_publication.dart';
import 'package:night_owl_ub/features/profile/services/report_submission_service.dart';
import 'package:night_owl_ub/features/profile/widgets/block_report_sheet.dart';
import 'package:night_owl_ub/models/post.dart';
import 'package:night_owl_ub/models/story.dart';
import 'package:night_owl_ub/models/comment.dart';
import 'package:night_owl_ub/models/user_profile.dart';

const _receipt = '20000000-0000-4000-8000-000000000001';

class _Session extends PublicationSession {
  bool active = true;
  @override
  String get ownerId => 'owner';
  @override
  String get token => 'captured-token';
  @override
  bool get isCurrent => active;
  @override
  void close() => active = false;
}

class _Reports extends ReportSubmissionService {
  final session = _Session();
  final changes = StreamController<void>.broadcast();
  int calls = 0;
  Completer<void>? pending;
  bool fail = false;
  String? details;
  @override
  PublicationSession captureSession() => session;
  @override
  Stream<void> get sessionChanges => changes.stream;
  @override
  Future<void> submit(
    PublicationSession session, {
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    session.check();
    calls++;
    this.details = details;
    await pending?.future;
    session.check();
    if (fail) throw const PublicationFailure('Дахин оролдоно уу.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppFonts.configure();
  group('report transport pins the captured account', () {
    late SupabaseClient client;
    late _Session session;
    late ReportSubmissionService service;
    final sent = <http.Request>[];
    late Future<http.Response> Function(http.Request) response;
    setUp(() {
      sent.clear();
      session = _Session();
      client = SupabaseClient('https://fixture.test', 'public-fixture-key');
      response = (_) async => http.Response(jsonEncode(_receipt), 200);
      service = ReportSubmissionService(
          client: client,
          httpClient: MockClient((request) async {
            sent.add(request);
            return response(request);
          }));
    });
    tearDown(() async {
      session.close();
      await client.dispose();
    });
    test(
        'all surfaced target types use exact references and no copied message body',
        () async {
      for (final kind in [
        'post',
        'user',
        'comment',
        'venue',
        'story',
        'message',
        'group_message',
        'event',
        'review',
        'note',
        'collection'
      ]) {
        await service.submit(session,
            targetType: kind,
            targetId: _receipt,
            reason: 'harassment',
            details: '  context  ');
        final request = sent.last;
        expect(request.url.path, '/rest/v1/rpc/report_ugc');
        expect(request.headers['authorization'], 'Bearer captured-token');
        expect(request.headers['apikey'], 'public-fixture-key');
        expect(jsonDecode(request.body), {
          'p_target_type': kind,
          'p_target_id': _receipt,
          'p_reason': 'harassment',
          'p_details': 'context'
        });
      }
    });
    test('invalid type/reason/oversized details never reach transport',
        () async {
      for (final args in [
        ('unknown', 'spam', ''),
        ('post', 'unknown', ''),
        ('post', 'spam', 'x' * 2001),
      ]) {
        await expectLater(
            service.submit(session,
                targetType: args.$1,
                targetId: _receipt,
                reason: args.$2,
                details: args.$3),
            throwsA(isA<PublicationFailure>()));
      }
      expect(sent, isEmpty);
    });
    test(
        'server denial and duplicate results never become success or expose raw error',
        () async {
      for (final code in ['42501', '40001', 'P0002']) {
        response = (_) async => http.Response(
            jsonEncode({'code': code, 'message': 'private-body-and-token'}),
            403);
        await expectLater(
            service.submit(session,
                targetType: 'message', targetId: _receipt, reason: 'spam'),
            throwsA(isA<PublicationFailure>().having((e) => e.message,
                'safe message', isNot(contains('private-body')))));
      }
    });
    test('malformed receipt cannot claim a report was accepted', () async {
      response = (_) async => http.Response('[]', 200);
      await expectLater(
          service.submit(session,
              targetType: 'post', targetId: _receipt, reason: 'spam'),
          throwsA(isA<PublicationFailure>()));
    });
    test('account change during a response rejects old success', () async {
      final pending = Completer<http.Response>();
      response = (_) => pending.future;
      final result = expectLater(
          service.submit(session,
              targetType: 'story', targetId: _receipt, reason: 'spam'),
          throwsA(isA<PublicationFailure>()));
      await Future<void>.delayed(Duration.zero);
      session.active = false;
      pending.complete(http.Response(jsonEncode(_receipt), 200));
      await result;
      expect(sent.single.headers['authorization'], 'Bearer captured-token');
    });
  });

  Future<void> open(WidgetTester tester, _Reports service,
      {String kind = 'message'}) async {
    addTearDown(service.changes.close);
    await tester.pumpWidget(ProviderScope(
        overrides: [reportSubmissionServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showReportSheet(context,
                            targetType: kind, targetId: _receipt),
                        child: const Text('Open')))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Спам / хуурамч'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    final button = find.text('Модераторт илгээх');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets(
      'exact-message disclosure and explicit submission prevent accidental report',
      (tester) async {
    final service = _Reports()..pending = Completer<void>();
    await open(tester, service);
    expect(
        find.textContaining('Ярианы бусад мессежийг нээхгүй'), findsOneWidget);
    expect(service.calls, 0);
    await submit(tester);
    expect(service.calls, 1);
    expect(find.text('Илгээж байна…'), findsOneWidget);
    service.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Мэдээлэл хүлээн авлаа'), findsOneWidget);
    expect(service.session.active, isFalse);
  });
  testWidgets('failed report retains entered details and can retry',
      (tester) async {
    final service = _Reports()..fail = true;
    await open(tester, service, kind: 'story');
    await tester.enterText(find.byType(TextField), 'Миний тайлбар');
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Миний тайлбар'), findsOneWidget);
    expect(find.text('Дахин оролдоно уу.'), findsOneWidget);
    service.fail = false;
    await submit(tester);
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(service.details, 'Миний тайлбар');
  });
  testWidgets('account switch before report submit keeps old form inert',
      (tester) async {
    final service = _Reports();
    await open(tester, service);
    service.session.active = false;
    await submit(tester);
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
    expect(find.textContaining('Мэдээлэл хүлээн авлаа'), findsNothing);
  });
  testWidgets('auth event clears the previous account report draft immediately',
      (tester) async {
    final service = _Reports();
    await open(tester, service);
    await tester.enterText(find.byType(TextField), 'private draft');
    service.session.active = false;
    service.changes.add(null);
    await tester.pumpAndSettle();
    expect(find.text('private draft'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((widget) => widget is FilledButton))
            .onPressed,
        isNull);
    expect(find.textContaining('Нэвтрэх хаяг өөрчлөгдсөн'), findsOneWidget);
    expect(service.calls, 0);
  });
  test(
      'moderation state survives parsing and local edits without approval escalation',
      () {
    final post = Post.fromJson(
        {'id': 'p', 'user_id': 'u', 'moderation_status': 'pending'});
    expect(post.copyWith(caption: 'edited').moderationStatus, 'pending');
    expect(
        Story.fromJson({
          'id': 's',
          'user_id': 'u',
          'media_url': 'fixture',
          'moderation_status': 'rejected'
        }).moderationStatus,
        'rejected');
    expect(
        Comment.fromJson({
          'id': 'c',
          'user_id': 'u',
          'post_id': 'p',
          'body': 'text',
          'moderation_status': 'pending'
        }).moderationStatus,
        'pending');
    final profile =
        UserProfile.fromJson({'id': 'u', 'moderation_status': 'pending'});
    expect(profile.copyWith(bio: 'edit').moderationStatus, 'pending');
    expect(profile.toJson().containsKey('moderation_status'), isFalse);
  });
  testWidgets('pending and rejected notices fit narrow large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Column(children: [
                  ContentReviewNotice(status: 'pending'),
                  ContentReviewNotice(status: 'rejected'),
                  ContentReviewNotice(status: 'pending', profile: true),
                  ContentReviewNotice(status: 'approved'),
                ])))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Баталсны дараа бусдад'), findsOneWidget);
  });
}
