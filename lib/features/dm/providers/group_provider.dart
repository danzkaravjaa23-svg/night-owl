import '../../../core/services/supabase_service.dart';

/// Групп чатын үйлчилгээ — group_chats / group_members / group_messages
class GroupService {
  /// Миний гишүүнээр орсон группүүд (сүүлийн мессежтэй хамт)
  static Future<List<Map<String, dynamic>>> myGroups() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return [];
    try {
      final rows = await SupabaseService.client
          .from('group_members')
          .select('group_id, group_chats!inner(id, name, created_by, created_at)')
          .eq('user_id', me);
      final groups = <Map<String, dynamic>>[];
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final g = r['group_chats'] as Map<String, dynamic>?;
        if (g != null) groups.add(g);
      }
      // Сүүлийн мессежийг ГРУПП тус бүрээр (limit 1) авна.
      // Өмнө нь бүх группд нийт 60 мөр авдаг байсан тул нэг идэвхтэй групп
      // бусад группуудын сүүлийн мессежийг "залгидаг" байсан алдааг зассан.
      if (groups.isNotEmpty) {
        await Future.wait(groups.map((g) async {
          try {
            final last = await SupabaseService.client
                .from('group_messages')
                .select('body, created_at')
                .eq('group_id', g['id'] as String)
                .order('created_at', ascending: false)
                .limit(1)
                .maybeSingle();
            g['last_msg'] = last?['body'];
            g['last_at'] = last?['created_at'] ?? g['created_at'];
          } catch (_) {
            g['last_at'] = g['created_at'];
          }
        }));
        groups.sort((a, b) => (b['last_at'] as String? ?? '')
            .compareTo(a['last_at'] as String? ?? ''));
      }
      return groups;
    } catch (_) {
      return [];
    }
  }

  /// Групп үүсгээд гишүүдийг нэмнэ. Амжилттай бол group id буцаана.
  /// create_group RPC байвал транзакцаар (атомик) үүсгэнэ; байхгүй бол
  /// хоёр insert хийж, гишүүд орохгүй бол group_chats-ийг буцааж устгана
  /// (orphan групп үлдэхээс сэргийлэв).
  static Future<String?> createGroup(
      String name, List<String> memberIds) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return null;
    final members = {...memberIds, me}.toList(); // өөрийгөө заавал оруулна

    // 1) RPC — атомик
    try {
      final res = await SupabaseService.client.rpc('create_group', params: {
        'p_name': name,
        'p_member_ids': members,
      });
      final gid = res is String ? res : res?.toString();
      if (gid != null && gid.isNotEmpty) return gid;
    } catch (_) {
      // RPC байхгүй/алдаа — доорх fallback руу
    }

    // 2) Fallback — compensating delete-тэй
    String? gid;
    try {
      final g = await SupabaseService.client
          .from('group_chats')
          .insert({'name': name, 'created_by': me})
          .select('id')
          .single();
      gid = g['id'] as String;
      await SupabaseService.client.from('group_members').insert([
        for (final uid in members) {'group_id': gid, 'user_id': uid},
      ]);
      return gid;
    } catch (_) {
      // Гишүүд орж чадаагүй бол orphan группыг цэвэрлэнэ
      if (gid != null) {
        try {
          await SupabaseService.client
              .from('group_chats').delete().eq('id', gid);
        } catch (_) {}
      }
      return null;
    }
  }

  /// Группийн нэрийг id-аар авна (deep-link / reload үед name query байхгүй үед)
  static Future<String?> groupName(String groupId) async {
    try {
      final g = await SupabaseService.client
          .from('group_chats')
          .select('name')
          .eq('id', groupId)
          .maybeSingle();
      return g?['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Группээс гарна (өөрийн group_members мөрийг устгана)
  static Future<bool> leaveGroup(String groupId) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return false;
    try {
      await SupabaseService.client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', me);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Группд шинэ гишүүд нэмнэ (аль хэдийн байгааг алгасна)
  static Future<bool> addMembers(String groupId, List<String> userIds) async {
    if (userIds.isEmpty) return true;
    try {
      await SupabaseService.client.from('group_members').upsert([
        for (final uid in userIds) {'group_id': groupId, 'user_id': uid},
      ], onConflict: 'group_id,user_id', ignoreDuplicates: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Группийн гишүүд (нэр, зурагтай)
  static Future<List<Map<String, dynamic>>> members(String groupId) async {
    try {
      final rows = await SupabaseService.client
          .from('group_members')
          .select('user_id, profiles!inner(id, username, avatar_url)')
          .eq('group_id', groupId);
      return [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          if (r['profiles'] != null) r['profiles'] as Map<String, dynamic>
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> sendMessage(String groupId, String body) async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return false;
    try {
      await SupabaseService.client.from('group_messages').insert({
        'group_id': groupId,
        'sender_id': me,
        'body': body,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
