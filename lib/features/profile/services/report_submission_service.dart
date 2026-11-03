import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../post/services/content_publication.dart';

final reportSubmissionServiceProvider =
    Provider((ref) => ReportSubmissionService());

/// A report stays bound to the account that opened its form. Only the target
/// reference is sent; the server captures the exact caller-readable context.
class ReportSubmissionService extends ContentPublicationService {
  final http.Client? _transport;
  ReportSubmissionService(
      {super.client, super.httpClient, super.requestTimeout})
      : _transport = httpClient;
  Stream<void> get sessionChanges => client.auth.onAuthStateChange.map((_) {});

  Future<void> submit(
    PublicationSession session, {
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    session.check();
    if (!const {
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
        }.contains(targetType) ||
        targetId.trim().isEmpty ||
        !const {'spam', 'harassment', 'nudity', 'violence', 'hate', 'other'}
            .contains(reason) ||
        (details?.trim().length ?? 0) > 2000) {
      throw const PublicationFailure(
          'Мэдээллийн төрөл, шалтгаан, тайлбарыг шалгана уу.');
    }
    final connection = _transport ?? http.Client();
    try {
      final headers = Map<String, String>.from(client.auth.headers)
        ..removeWhere((key, _) => const {'authorization', 'content-type'}
            .contains(key.toLowerCase()));
      headers.addAll({
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json'
      });
      final response = await connection
          .post(
            Uri.parse('${client.rest.url}/rpc/report_ugc'),
            headers: headers,
            body: jsonEncode({
              'p_target_type': targetType,
              'p_target_id': targetId,
              'p_reason': reason,
              'p_details':
                  details?.trim().isEmpty == true ? null : details?.trim()
            }),
          )
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final payload = jsonDecode(response.body);
        final code = payload is Map ? payload['code'] : null;
        throw PublicationFailure(switch (code) {
          '40001' => 'Энэ агуулгын тухай таны өмнөх мэдээлэл шалгагдаж байна.',
          'P0002' => 'Мэдээлэх агуулга олдсонгүй. Хуудсыг шинэчилнэ үү.',
          '42501' =>
            'Энэ үйлдлийг хийх эрхгүй. Нэвтрэлт болон агуулгын эрхээ шалгана уу.',
          _ => 'Мэдээллийг илгээж чадсангүй. Түр хүлээгээд дахин оролдоно уу.',
        });
      }
      final id = jsonDecode(response.body);
      if (id is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
              .hasMatch(id)) {
        throw const FormatException('Invalid report receipt');
      }
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const PublicationFailure(
          'Илгээсэн эсэхийг баталж чадсангүй. Дахин шалгаарай.');
    } finally {
      if (_transport == null) connection.close();
    }
  }
}
