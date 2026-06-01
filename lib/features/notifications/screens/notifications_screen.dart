import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final user = SupabaseService.currentUser;
      if (user == null) { if (mounted) setState(() => _loading = false); return; }
      final data = await SupabaseService.client
          .from('notifications')
          .select('*, profiles!actor_id (id, username, avatar_url)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) setState(() {
        _notifs = (data as List).cast<Map<String,dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    await SupabaseService.client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id);
    setState(() {
      _notifs = _notifs.map((n) => {...n, 'is_read': true}).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => n['is_read'] != true).length;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 8, 8),
          child: Row(children: [
            if (context.canPop())
              GestureDetector(
                onTap: () => context.pop(),
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8, left: 4),
                  child: Icon(Icons.arrow_back_ios_new,
                    size: 20, color: AppColors.textPrimary))),
            Text('Activity', style: AppTextStyles.h1),
            if (unread > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentStart,
                  borderRadius: BorderRadius.circular(10)),
                child: Text('$unread',
                  style: const TextStyle(color: Colors.white,
                    fontSize: 12, fontWeight: FontWeight.w700))),
            ],
            const Spacer(),
            if (unread > 0)
              TextButton(
                onPressed: _markAllRead,
                child: Text('Mark all read',
                  style: AppTextStyles.bodyXs.copyWith(color: AppColors.accentStart))),
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 20,
                color: AppColors.textSecondary),
              padding: const EdgeInsets.all(8)),
          ]),
        ),

        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accentStart, strokeWidth: 2))
          : _notifs.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  color: AppColors.accentStart,
                  backgroundColor: AppColors.bgElevated,
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _notifs.length,
                    itemBuilder: (_, i) {
                      final n = _notifs[i];
                      return _NotifTile(
                        notif: n,
                        onTap: () async {
                          // Mark read
                          if (n['is_read'] != true) {
                            SupabaseService.client
                                .from('notifications')
                                .update({'is_read': true})
                                .eq('id', n['id'])
                                .then((_) {})
                                .catchError((_) {});
                            setState(() => _notifs[i] = {...n, 'is_read': true});
                          }
                          // Navigate to post or profile
                          final postId  = n['post_id'] as String?;
                          final type    = n['type'] as String? ?? '';
                          final actorId = (n['profiles'] as Map?)?['id'] as String?;
                          if (!mounted) return;
                          if (type == 'message' && actorId != null) {
                            context.push('/dm/$actorId');
                          } else if (postId != null &&
                              (type == 'like' || type == 'comment')) {
                            context.push('/post/$postId');
                          } else if (actorId != null) {
                            context.push('/creator/$actorId');
                          }
                        },
                      );
                    },
                  )),
        ),
      ])),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final VoidCallback onTap;
  const _NotifTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type     = notif['type'] as String? ?? 'like';
    final profiles = notif['profiles'] as Map?;
    final username = profiles?['username'] as String? ?? 'Someone';
    final avatarUrl= profiles?['avatar_url'] as String?;
    final initial  = username.replaceAll('@', '').isNotEmpty
        ? username.replaceAll('@', '')[0].toUpperCase() : '?';
    final message  = notif['message'] as String? ?? '';
    final isRead   = notif['is_read'] as bool? ?? false;

    final icon = switch (type) {
      'like'    => Icons.favorite_rounded,
      'follow'  => Icons.person_add_rounded,
      'comment' => Icons.chat_bubble_rounded,
      'message' => Icons.mail_rounded,
      'mention' => Icons.alternate_email_rounded,
      'event'   => Icons.event_rounded,
      _         => Icons.notifications_rounded,
    };
    final color = switch (type) {
      'like'    => AppColors.accentStart,
      'follow'  => AppColors.accentPurple,
      'comment' => AppColors.accentEnd,
      'message' => AppColors.accentPurple,
      'mention' => AppColors.accentEnd,
      'event'   => AppColors.success,
      _         => AppColors.textSecondary,
    };

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isRead ? Colors.transparent
            : AppColors.accentStart.withOpacity(0.06),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Stack(children: [
            AppAvatar(imageUrl: avatarUrl, initial: initial, size: 48),
            Positioned(bottom: 0, right: 0,
              child: Container(width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color,
                  border: Border.all(color: AppColors.bgBase, width: 2)),
                child: Icon(icon, size: 10, color: Colors.white))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(text: TextSpan(
                style: AppTextStyles.bodyMd,
                children: [
                  TextSpan(text: '$username ',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: message),
                ])),
              const SizedBox(height: 3),
              Text(_ago(notif['created_at'] as String?),
                style: AppTextStyles.bodyXs.copyWith(
                  color: AppColors.textTertiary)),
            ])),
          const SizedBox(width: 8),
          if (!isRead)
            Container(width: 8, height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentStart)),
        ]),
      ),
    );
  }

  String _ago(String? iso) {
    if (iso == null) return '';
    final d = DateTime.now().difference(DateTime.parse(iso));
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    if (d.inDays < 7)     return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.bgSurface,
          border: Border.all(color: AppColors.hairline)),
        child: const Center(
          child: Text('🔔', style: TextStyle(fontSize: 36)))),
      const SizedBox(height: 20),
      Text('No activity yet', style: AppTextStyles.h2),
      const SizedBox(height: 8),
      Text('Likes, comments and follows\nwill appear here.',
        style: AppTextStyles.bodyMd.copyWith(
          color: AppColors.textSecondary, height: 1.5),
        textAlign: TextAlign.center),
    ]));
}
