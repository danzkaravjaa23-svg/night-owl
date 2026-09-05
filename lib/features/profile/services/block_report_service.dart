import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

/// Block / Report үйлчилгээ
class BlockReportService {
  static final _c = SupabaseService.client;

  /// Хэрэглэгчийг блоклох
  static Future<String?> block(String userId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return 'Нэвтэрнэ үү';
    if (me == userId) return 'Өөрийгөө блоклож болохгүй';
    try {
      await _c.from('blocks').upsert({
        'blocker_id': me,
        'blocked_id': userId,
      }, onConflict: 'blocker_id,blocked_id');
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Блокыг цуцлах
  static Future<String?> unblock(String userId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return 'Нэвтэрнэ үү';
    try {
      await _c.from('blocks').delete().match({
        'blocker_id': me,
        'blocked_id': userId,
      });
      return null;
    } catch (e) {
      return e.toString();
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
      final res = await _c.from('blocks').select('blocked_id').eq('blocker_id', me);
      return (res as List)
          .map((e) => e['blocked_id']?.toString())
          .whereType<String>()
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// [Админ] Хэрэглэгчийг хориглох / сэргээх (profiles RLS — is_admin())
  static Future<String?> setBanned(String userId, bool banned) async {
    try {
      await _c.from('profiles').update({'is_banned': banned}).eq('id', userId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Контент/хэрэглэгчийг мэдээлэх
  /// targetType: 'post' | 'user' | 'comment' | 'venue'
  static Future<String?> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return 'Нэвтэрнэ үү';
    try {
      await _c.from('reports').insert({
        'reporter_id': me,
        'target_type': targetType,
        'target_id':   targetId,
        'reason':      reason,
        if (details != null && details.isNotEmpty) 'details': details,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

/// Миний блоклосон хэрэглэгчдийн ID-нуудын provider (search/list-д шүүхэд)
final blockedIdsProvider = FutureProvider<Set<String>>((ref) async {
  return BlockReportService.myBlockedIds();
});
