import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../post/services/content_publication.dart';

/// Keeps a venue draft and its network credentials bound to one login.
class VenueEditorService {
  final SupabaseClient? _client;
  final http.Client? _httpClient;
  final Duration requestTimeout;

  VenueEditorService({
    SupabaseClient? client,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 60),
  })  : _client = client,
        _httpClient = httpClient;

  SupabaseClient get client => _client ?? SupabaseService.client;
  PublicationSession captureSession() =>
      ContentPublicationService(client: client).captureSession();
  Stream<void> get sessionChanges => client.auth.onAuthStateChange.map((_) {});

  Future<Map<String, dynamic>?> load(PublicationSession session,
      {String? venueId}) async {
    session.check();
    var query = client.from('venues').select().eq('owner_id', session.ownerId!);
    if (venueId != null) query = query.eq('id', venueId);
    final row = await query.limit(1).maybeSingle().timeout(requestTimeout);
    session.check();
    return row;
  }

  Map<String, String> _headers(
          PublicationSession session, String contentType) =>
      Map<String, String>.from(client.auth.headers)
        ..removeWhere((key, _) =>
            key.toLowerCase() == 'authorization' ||
            key.toLowerCase() == 'content-type')
        ..addAll({
          'Authorization': 'Bearer ${session.token}',
          'Content-Type': contentType,
        });

  Future<String> uploadCover(
      PublicationSession session, Uint8List bytes) async {
    session.check();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const PublicationFailure('Зураг хоосон эсвэл 5MB-ээс том байна.');
    }
    final type = ContentPublicationService.imageType(bytes);
    final path =
        '${session.ownerId}/cover_${ContentPublicationService.newId()}.${type.ext}';
    final root = client.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '');
    final connection = _httpClient ?? http.Client();
    try {
      // The shared Supabase transport can refresh from a different ambient
      // login while dispatching. Use the captured draft's token directly.
      final response = await connection
          .post(Uri.parse('$root/storage/v1/object/venues/$path'),
              headers: _headers(session, type.mime)..['x-upsert'] = 'false',
              body: bytes)
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const PublicationFailure(
            'Зураг илгээж чадсангүй. Дахин оролдоно уу');
      }
      return client.storage.from('venues').getPublicUrl(path);
    } finally {
      if (_httpClient == null) connection.close();
    }
  }

  Future<void> save(PublicationSession session, Map<String, dynamic> row,
      {String? venueId}) async {
    session.check();
    if (row['owner_id'] != session.ownerId) {
      throw const PublicationFailure(
          'Газрын эзний мэдээлэл өөрчлөгдсөн байна.');
    }
    final root = client.rest.url.replaceFirst(RegExp(r'/$'), '');
    final uri = Uri.parse('$root/venues').replace(queryParameters: {
      'select': 'id',
      if (venueId != null) 'id': 'eq.$venueId',
      if (venueId != null) 'owner_id': 'eq.${session.ownerId}',
    });
    final headers = _headers(session, 'application/json')
      ..['Prefer'] = 'return=representation';
    final body = jsonEncode(row);
    final connection = _httpClient ?? http.Client();
    try {
      final response = await (venueId == null
              ? connection.post(uri, headers: headers, body: body)
              : connection.patch(uri, headers: headers, body: body))
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const PublicationFailure('Хадгалж чадсангүй. Дахин оролдоно уу');
      }
      final rows = jsonDecode(response.body);
      if (rows is! List ||
          rows.length != 1 ||
          rows.single is! Map ||
          rows.single['id'] is! String ||
          (venueId != null && rows.single['id'] != venueId)) {
        throw const PublicationFailure('Хадгалж чадсангүй. Дахин оролдоно уу');
      }
    } finally {
      if (_httpClient == null) connection.close();
    }
  }
}
