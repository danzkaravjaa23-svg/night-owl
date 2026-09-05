import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/notification_provider.dart' show markAllNotifsRead;

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _notifs = [];
  Map<String, String> _thumbs = {}; // post_id → media_url (баруун талын thumbnail)
  bool _loading = true;
  bool _error = false;
  bool _markingAll = false; // "Бүгдийг уншсан" явцын төлөв

  @override
  void initState() {
    super.initState();
    // Дэлгэц нээхэд DB-д уншсан болгоно (bottom-nav badge арилна).
    // Local _notifs-ийг шууд өөрчлөхгүй — энэ session-д "шинэ"-г онцолж харуулна.
    _load().then((_) => markAllNotifsRead().catchError((_) {}));
  }

  Future<void> _load() async {
    // Жагсаалт байхад spinner-ээр солихгүй — RefreshIndicator өөрөө харуулна
    if (mounted && _notifs.isEmpty) setState(() { _loading = true; _error = false; });
    try {
      final user = SupabaseService.currentUser;
      if (user == null) { if (mounted) setState(() => _loading = false); return; }
      final data = await SupabaseService.client
          .from('notifications')
          .select('*, profiles!actor_id (id, username, avatar_url)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifs = (data as List).cast<Map<String, dynamic>>();
          _loading = false;
          _error = false;
        });
        _loadThumbs(); // жагсаалтыг хүлээлгэхгүй — thumbnail-уудыг ард нь татна
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _notifs.isEmpty; });
      // Жагсаалт байсаар байгаа refresh бүтэлгүйтсэн тохиолдолд мэдэгдэнэ
      if (_notifs.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Шинэчлэхэд алдаа гарлаа')));
      }
    }
  }

  /// Мэдэгдэлтэй холбоотой постуудын media_url-ийг batch-аар татна.
  /// Нэмэлт чимэг тул алдаа гарвал чимээгүй — icon fallback хэвээр үлдэнэ.
  Future<void> _loadThumbs() async {
    final ids = _notifs
        .map((n) => n['post_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final data = await SupabaseService.client
          .from('posts')
          .select('id, media_url')
          .inFilter('id', ids);
      if (!mounted) return;
      setState(() {
        _thumbs = {
          for (final p in (data as List).cast<Map<String, dynamic>>())
            if (p['media_url'] != null)
              p['id'] as String: p['media_url'] as String,
        };
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    final user = SupabaseService.currentUser;
    if (user == null || _markingAll) return;
    // Optimistic — эхлээд local-оо шинэчилж, алдаа гарвал буцаана
    final prev = _notifs;
    setState(() {
      _markingAll = true;
      _notifs = _notifs.map((n) => {...n, 'is_read': true}).toList();
    });
    try {
      await SupabaseService.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id);
      if (!mounted) return;
      setState(() => _markingAll = false);
    } catch (_) {
      if (!mounted) return;
      setState(() { _notifs = prev; _markingAll = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Алдаа гарлаа — дахин оролдоно уу'),
        backgroundColor: AppColors.error));
    }
  }

  void _onTapNotif(int i, Map<String, dynamic> n) {
    // Уншсан болгох
    if (n['is_read'] != true) {
      SupabaseService.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', n['id'])
          .then((_) {})
          .catchError((_) {});
      setState(() => _notifs[i] = {...n, 'is_read': true});
    }
    // Пост / профайл руу шилжинэ
    final postId  = n['post_id'] as String?;
    final type    = n['type'] as String? ?? '';
    final actorId = (n['profiles'] as Map?)?['id'] as String?;
    if (!mounted) return;
    if (type == 'message' && actorId != null) {
      context.push('/dm/$actorId');
    } else if (postId != null &&
        (type == 'like' || type == 'comment' || type == 'mention')) {
      context.push('/post/$postId');
    } else if (type == 'event') {
      // Эвент мэдэгдэл — фийд дэх events rail руу
      context.go('/feed');
    } else if (actorId != null) {
      context.push('/creator/$actorId');
    } else if (postId != null) {
      context.push('/post/$postId');
    } else {
      // Очих газаргүй (устсан контент) — хэрэглэгчид мэдэгдэнэ
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Контент олдсонгүй')));
    }
  }

  /// Мэдэгдлүүдийг цагаар нь бүлэглэнэ: ӨНӨӨДӨР / ЭНЭ 7 ХОНОГ / ӨМНӨХ.
  /// Гаралт — гарчиг (String) эсвэл (эх индекс, мэдэгдэл) хослол.
  List<Object> _sectioned() {
    final now = DateTime.now();
    final today   = <(int, Map<String, dynamic>)>[];
    final week    = <(int, Map<String, dynamic>)>[];
    final earlier = <(int, Map<String, dynamic>)>[];
    for (var i = 0; i < _notifs.length; i++) {
      final iso = _notifs[i]['created_at'] as String?;
      DateTime? t;
      if (iso != null) {
        try { t = DateTime.parse(iso).toLocal(); } catch (_) {}
      }
      if (t != null && t.year == now.year && t.month == now.month &&
          t.day == now.day) {
        today.add((i, _notifs[i]));
      } else if (t != null && now.difference(t).inDays < 7) {
        week.add((i, _notifs[i]));
      } else {
        earlier.add((i, _notifs[i]));
      }
    }
    final out = <Object>[];
    if (today.isNotEmpty)   { out.add('ӨНӨӨДӨР');      out.addAll(today); }
    if (week.isNotEmpty)    { out.add('ЭНЭ 7 ХОНОГ');  out.addAll(week); }
    if (earlier.isNotEmpty) { out.add('ӨМНӨХ');        out.addAll(earlier); }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => n['is_read'] != true).length;
    final entries = _sectioned();

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(child: Column(children: [
        // ── Header — том гарчиг + үйлдлүүд ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(children: [
            if (context.canPop()) ...[
              _Press(
                onTap: () => context.pop(),
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgElevated.withValues(alpha: 0.72),
                    border: Border.all(color: AppColors.hairline)),
                  child: const Icon(Icons.arrow_back_ios_new,
                    size: 16, color: AppColors.textPrimary))),
              const SizedBox(width: 14),
            ],
            Text('Мэдэгдэл', style: AppTextStyles.h1),
            if (unread > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: AppColors.glowShadow(AppColors.accentStart,
                      alpha: 0.4, blur: 12)),
                child: Text('$unread',
                  style: const TextStyle(color: Colors.white,
                    fontSize: 12, fontWeight: FontWeight.w700))),
            ],
            const Spacer(),
            if (unread > 0) ...[
              _Press(
                onTap: _markingAll ? null : _markAllRead,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hairline)),
                  child: _markingAll
                    ? const SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accentStart))
                    : Text('Бүгдийг уншсан',
                        style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.accentStart,
                          fontWeight: FontWeight.w600)))),
              const SizedBox(width: 4),
            ],
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 20,
                color: AppColors.textSecondary),
              padding: const EdgeInsets.all(8)),
          ]),
        ),

        Expanded(child: _loading
          ? const _SkeletonList()
          : _error
              ? _ErrorState(onRetry: _load)
              : _notifs.isEmpty
                  ? _EmptyNotifState(onRefresh: _load)
                  : RefreshIndicator(
                      color: AppColors.accentStart,
                      backgroundColor: AppColors.bgElevated,
                      onRefresh: _load,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 28),
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          // Хэсгийн гарчиг — uppercase sectionLabel + сунгасан hairline
                          if (e is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                              child: Row(children: [
                                Text(e, style: AppTextStyles.sectionLabel),
                                const SizedBox(width: 12),
                                const Expanded(child: Divider(
                                  color: AppColors.hairline, height: 1)),
                              ]),
                            );
                          }
                          final (idx, n) = e as (int, Map<String, dynamic>);
                          return _NotifTile(
                            notif: n,
                            thumbUrl: _thumbs[n['post_id']],
                            onTap: () => _onTapNotif(idx, n),
                          );
                        },
                      )),
        ),
      ])),
    );
  }
}

