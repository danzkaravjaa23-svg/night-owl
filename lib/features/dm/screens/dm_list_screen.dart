import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../widgets/notes_row.dart';

class DmListScreen extends StatefulWidget {
  const DmListScreen({super.key});
  @override State<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends State<DmListScreen> {
  String _search = '';
  List<Map<String, dynamic>> _convos = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = SupabaseService.currentUser?.id;
      if (me == null) { setState(() => _loading = false); return; }

      final data = await SupabaseService.client
          .from('messages')
          .select('*, sender:profiles!sender_id(id,username,avatar_url), receiver:profiles!receiver_id(id,username,avatar_url)')
          .or('sender_id.eq.$me,receiver_id.eq.$me')
          .order('created_at', ascending: false)
          .limit(100);

      final Map<String, Map<String, dynamic>> seen = {};
      for (final msg in (data as List)) {
        final m = msg as Map<String, dynamic>;
        final senderId   = m['sender_id'] as String;
        final receiverId = m['receiver_id'] as String;
        final partnerId  = senderId == me ? receiverId : senderId;
        if (!seen.containsKey(partnerId)) {
          seen[partnerId] = {
            'partner_id': partnerId,
            'partner': senderId == me ? m['receiver'] : m['sender'],
            'last_msg': m['body'] ?? '',
            'created_at': m['created_at'],
            'is_read': m['is_read'] ?? true,
            'is_me': senderId == me,
          };
        }
      }
      setState(() { _convos = seen.values.toList(); _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _convos;
    return _convos.where((c) {
      final partner  = c['partner'] as Map?;
      final username = partner?['username'] as String? ?? '';
      return username.toLowerCase().contains(_search.toLowerCase()) ||
          (c['last_msg'] as String? ?? '').toLowerCase().contains(_search.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _convos.where((c) => c['is_read'] == false).length;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
          child: Row(children: [
            if (context.canPop())
              GestureDetector(
                onTap: () => context.pop(),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8, left: 4),
                  child: Icon(Icons.arrow_back_ios_new,
                    size: 20, color: AppColors.textPrimary))),
            Text('Messages', style: AppTextStyles.h1),
            if (unreadCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentStart,
                  borderRadius: BorderRadius.circular(10)),
                child: Text('$unreadCount',
                  style: const TextStyle(color: Colors.white,
                    fontSize: 12, fontWeight: FontWeight.w700))),
            ],
            const Spacer(),
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary, size: 20)),
          ]),
        ),

        // Notes мөр (Instagram маягийн)
        const NotesRow(),

        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline)),
            child: Row(children: [
              const SizedBox(width: 12),
              const Icon(Icons.search, color: AppColors.textTertiary, size: 18),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search messages...',
                  hintStyle: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textTertiary),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.zero))),
              if (_search.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _search = ''),
                  child: const Padding(padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.close,
                      color: AppColors.textTertiary, size: 16))),
            ])),
        ),
        const SizedBox(height: 16),

        // Conversations
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accentStart, strokeWidth: 2))
          : _filtered.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  color: AppColors.accentStart,
                  backgroundColor: AppColors.bgElevated,
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _ConvoTile(
                      convo: _filtered[i], onChanged: _load)))),
      ])),
    );
  }
}

class _ConvoTile extends StatelessWidget {
  final Map<String, dynamic> convo;
  final VoidCallback onChanged;
  const _ConvoTile({required this.convo, required this.onChanged});

  String get _myId => SupabaseService.currentUser?.id ?? '';

  // Партнёроос ирсэн мессежийг уншсан/уншаагүй болгоно
  Future<void> _setRead(String partnerId, bool read) async {
    final me = _myId;
    if (me.isEmpty) return;
    try {
      await SupabaseService.client
          .from('messages')
          .update({'is_read': read})
          .eq('sender_id', partnerId)
          .eq('receiver_id', me);
    } catch (_) {}
  }

  void _showOptions(BuildContext context, String partnerId,
      String username, bool isRead) {
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: AppColors.hairline, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text(username.replaceAll('@', ''), style: AppTextStyles.labelLg),
            ])),
          const SizedBox(height: 8),
          if (!isRead)
            _OptTile(icon: Icons.mark_chat_read_outlined, label: 'Уншсан болгох',
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _setRead(partnerId, true);
                onChanged();
              })
          else
            _OptTile(icon: Icons.mark_chat_unread_outlined, label: 'Уншаагүй болгох',
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _setRead(partnerId, false);
                onChanged();
              }),
          _OptTile(icon: Icons.chat_bubble_outline, label: 'Чат нээх',
            onTap: () {
              Navigator.pop(sheetCtx);
              context.push('/dm/$partnerId').then((_) => onChanged());
            }),
          _OptTile(icon: Icons.person_outline, label: 'Профайл харах',
            onTap: () {
              Navigator.pop(sheetCtx);
              context.push('/creator/$partnerId');
            }),
          const SizedBox(height: 12),
        ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner    = convo['partner'] as Map?;
    final username   = partner?['username'] as String? ?? 'Unknown';
    final avatarUrl  = partner?['avatar_url'] as String?;
    final initial    = username.replaceAll('@','').isNotEmpty
        ? username.replaceAll('@','')[0].toUpperCase() : '?';
    final lastMsg    = convo['last_msg'] as String? ?? '';
    final isMe       = convo['is_me'] as bool? ?? false;
    final isRead     = convo['is_read'] as bool? ?? true;
    final partnerId  = convo['partner_id'] as String;
    final time       = _ago(convo['created_at'] as String?);

    return InkWell(
      onTap: () => context.push('/dm/$partnerId').then((_) => onChanged()),
      onLongPress: () => _showOptions(context, partnerId, username, isRead),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Stack(children: [
            AppAvatar(imageUrl: avatarUrl, initial: initial, size: 52),
            // Online dot (placeholder)
            Positioned(bottom: 2, right: 2,
              child: Container(width: 12, height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.success,
                  border: Border.all(color: AppColors.bgBase, width: 2)))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(username, style: AppTextStyles.labelMd.copyWith(
                  fontWeight: isRead ? FontWeight.w500 : FontWeight.w700)),
                const Spacer(),
                Text(time, style: AppTextStyles.bodyXs.copyWith(
                  color: isRead ? AppColors.textTertiary : AppColors.accentStart)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(child: Text(
                  '${isMe ? 'You: ' : ''}$lastMsg',
                  style: AppTextStyles.bodySm.copyWith(
                    color: isRead ? AppColors.textSecondary : AppColors.textPrimary,
                    fontWeight: isRead ? FontWeight.w400 : FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
                if (!isRead) ...[
                  const SizedBox(width: 8),
                  Container(width: 9, height: 9,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.accentGradient)),
                ],
              ]),
            ])),
        ]),
      ),
    );
  }

  String _ago(String? iso) {
    if (iso == null) return '';
    final d = DateTime.now().difference(DateTime.parse(iso));
    if (d.inMinutes < 1)  return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24)   return '${d.inHours}h';
    if (d.inDays < 7)     return '${d.inDays}d';
    return '${(d.inDays/7).floor()}w';
  }
}

class _OptTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _OptTile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.textSecondary, size: 22),
    title: Text(label, style: AppTextStyles.bodyMd.copyWith(
      color: AppColors.textPrimary)),
    onTap: onTap,
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('💬', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 16),
      Text('No messages yet', style: AppTextStyles.h2),
      const SizedBox(height: 8),
      Text('Хүмүүсийн profile-д орж мессеж илгээ.',
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
        textAlign: TextAlign.center),
    ]));
}
