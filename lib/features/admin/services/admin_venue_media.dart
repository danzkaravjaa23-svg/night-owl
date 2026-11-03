import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../post/services/content_publication.dart';
import '../providers/admin_console_provider.dart';
import 'admin_console_service.dart';

/// Uploads from the gated venue editor remain bound to its administrator.
class AdminVenueMedia {
  final http.Client? httpClient;
  final Duration timeout;
  AdminVenueMedia(
      {this.httpClient, this.timeout = const Duration(seconds: 30)});

  Future<String> upload(AdminConsoleAccess access, Uint8List bytes) async {
    final session = access.session;
    session.check();
    if (bytes.isEmpty || bytes.length > 50 * 1024 * 1024) {
      throw const AdminConsoleFailure('invalid');
    }
    final type = ContentPublicationService.imageType(bytes);
    final path =
        '${session.ownerId}/review_${ContentPublicationService.newId()}.${type.ext}';
    final client = access.service.client;
    final root = client.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '');
    final headers = Map<String, String>.from(client.auth.headers)
      ..removeWhere((key, _) => {'authorization', 'content-type', 'x-upsert'}
          .contains(key.toLowerCase()))
      ..addAll({
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': type.mime,
        'x-upsert': 'false'
      });
    final connection = httpClient ?? http.Client();
    try {
      final response = await connection
          .post(Uri.parse('$root/storage/v1/object/venues/$path'),
              headers: headers, body: bytes)
          .timeout(timeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AdminConsoleFailure('network');
      }
      return client.storage.from('venues').getPublicUrl(path);
    } on AdminConsoleFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const AdminConsoleFailure('network');
    } finally {
      if (httpClient == null) connection.close();
    }
  }
}