// ─── Дарахад жижигрэх + hover cursor (веб мэдрэмж) ───
class _Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Press({required this.child, this.onTap});
  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null
        ? SystemMouseCursors.basic : SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null : (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child),
    ),
  );
}

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  final String? thumbUrl; // постын жинхэнэ зураг (байхгүй бол icon fallback)
  final VoidCallback onTap;
  const _NotifTile({required this.notif, this.thumbUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type     = notif['type'] as String? ?? 'like';
    final profiles = notif['profiles'] as Map?;
    final username = profiles?['username'] as String? ?? 'Хэрэглэгч';
    final avatarUrl= profiles?['avatar_url'] as String?;
    final initial  = username.replaceAll('@', '').isNotEmpty
        ? username.replaceAll('@', '')[0].toUpperCase() : '?';
    final message  = notif['message'] as String? ?? '';
    final isRead   = notif['is_read'] as bool? ?? false;
    final postId   = notif['post_id'] as String?;

    final icon = switch (type) {
      'like'    => Icons.favorite_rounded,
      'follow'  => Icons.person_add_rounded,
      'comment' => Icons.chat_bubble_rounded,
      'message' => Icons.mail_rounded,
      'mention' => Icons.alternate_email_rounded,
      'event'   => Icons.event_rounded,
      _         => Icons.notifications_rounded,
    };
    // Төрлийн өнгө — like=pink, follow/message=cyan, comment=purple, event=lime
    final color = switch (type) {
      'like'    => AppColors.accentEnd,
      'follow'  => AppColors.neonCyan,
      'comment' => AppColors.accentPurple,
      'message' => AppColors.neonCyan,
      'mention' => AppColors.accentEnd,
      'event'   => AppColors.success,
      _         => AppColors.textSecondary,
    };

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: isRead ? Colors.transparent
            : AppColors.accentStart.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          // Actor avatar 44 + төрлийн неон glow badge
          Stack(children: [
            AppAvatar(imageUrl: avatarUrl, initial: initial, size: 44),
            Positioned(bottom: 0, right: 0,
              child: Container(width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: color,
                  border: Border.all(color: AppColors.bgBase, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.55),
                      blurRadius: 10, spreadRadius: -1),
                  ]),
                child: Icon(icon, size: 10, color: Colors.white))),
          ]),
          const SizedBox(width: 14),
          // Richtext — нэр w700 + үйлдэл secondary + хугацаа inline micro
          Expanded(child: RichText(
            maxLines: 3, overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textSecondary, height: 1.35),
              children: [
                TextSpan(text: '$username ',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
                TextSpan(text: message),
                TextSpan(text: '  ·  ${_ago(notif['created_at'] as String?)}',
                  style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textTertiary)),
              ]))),
          const SizedBox(width: 10),
          if (!isRead)
            Container(width: 8, height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentStart.withValues(alpha: 0.5),
                    blurRadius: 8),
                ])),
          // Пост руу очих affordance — жинхэнэ thumbnail 44, radius 10
          if (postId != null) _PostThumb(url: thumbUrl, color: color),
        ]),
      ),
    );
  }

  // Харьцангуй хугацаа — монголоор
  String _ago(String? iso) {
    if (iso == null) return '';
    final d = DateTime.now().difference(DateTime.parse(iso));
    if (d.inSeconds < 60) return 'саяхан';
    if (d.inMinutes < 60) return '${d.inMinutes} мин';
    if (d.inHours < 24)   return '${d.inHours} цаг';
    if (d.inDays < 7)     return '${d.inDays} өдөр';
    return '${(d.inDays / 7).floor()} долоо хоног';
  }
}

