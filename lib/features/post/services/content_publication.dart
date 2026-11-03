import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/image_compress.dart';
import '../utils/post_media.dart';

class PublicationFailure implements Exception {
  final String message;
  const PublicationFailure(this.message);
  @override
  String toString() => message;
}

abstract class PublicationSession {
  String? get ownerId;
  String get token;
  bool get isCurrent;
  void close();

  void check() {
    if (!isCurrent) {
      throw const PublicationFailure(
          'Нэвтрэх хаяг өөрчлөгдсөн байна. Энэ нооргийг өөр хаягаар нийтлэхгүй.');
    }
  }
}

class _AuthPublicationSession extends PublicationSession {
  final SupabaseClient client;
  late final String? _owner;
  Session? _allowed;
  bool _stale = false;
  late final StreamSubscription<AuthState> _subscription;

  _AuthPublicationSession(this.client) {
    final captured = client.auth.currentSession;
    _allowed = captured;
    _owner = captured?.user.id;
    var first = true;
    _subscription = client.auth.onAuthStateChange.listen((state) {
      if (first && identical(state.session, captured)) {
        first = false;
        return;
      }
      first = false;
      if (!_stale &&
          (state.event == AuthChangeEvent.tokenRefreshed ||
              state.event == AuthChangeEvent.userUpdated) &&
          state.session?.user.id == _owner) {
        _allowed = state.session;
      } else {
        _stale = true;
      }
    }, onError: (Object _) => _stale = true);
  }

  @override
  String? get ownerId => _owner;
  @override
  String get token => _allowed?.accessToken ?? '';
  @override
  bool get isCurrent =>
      !_stale &&
      _owner != null &&
      client.auth.currentUser?.id == _owner &&
      identical(client.auth.currentSession, _allowed);
  @override
  void close() {
    _stale = true;
    unawaited(_subscription.cancel());
  }
}

/// A client-assigned row ID makes a retry after a lost response recover the
/// original publication instead of creating another post/story.
class ContentPublicationService {
  final SupabaseClient? _client;
  final http.Client? _httpClient;
  final Duration requestTimeout;
  ContentPublicationService(
      {SupabaseClient? client,
      http.Client? httpClient,
      this.requestTimeout = const Duration(seconds: 60)})
      : _client = client,
        _httpClient = httpClient;

  SupabaseClient get client => _client ?? SupabaseService.client;
  PublicationSession captureSession() => _AuthPublicationSession(client);

  Future<Object> preparePostImage(PickedMediaFile media) =>
      resizeImageForUpload(media);
  Future<Uint8List> prepareStoryImage(Uint8List bytes) => compressToJpeg(bytes);

