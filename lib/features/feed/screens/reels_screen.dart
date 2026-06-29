import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});
  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  List<Map<String, dynamic>> _reels = [];
  bool _loading = true;
  bool _canCreate = false; // зөвхөн venue эзэн оруулна
  final Set<String> _liked = {};
  bool _forYou = true; // visual-only segment toggle (default: For You)
  final PageController _pageCtrl = PageController();
  int _page = 0; // идэвхтэй (харагдаж буй) reel — зөвхөн энэ дуутай тоглоно

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _checkOwner();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkOwner() async {
    if (_myId.isEmpty) return;
    try {
      final r = await SupabaseService.client.from('venues')
          .select('id').eq('owner_id', _myId).limit(1).maybeSingle();
      if (mounted) setState(() => _canCreate = r != null);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final data = await SupabaseService.client
          .from('posts')
          .select('id, user_id, caption, media_url, likes_count, comments_count, '
              'profiles!user_id (username, avatar_url)')
          .order('created_at', ascending: false)
          .limit(50);
      final all = (data as List).cast<Map<String, dynamic>>();
      final reels = all.where((p) => isVideoUrl(p['media_url'] as String?)).toList();

      // Аль reel-уудыг лайкласныг шалгах
      if (_myId.isNotEmpty && reels.isNotEmpty) {
        final ids = reels.map((r) => r['id'] as String).toList();
        final likes = await SupabaseService.client
            .from('likes').select('post_id').eq('user_id', _myId).inFilter('post_id', ids);
        for (final l in (likes as List)) { _liked.add(l['post_id'] as String); }
      }
      if (mounted) setState(() { _reels = reels; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final user = _myId;
    if (user.isEmpty) return;
    final wasLiked = _liked.contains(id);
    setState(() {
      if (wasLiked) {
        _liked.remove(id);
        reel['likes_count'] = (reel['likes_count'] as int? ?? 1) - 1;
      } else {
        _liked.add(id);
        reel['likes_count'] = (reel['likes_count'] as int? ?? 0) + 1;
      }
    });
    try {
      if (wasLiked) {
        await SupabaseService.client.from('likes').delete()
            .eq('user_id', user).eq('post_id', id);
      } else {
        await SupabaseService.client.from('likes').insert({'user_id': user, 'post_id': id});
      }
    } catch (_) {}
  }

  Future<void> _deleteReel(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Бичлэг устгах уу?', style: AppTextStyles.h3),
        content: Text('Энэ live/reel бичлэгийг бүрмөсөн устгана.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(d, true),
              child: Text('Устгах', style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('posts')
          .delete().eq('id', id).eq('user_id', _myId);
      if (mounted) {
        setState(() => _reels.removeWhere((r) => r['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Бичлэг устгагдлаа')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.accentStart, strokeWidth: 2))
        : _reels.isEmpty
          ? _empty(context)
          : Stack(children: [
              PageView.builder(
                controller: _pageCtrl,
                scrollDirection: Axis.vertical,
                itemCount: _reels.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _ReelPage(
                  reel: _reels[i],
                  height: h,
                  active: i == _page,
                  liked: _liked.contains(_reels[i]['id']),
                  onLike: () => _toggleLike(_reels[i]),
                  isOwn: _reels[i]['user_id'] == _myId,
                  onDelete: () => _deleteReel(_reels[i]),
                ),
              ),
              // Дээд overlay: сегмент (Following / For You) + хайлт + нэмэх
              SafeArea(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Venue эзэн create (+) — зүүн дээд
                    if (_canCreate)
                      _GlassIconButton(
                        icon: Icons.add_box_outlined,
                        onTap: () => context.push('/reels/create'),
                      )
                    else
                      const SizedBox(width: 40),
                    const Spacer(),
                    _SegmentedTabs(
                      forYou: _forYou,
                      onChanged: (v) => setState(() => _forYou = v),
                    ),
                    const Spacer(),
                    // Хайлт
                    _GlassIconButton(
                      icon: Icons.search,
                      onTap: () => context.push('/search'),
                    ),
                  ],
                ))),
            ]),
    );
  }

  Widget _empty(BuildContext context) => SafeArea(child: Stack(children: [
    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.explore_outlined, color: Colors.white38, size: 72),
      const SizedBox(height: 16),
      Text('Контент алга байна', style: AppTextStyles.h2.copyWith(color: Colors.white)),
      const SizedBox(height: 8),
      Text(_canCreate
          ? 'Эхний бичлэгээ хуваалцаарай!'
          : 'Venue эзэд богино видео нийтэлдэг',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMd.copyWith(color: Colors.white54)),
      if (_canCreate) ...[
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => context.push('/reels/create'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
            child: Text('Бичлэг нэмэх', style: AppTextStyles.btn.copyWith(color: Colors.white)))),
      ],
    ])),
    Align(alignment: Alignment.topLeft, child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Discovery', style: AppTextStyles.h2.copyWith(color: Colors.white)))),
  ]));
}

