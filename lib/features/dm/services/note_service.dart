import 'dart:convert';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../../post/services/content_publication.dart';

final noteServiceProvider = Provider((ref) => NoteService());

/// A note belongs to the login that opened its draft, including after a refresh.
class NoteService {
  final SupabaseClient? _client;
  final http.Client? _transport;
  final Duration timeout;
  NoteService(
      {SupabaseClient? client,
      http.Client? transport,
      this.timeout = const Duration(seconds: 30)})
      : _client = client,
        _transport = transport;
  SupabaseClient get client => _client ?? SupabaseService.client;
  PublicationSession captureSession() =>
      ContentPublicationService(client: client).captureSession();
  Stream<void> get sessionChanges => client.auth.onAuthStateChange.map((_) {});

  /// Returns the saved note's moderation_status, or null when unknown.
  Future<String?> save(
          PublicationSession session, String text, String? venueId) =>
      _write(session, text: text.trim(), venueId: venueId);
  Future<void> delete(PublicationSession session) => _write(session);

  Future<String?> _write(PublicationSession session,
      {String? text, String? venueId}) async {
    session.check();
    if (text != null && (text.isEmpty || text.characters.length > 100)) {
      throw const PublicationFailure('Note 1–100 тэмдэгттэй байна.');
    }
    final deleting = text == null;
    final uri =
        Uri.parse('${client.rest.url.replaceFirst(RegExp(r'/$'), '')}/notes')
            .replace(queryParameters: {
      'select': 'user_id,text,moderation_status',
      if (deleting) 'user_id': 'eq.${session.ownerId}',
      if (!deleting) 'on_conflict': 'user_id',
    });
    final headers = Map<String, String>.from(client.auth.headers)
      ..removeWhere((key, _) => ['authorization', 'content-type', 'prefer']
          .contains(key.toLowerCase()))
      ..addAll({
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
        'Prefer':
            '${deleting ? '' : 'resolution=merge-duplicates,'}return=representation'
      });
    final now = DateTime.now().toUtc();
    final connection = _transport ?? http.Client();
    try {
      final response = await (deleting
              ? connection.delete(uri, headers: headers)
              : connection.post(uri,
                  headers: headers,
                  body: jsonEncode({
                    'user_id': session.ownerId,
                    'text': text,
                    'venue_id': venueId,
                    'created_at': now.toIso8601String(),
                    'expires_at':
                        now.add(const Duration(hours: 24)).toIso8601String(),
                  })))
          .timeout(timeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const PublicationFailure(
            'Note хадгалж чадсангүй. Дахин оролдоно уу.');
      }
      final rows = jsonDecode(response.body);
      if (rows is! List ||
          rows.length != 1 ||
          rows.single is! Map ||
          rows.single['user_id'] != session.ownerId ||
          (!deleting && rows.single['text'] != text)) {
        throw const PublicationFailure(
            'Өөрчлөлт баталгаажаагүй байна. Дахин оролдоно уу.');
      }
      return savedModerationStatus(rows);
    } finally {
      if (_transport == null) connection.close();
    }
  }
}
