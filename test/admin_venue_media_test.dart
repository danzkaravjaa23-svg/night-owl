import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/admin/providers/admin_console_provider.dart';
import 'package:night_owl_ub/features/admin/services/admin_console_service.dart';
import 'package:night_owl_ub/features/admin/services/admin_venue_media.dart';
import 'admin_console_fixture.dart';

void main() {
  final bytes = Uint8List.fromList([255, 216, 255, 224, 0]);
  late SupabaseClient client;
  late AdminFixtureSession session;
  late AdminConsoleAccess access;
  setUp(() {
    client = SupabaseClient(
        'https://admin-media.example.test', 'public-fixture-key');
    session = AdminFixtureSession();
    access = AdminConsoleAccess(AdminConsoleService(client: client), session,
        const AdminConsoleSummary(adminFixtureOwner, {}));
  });
  tearDown(() async {
    session.close();
    await client.dispose();
  });

  test('venue image credentials and object path belong to captured admin',
      () async {
    final upload = AdminVenueMedia(httpClient: MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer fixture-captured-token');
      expect(request.headers['content-type'], 'image/jpeg');
      expect(request.headers['x-upsert'], 'false');
      expect(request.url.host, 'admin-media.example.test');
      expect(request.url.path,
          startsWith('/storage/v1/object/venues/$adminFixtureOwner/review_'));
      expect(request.bodyBytes, bytes);
      return http.Response('{}', 200);
    }));
    final url = await upload.upload(access, bytes);
    expect(
        url,
        startsWith(
            'https://admin-media.example.test/storage/v1/object/public/venues/$adminFixtureOwner/'));
  });
  test('obsolete editor cannot start an upload', () async {
    session.invalidate(const AdminConsoleFailure('session_changed'));
    var requests = 0;
    final upload = AdminVenueMedia(httpClient: MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    await expectLater(
        upload.upload(access, bytes), throwsA(isA<AdminConsoleFailure>()));
    expect(requests, 0);
  });
  test('late image result is rejected after account change', () async {
    final pending = Completer<http.Response>();
    final upload =
        AdminVenueMedia(httpClient: MockClient((_) => pending.future));
    final result = upload.upload(access, bytes);
    final expectation = expectLater(
        result,
        throwsA(isA<AdminConsoleFailure>()
            .having((e) => e.code, 'code', 'session_changed')));
    session.invalidate(const AdminConsoleFailure('session_changed'));
    pending.complete(http.Response('{}', 200));
    await expectation;
  });
  test('storage failure does not return an image URL', () async {
    final upload = AdminVenueMedia(
        httpClient: MockClient((_) async => http.Response('{}', 403)));
    await expectLater(
        upload.upload(access, bytes), throwsA(isA<AdminConsoleFailure>()));
  });
}