/// Дугуй шилэн товч (хайлт / нэмэх) — neon hairline glass
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.42),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline2),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Following / For You сегмент — шилэн pill, local setState toggle (visual)
class _SegmentedTabs extends StatelessWidget {
  final bool forYou;
  final ValueChanged<bool> onChanged;
  const _SegmentedTabs({required this.forYou, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _tab('Following', !forYou, () => onChanged(false)),
        _tab('For You', forYou, () => onChanged(true)),
      ]),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.bgBase.withValues(alpha: 0.6) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.neonCyan.withValues(alpha: 0.32) : Colors.transparent,
          ),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8)]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMd.copyWith(
            color: active ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.7),
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  final Map<String, dynamic> reel;
  final double height;
  final bool active;
  final bool liked;
  final VoidCallback onLike;
  final bool isOwn;
  final VoidCallback? onDelete;
  const _ReelPage({
    required this.reel, required this.height,
    this.active = true,
    required this.liked, required this.onLike,
    this.isOwn = false, this.onDelete,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with SingleTickerProviderStateMixin {
  // Spinning music disc
  late final AnimationController _spin;
  // Видеоны бодит тоглуулах явц (0..1) — доод progress bar
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final liked = widget.liked;
    final prof = reel['profiles'] as Map?;
    final username = (prof?['username'] as String? ?? 'User').replaceAll('@', '');
    final avatarUrl = prof?['avatar_url'] as String?;
    final caption = reel['caption'] as String? ?? '';
    final likes = reel['likes_count'] as int? ?? 0;
    final comments = reel['comments_count'] as int? ?? 0;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final userId = reel['user_id'];

    return Stack(fit: StackFit.expand, children: [
      // Видео (autoplay loop) — идэвхтэй reel дуутай, явцыг _progress руу
      NetworkVideo(url: reel['media_url'] as String, autoplay: true,
          active: widget.active, height: widget.height, progress: _progress),

      // Дээд скрим (уншигдах) + доод градиент
      const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.center,
          colors: [Colors.black54, Colors.transparent])))),
      const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.center,
          colors: [Colors.black87, Colors.transparent])))),

      // ── Баруун үйлдлийн рейл (premium / neon) ──
      Positioned(right: 10, bottom: 162, child: Column(children: [
        // (1) Зохиогчийн avatar — neon ring + magenta "+" badge → /creator/:id
        GestureDetector(
          onTap: () => context.push('/creator/$userId'),
          child: SizedBox(
            width: 44,
            height: 50,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                  boxShadow: [
                    BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.2), blurRadius: 10),
                  ],
                ),
                child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 38),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                    border: Border.all(color: Colors.black, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.magenta.withValues(alpha: 0.7),
                        blurRadius: 8, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 11),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 17),

        // (2) LIKE — magenta glow when liked
        _RailButton(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          iconColor: liked ? AppColors.accentEnd : Colors.white,
          glow: liked ? AppColors.accentEnd : null,
          label: '$likes',
          onTap: widget.onLike,
        ),
        const SizedBox(height: 17),

        // (3) COMMENT → /post/:id
        _RailButton(
          icon: Icons.mode_comment_outlined,
          label: '$comments',
          onTap: () => context.push('/post/${reel['id']}'),
        ),
        const SizedBox(height: 17),

        // (4) SHARE — existing send icon, styled
        const _RailButton(
          icon: Icons.send_outlined,
          label: 'Хуваалцах',
        ),
        const SizedBox(height: 17),

        // (5) BOOKMARK — visual only (no backend)
        const _RailButton(
          icon: Icons.bookmark_border,
          label: 'Хадгалах',
        ),
        const SizedBox(height: 17),

        // (6) MORE — visual
        const _RailButton(icon: Icons.more_horiz),

        // Өөрийн бичлэг (live/reel) бол устгах
        if (widget.isOwn) ...[
          const SizedBox(height: 17),
          _RailButton(
            icon: Icons.delete_outline,
            iconColor: AppColors.error,
            onTap: widget.onDelete,
          ),
        ],
        const SizedBox(height: 17),

        // Доод: эргэлддэг музикийн диск (creator avatar дотор)
        RotationTransition(
          turns: _spin,
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppColors.bgSurface, AppColors.bgBase]),
              border: Border.all(color: AppColors.hairline2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 16),
                BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.2), blurRadius: 14),
              ],
            ),
            child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 34),
          ),
        ),
      ])),

      // ── Доод зүүн: зохиогч + дагах pill + тайлбар + хөгжмийн ticker ──
      Positioned(left: 14, right: 84, bottom: 108, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(
              onTap: () => context.push('/creator/$userId'),
              child: Text('@$username', style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
                letterSpacing: -0.16,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
            ),
            const SizedBox(width: 10),
            // Cyan "Дагах" pill → /creator/:id (no new backend)
            GestureDetector(
              onTap: () => context.push('/creator/$userId'),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.neonCyan,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.45), blurRadius: 14),
                  ],
                ),
                child: Text('Дагах', style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.bgBase, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white, fontSize: 13.5, height: 1.5,
                shadows: [Shadow(color: Colors.black, blurRadius: 5)])),
          ],
          const SizedBox(height: 12),
          // Хөгжмийн ticker (visual only)
          Row(children: [
            const Icon(Icons.music_note, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Midnight Edit · Disclosure',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 12, fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)]),
              ),
            ),
          ]),
        ])),

      // ── Доод нимгэн прогресс шугам — видеоны бодит тоглуулах явц ──
      Positioned(left: 0, right: 0, bottom: 92, child: IgnorePointer(child: Container(
        height: 2.5,
        color: Colors.white.withValues(alpha: 0.16),
        child: ValueListenableBuilder<double>(
          valueListenable: _progress,
          builder: (_, p, __) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: p <= 0 ? 0.001 : p.clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(
              color: AppColors.neonCyan,
              boxShadow: [
                BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.6), blurRadius: 10),
              ],
            )),
          ),
        ),
      ))),
    ]);
  }
}

/// Рейлийн нэг товч — neon drop-shadow + label
class _RailButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? glow;
  final String? label;
  final VoidCallback? onTap;
  const _RailButton({
    required this.icon,
    this.iconColor = Colors.white,
    this.glow,
    this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: glow != null
              ? BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: glow!.withValues(alpha: 0.85), blurRadius: 14),
                ])
              : null,
          child: Icon(icon, color: iconColor, size: 26, shadows: const [
            Shadow(color: Colors.black54, blurRadius: 6),
          ]),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label!, style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
        ],
      ]),
    );
  }
}
