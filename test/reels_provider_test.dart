import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:night_owl_ub/features/feed/providers/reels_provider.dart';

Map<String, dynamic> reel(String id, String? url, {String type = 'video'}) => {
      'id': id,
      'user_id': 'author-$id',
      'media_url': url,
      'media_type': type,
    };

void main() {
  test('video filter reaches the server before its 50-video limit', () async {
    late Uri requested;
    final client = SupabaseClient('https://example.test', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requested = request.url;
      return http.Response(
          jsonEncode([
            reel('older-video', 'https://media.test/old.mp4', type: 'image'),
            reel('wrong-extension-match', 'https://media.test/photo.mp4.jpg',
                type: 'image'),
            reel('typed-video', 'https://media.test/opaque-media'),
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }));
    addTearDown(client.dispose);
    final rows = await ReelsRepository(client).load();
    expect(requested.queryParameters['or'], contains('media_type.eq.video'));
    expect(requested.queryParameters['or'], contains('media_url.ilike.%.mp4*'));
    expect(requested.queryParameters['limit'], '50');
    expect(requested.queryParameters['order'],
        'created_at.desc.nullslast,id.desc.nullslast');
    expect(rows.map((row) => row['id']), ['older-video', 'typed-video']);
  });

  test('normalization recognizes legacy signed URLs and rejects non-video rows',
      () {
    expect(
        ReelsRepository.normalize(reel(
            'signed', 'https://media.test/CLIP.MP4?token=opaque',
            type: 'image'))?['id'],
        'signed');
    expect(
        ReelsRepository.normalize(
            reel('photo', 'https://media.test/image.jpg', type: 'image')),
        isNull);
    expect(ReelsRepository.normalize(reel('empty', null)), isNull);
    expect(ReelsRepository.normalize(reel('invalid', 'javascript:alert(1)')),
        isNull);
    expect(
        ReelsRepository.normalize({
          ...reel('array', null),
          'media_urls': ['https://media.test/clip.webm']
        })?['media_url'],
        'https://media.test/clip.webm');
  });

  test('Following uses a guarded server query, not the global newest page',
      () async {
    final client = SupabaseClient('https://example.test', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/get_following_reels');
      expect(jsonDecode(request.body), {'p_limit': 50});
      return http.Response(
          jsonEncode([
            reel('followed-old', 'https://media.test/old.mp4'),
            reel('bad-media', 'https://media.test/photo.jpg'),
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }));
    addTearDown(client.dispose);
    final rows = await ReelsRepository(client).loadFollowing();
    expect(rows.map((row) => row['id']), ['followed-old']);
  });

  test('a failed Following query never falls back to unrelated public clips',
      () async {
    var requests = 0;
    final client = SupabaseClient('https://example.test', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requests++;
      expect(request.url.path, '/rest/v1/rpc/get_following_reels');
      return http.Response('{"code":"42501","message":"Denied"}', 403,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);
    await expectLater(ReelsRepository(client).loadFollowing(),
        throwsA(isA<PostgrestException>()));
    expect(requests, 1);
  });

  test('selected ID fetch finds an older clip outside the latest-page query',
      () async {
    late Uri requested;
    final client = SupabaseClient('https://example.test', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      requested = request.url;
      return http.Response(
          jsonEncode([reel('selected-old', 'https://media.test/selected.mov')]),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }));
    addTearDown(client.dispose);
    final selected = await ReelsRepository(client).find('selected-old');
    expect(requested.queryParameters['id'], 'eq.selected-old');
    expect(requested.queryParameters.containsKey('limit'), isFalse);
    expect(selected?['id'], 'selected-old');
  });

  test(
      'carousel chooses explicit video before a photo cover or opaque fallback',
      () {
    for (final cover in ['cover.JPG?signature=opaque', 'opaque-cover']) {
      expect(
          ReelsRepository.normalize({
            ...reel('carousel', 'https://media.test/$cover'),
            'media_urls': ['https://media.test/actual-clip.mp4'],
          })?['media_url'],
          'https://media.test/actual-clip.mp4');
    }
    for (final extension in [
      'jpg',
      'JPEG',
      'png',
      'gif',
      'webp',
      'svg',
      'avif',
      'heic'
    ]) {
      expect(
          ReelsRepository.normalize(
              reel('photo', 'https://media.test/photo.$extension?download=1')),
          isNull);
    }
    expect(
        ReelsRepository.normalize(
            reel('opaque', 'https://media.test/video-stream'))?['media_url'],
        'https://media.test/video-stream');
  });

  test('server failure stays an error instead of becoming an empty gallery',
      () async {
    final client = SupabaseClient('https://example.test', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async => http.Response(
            '{"message":"backend unavailable","code":"XX000"}', 400,
            headers: {'content-type': 'application/json'}, request: request)));
    addTearDown(client.dispose);
    await expectLater(
        ReelsRepository(client).load(), throwsA(isA<PostgrestException>()));
  });
}