// ─── Постын thumbnail 44×44 (зураг → cover, видео/байхгүй → icon tile) ───
class _PostThumb extends StatelessWidget {
  final String? url;
  final Color color;
  const _PostThumb({required this.url, required this.color});

  // Icon fallback — glass tile 44, radius 10
  Widget _iconTile(IconData icon) => Container(width: 44, height: 44,
    decoration: BoxDecoration(
      color: AppColors.bgSurface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.hairline)),
    child: Icon(icon, size: 18, color: color.withValues(alpha: 0.9)));

  @override
  Widget build(BuildContext context) {
    final isVideo = isVideoUrl(url?.split('?').first);
    if (url == null || isVideo) {
      return _iconTile(isVideo
          ? Icons.play_arrow_rounded : Icons.image_outlined);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url!, width: 44, height: 44, fit: BoxFit.cover,
        memCacheWidth: 120, // жижиг decode — жагсаалт хурдан
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => Container(width: 44, height: 44,
            color: AppColors.bgSurface),
        errorWidget: (_, __, ___) => _iconTile(Icons.image_outlined),
      ),
    );
  }
}

// ─── Хоосон төлөв ───
class _EmptyNotifState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _EmptyNotifState({required this.onRefresh});
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    color: AppColors.accentStart,
    backgroundColor: AppColors.bgElevated,
    onRefresh: onRefresh,
    child: LayoutBuilder(builder: (context, c) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [SizedBox(height: c.maxHeight, child: EmptyState(
        illustration: 'assets/images/illustrations/empty_notif.svg',
        title: AppStrings.mn.notifEmptyTitle,
        subtitle: AppStrings.mn.notifEmptyBody,
      ))],
    )),
  );
}

// ─── Алдааны төлөв ───
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.textTertiary),
      const SizedBox(height: 12),
      Text('Алдаа гарлаа — дахин оролдоно уу',
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
      const SizedBox(height: 14),
      OutlinedButton(
        onPressed: onRetry,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentStart,
          side: const BorderSide(color: AppColors.hairline2)),
        child: const Text('Дахин оролдох')),
    ]),
  );
}

// ─── Эхний ачаалалтын skeleton (spinner-ийн оронд) ───
class _SkeletonList extends StatefulWidget {
  const _SkeletonList();
  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
    lowerBound: 0.4, upperBound: 0.9)..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Container(width: 44, height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.bgElevated)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 12, width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 8),
              Container(height: 10, width: 90,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(5))),
            ])),
          const SizedBox(width: 14),
          // Баруун талын пост tile placeholder
          Container(width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10))),
        ]),
      ),
    ),
  );
}
