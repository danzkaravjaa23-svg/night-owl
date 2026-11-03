import 'report_submission_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../post/services/content_publication.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';
import '../../../core/services/supabase_service.dart';

final blockMutationServiceProvider = Provider((ref) => BlockMutationService());

/// Account-bound mutations never refresh or replace the ambient SDK login.
class BlockMutationService extends ContentPublicationService {
  final http.Client? _transport;
  BlockMutationService({super.client, super.httpClient, super.requestTimeout})
      : _transport = httpClient;

  Future<void> setBlocked(PublicationSession session, String target,
      {required bool blocked}) async {
    session.check();
    if (target.isEmpty || target == session.ownerId) {
      throw const PublicationFailure('Өөрийгөө блоклож болохгүй.');
    }
    final connection = _transport ?? http.Client();
    try {
      final headers = Map<String, String>.from(client.auth.headers)
        ..removeWhere((key, _) => const {
              'authorization',
              'content-type',
              'prefer'
            }.contains(key.toLowerCase()));
      headers.addAll({
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
        'Prefer': blocked
            ? 'resolution=ignore-duplicates,return=minimal'
            : 'return=minimal',
      });
      final uri = Uri.parse('${client.rest.url}/blocks').replace(
          queryParameters: blocked
              ? {'on_conflict': 'blocker_id,blocked_id'}
              : {
                  'blocker_id': 'eq.${session.ownerId}',
                  'blocked_id': 'eq.$target'
                });
      final response = await (blocked
              ? connection.post(uri,
                  headers: headers,
                  body: jsonEncode(
                      {'blocker_id': session.ownerId, 'blocked_id': target}))
              : connection.delete(uri, headers: headers))
          .timeout(requestTimeout);
      session.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const PublicationFailure(
            'Блокийн тохиргоог хадгалж чадсангүй. Нэвтрэлтээ шалгаад дахин оролдоно уу.');
      }
    } on PublicationFailure {
      rethrow;
    } catch (_) {
      session.check();
      throw const PublicationFailure(
          'Блокийн тохиргоо хадгалагдсан эсэхийг баталж чадсангүй. Дахин шалгаарай.');
    } finally {
      if (_transport == null) connection.close();
    }
  }
}

/// Block / Report үйлчилгээ
class BlockReportService {
  static SupabaseClient get _c => SupabaseService.client;

  /// Хэрэглэгчийг блоклох
  static Future<String?> block(String userId) async {
    return _change(userId, true);
  }

  /// Блокыг цуцлах
  static Future<String?> unblock(String userId) async {
    return _change(userId, false);
  }

  static Future<String?> _change(String userId, bool blocked) async {
    PublicationSession? session;
    try {
      final service = BlockMutationService();
      session = service.captureSession();
      if (session.ownerId == null) return 'Нэвтэрнэ үү';
      await service.setBlocked(session, userId, blocked: blocked);
      return null;
    } catch (error) {
      return error is PublicationFailure
          ? error.message
          : discoveryError(error);
    } finally {
      session?.close();
    }
  }

  /// Тухайн хэрэглэгчийг блоклосон эсэх
  static Future<bool> isBlocked(String userId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return false;
    try {
      final res = await _c
          .from('blocks')
          .select('blocked_id')
          .eq('blocker_id', me)
          .eq('blocked_id', userId)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  /// Миний блоклосон бүх хэрэглэгчийн ID
  static Future<Set<String>> myBlockedIds() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return {};
    try {
      final res =
          await _c.from('blocks').select('blocked_id').eq('blocker_id', me);
      return (res as List)
          .map((e) => e['blocked_id']?.toString())
          .whereType<String>()
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Контент/хэрэглэгчийг мэдээлэх
  /// Server validates the caller-readable target and selected context.
  static Future<String?> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    final service = ReportSubmissionService();
    final session = service.captureSession();
    try {
      await service.submit(session,
          targetType: targetType,
          targetId: targetId,
          reason: reason,
          details: details);
      return null;
    } catch (error) {
      return error is PublicationFailure
          ? error.message
          : discoveryError(error);
    } finally {
      session.close();
    }
  }
}

/// Миний блоклосон хэрэглэгчдийн ID-нуудын provider (search/list-д шүүхэд)
final blockedIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(sessionUserIdProvider);
  return BlockReportService.myBlockedIds();
});