  static ({String ext, String mime}) imageType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return (ext: 'jpg', mime: 'image/jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      return (ext: 'png', mime: 'image/png');
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return (ext: 'webp', mime: 'image/webp');
    }
    if (bytes.length >= 6 &&
        const {'GIF87a', 'GIF89a'}
            .contains(String.fromCharCodes(bytes.sublist(0, 6)))) {
      return (ext: 'gif', mime: 'image/gif');
    }
    throw const PublicationFailure(
        'Зургийн форматыг таньсангүй. JPG эсвэл PNG зураг сонгоно уу.');
  }

  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String mediaUrl(String bucket, String path) =>
      client.storage.from(bucket).getPublicUrl(path);

  Map<String, String> _headers(PublicationSession session,
      {required String contentType}) {
    // Header names are case-insensitive. Drop inherited variants before
    // pinning the draft's token; a newer login must never supply credentials.
    return Map<String, String>.from(client.auth.headers)
      ..removeWhere((key, _) =>
          key.toLowerCase() == 'authorization' ||
          key.toLowerCase() == 'content-type')
      ..addAll({
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': contentType,
      });
  }

  Future<String> uploadPost(PublicationSession session, Object blob,
      {required String path,
      required String contentType,
      void Function(double)? onProgress}) async {
    session.check();
    if (blobSize(blob) <= 0 ||
        blobSize(blob) > 50 * 1024 * 1024 ||
        !path.startsWith('${session.ownerId}/')) {
      throw const PublicationFailure('Файл хоосон эсвэл 50MB-ээс том байна.');
    }
    final root = client.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '');
    try {
      await uploadBlobWithProgress(
          blob: blob,
          url: '$root/storage/v1/object/posts/$path',
          token: session.token,
          mime: contentType,
          onProgress: onProgress);
      session.check();
      return mediaUrl('posts', path);
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const PublicationFailure(
          'Медиа илгээж чадсангүй. Ноорог энэ дэлгэцэд хэвээр байна; холболтоо шалгаад дахин оролдоно уу.');
    }
  }

  Future<String> uploadStory(PublicationSession session, Uint8List bytes,
      {required String path, required String contentType}) async {
    session.check();
    if (bytes.isEmpty ||
        bytes.length > 50 * 1024 * 1024 ||
        !path.startsWith('${session.ownerId}/')) {
      throw const PublicationFailure('Файл хоосон эсвэл 50MB-ээс том байна.');
    }
    final connection = _httpClient ?? http.Client();
    try {
      final root = client.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '');
      final response = await connection
          .post(
            Uri.parse('$root/storage/v1/object/stories/$path'),
            headers: _headers(session, contentType: contentType)
              ..['x-upsert'] = 'true',
            body: bytes,
          )
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const PublicationFailure(
            'Медиа илгээж чадсангүй. Ноорог энэ дэлгэцэд хэвээр байна; дахин оролдоно уу.');
      }
      return mediaUrl('stories', path);
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const PublicationFailure(
          'Медиа илгээж чадсангүй. Ноорог энэ дэлгэцэд хэвээр байна; холболтоо шалгаад дахин оролдоно уу.');
    } finally {
      if (_httpClient == null) connection.close();
    }
  }

  Future<void> publish(PublicationSession session, String table,
      Map<String, dynamic> row) async {
    session.check();
    if (!const {'posts', 'stories'}.contains(table) ||
        row['user_id'] != session.ownerId ||
        row['id'] is! String) {
      throw const PublicationFailure('Нийтлэх мэдээлэл буруу байна.');
    }
    final connection = _httpClient ?? http.Client();
    try {
      // Supabase's shared REST transport refreshes the ambient login even
      // when Authorization is explicitly set. A late SDK refresh can replace
      // a newer login, and would still send our old pinned header afterwards.
      // Like uploads, these owner-scoped requests use the raw HTTP transport.
      final endpoint = Uri.parse('${client.rest.url}/$table');
      final response = await connection
          .post(endpoint,
              headers: _headers(session, contentType: 'application/json')
                ..['Prefer'] = 'return=minimal',
              body: jsonEncode(row))
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = jsonDecode(response.body);
        if (response.statusCode != 409 ||
            error is! Map ||
            error['code'] != '23505') {
          throw const FormatException('Publication failed');
        }
        session.check();
        final lookup = await connection
            .get(
              endpoint.replace(queryParameters: {
                'select': 'id,user_id',
                'id': 'eq.${row['id']}',
                'user_id': 'eq.${session.ownerId}',
              }),
              headers: _headers(session, contentType: 'application/json'),
            )
            .timeout(requestTimeout);
        session.check();
        if (lookup.statusCode != 200) {
          throw const FormatException('Publication lookup failed');
        }
        final rows = jsonDecode(lookup.body);
        final existing = rows is List && rows.length == 1 ? rows.single : null;
        if (existing is! Map ||
            existing['id'] != row['id'] ||
            existing['user_id'] != session.ownerId) {
          throw const FormatException('Publication does not match');
        }
      }
      session.check();
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      // The request may have committed. Keep the exact row/id for a safe retry.
      throw const PublicationFailure(
          'Нийтэлсэн эсэхийг баталж чадсангүй. Нийтлэгдсэн байж болно. '
          'Дахин оролдоход ижил нийтлэлийг шалгана; давхар нийтлэхгүй.');
    } finally {
      if (_httpClient == null) connection.close();
    }
  }
}
