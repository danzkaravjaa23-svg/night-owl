import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/router/app_router.dart' show AppRoutes;
import '../../profile/widgets/block_report_sheet.dart';

class CreatorScreen extends StatefulWidget {
  final String creatorId;
  const CreatorScreen({super.key, required this.creatorId});
  @override State<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends State<CreatorScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _isFollowing = false;
  bool _followLoading = false;
  int _tab = 0; // 0 = Posts, 1 = Reels (профайлтай ижил icon таб)

  bool _isVideo(String url) => url.endsWith('.mp4') || url.endsWith('.webm') ||
      url.endsWith('.mov') || url.endsWith('.m4v');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = SupabaseService.currentUser?.id;
      final results = await Future.wait(<Future<dynamic>>[
        SupabaseService.client.from('profiles').select()
            .eq('id', widget.creatorId).maybeSingle(),
        SupabaseService.client.from('posts').select('id, media_url, likes_count')
            .eq('user_id', widget.creatorId)
            .order('created_at', ascending: false).limit(24),
        if (me != null && me != widget.creatorId)
          SupabaseService.client.from('follows')
              .select().eq('follower_id', me)
              .eq('following_id', widget.creatorId).maybeSingle()
        else
          Future<dynamic>.value(null),
      ]);

      if (mounted) {
        setState(() {
        _profile     = results[0] as Map<String, dynamic>?;
        _posts       = (results[1] as List).cast<Map<String, dynamic>>();
        _isFollowing = results[2] != null;
        _loading     = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null || _followLoading) return;
    setState(() => _followLoading = true);
    try {
      if (_isFollowing) {
        await SupabaseService.client.from('follows').delete()
            .eq('follower_id', me).eq('following_id', widget.creatorId);
        setState(() => _isFollowing = false);
      } else {
        await SupabaseService.client.from('follows')
            .insert({'follower_id': me, 'following_id': widget.creatorId});
        setState(() => _isFollowing = true);
      }
    } catch (_) {}
    if (mounted) setState(() => _followLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final username  = _profile?['username'] as String? ?? 'User';
    final handle    = username.replaceAll('@', '');
    final bio       = _profile?['bio'] as String?;
    final avatarUrl = _profile?['avatar_url'] as String?;
    final coverUrl  = _profile?['cover_url'] as String?;
    final initial   = handle.isNotEmpty ? handle[0].toUpperCase() : '?';
    final followers = _profile?['followers_count'] as int? ?? 0;
    final following = _profile?['following_count'] as int? ?? 0;
    final isMe = SupabaseService.currentUser?.id == widget.creatorId;

    // Таб-аас хамаарч grid-д харуулах постууд (Reels = зөвхөн видео)
    final shown = _tab == 1
        ? _posts
            .where((p) => _isVideo((p['media_url'] as String?) ?? ''))
            .toList()
        : _posts;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentStart))
          : CustomScrollView(slivers: [
              // ── Hero: бүтэн өргөн cover + голд давхарласан avatar (профайлтай ижил) ──
              SliverToBoxAdapter(
                child: Column(children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      _CreatorCover(url: coverUrl),
                      // Дээд бар — буцах + options, cover дээгүүр glass товч
                      Positioned(
                        top: 0, left: 0, right: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                            child: Row(children: [
                              _GlassRoundBtn(
                                icon: Icons.arrow_back_ios_new,
                                onTap: () => context.pop(),
                              ),
                              const Spacer(),
                              if (isMe)
                                _GlassRoundBtn(
                                  icon: Icons.settings_outlined,
                                  onTap: () =>
                                      context.push(AppRoutes.settings),
                                )
                              else
                                _GlassRoundBtn(
                                  icon: Icons.more_horiz,
                                  onTap: () => showUserOptionsSheet(
                                    context,
                                    userId: widget.creatorId,
                                    username: handle,
                                    onBlocked: () => context.pop(),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ),
                      // Avatar 96 — cover-ийг -48 давхарлан голд, неон glow
                      Positioned(
                        bottom: -48,
                        child: Container(
                          width: 96, height: 96,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.bgBase,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.neonCyan
                                    .withValues(alpha: 0.30),
                                blurRadius: 24, spreadRadius: -2),
                              BoxShadow(
                                color: AppColors.magenta
                                    .withValues(alpha: 0.22),
                                blurRadius: 28, spreadRadius: -4),
                            ],
                          ),
                          child: AppAvatar(
                              imageUrl: avatarUrl,
                              initial: initial,
                              size: 88,
                              showRing: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                      // ── Нэр (голд, h2) + @handle eyebrow ──
                      Text(handle,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.h2),
                      const SizedBox(height: 4),
                      Text('@$handle',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelSm.copyWith(
                              color: AppColors.neonCyan,
                              letterSpacing: 1.2)),

                      // ── Bio (голд, 2 мөр) ──
                      if (bio != null && bio.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(bio,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.45)),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // ── Stats — нэг glass card, hairline хуваагчтай (профайлтай ижил) ──
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.hairline),
                          boxShadow: AppColors.shadowCard,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Row(children: [
                          Expanded(
                              child:
                                  _Stat(label: 'ПОСТ', value: _posts.length)),
                          Container(
                              width: 1, height: 36, color: AppColors.hairline),
                          Expanded(
                              child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => context.push(
                                  '/follows/${widget.creatorId}?tab=followers'),
                              child: _Stat(
                                  label: 'ДАГАГЧ',
                                  value: followers,
                                  gradient: true)),
                          )),
                          Container(
                              width: 1, height: 36, color: AppColors.hairline),
                          Expanded(
                              child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => context.push(
                                  '/follows/${widget.creatorId}?tab=following'),
                              child:
                                  _Stat(label: 'ДАГАЖ БУЙ', value: following)),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 16),

                      // ── Action мөр — бүтэн өргөн pill товчнууд ──
                      if (isMe)
                        GradientButton(
                          label: 'Профайл засах',
                          height: 48,
                          borderRadius: 999,
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white, size: 16),
                          onPressed: () => context.push(AppRoutes.setup),
                        )
                      else
                        Row(children: [
                          // Дагах / Дагасан — gradient ↔ glass pill
                          Expanded(
                            child: _FollowBtn(
                                isFollowing: _isFollowing,
                                loading: _followLoading,
                                onTap: _toggleFollow),
                          ),
                          const SizedBox(width: 12),
                          // Мессеж — glass pill
                          Expanded(
                            child: _GlassPillBtn(
                              label: 'Мессеж',
                              icon: Icons.send_outlined,
                              onTap: () =>
                                  context.push('/dm/${widget.creatorId}'),
                            ),
                          ),
                        ]),
                      const SizedBox(height: 28),

                      // ── Icon-only таб (grid / reels) — профайлтай ижил underline ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _IconTab(
                              icon: Icons.grid_on,
                              selected: _tab == 0,
                              onTap: () => setState(() => _tab = 0)),
                          const SizedBox(width: 40),
                          _IconTab(
                              icon: Icons.play_arrow_rounded,
                              selected: _tab == 1,
                              onTap: () => setState(() => _tab = 1)),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ]),
              ),

              // ── Posts grid — нягт 2px завсартай template grid ──
              shown.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        illustration: _tab == 1
                            ? 'assets/images/illustrations/empty_creator.svg'
                            : 'assets/images/illustrations/empty_profile.svg',
                        title: _tab == 1
                            ? 'Бичлэг алга байна'
                            : 'Пост алга байна',
                      ))
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate((_, i) {
                          final p = shown[i];
                          final url = p['media_url'] as String?;
                          final likes = p['likes_count'] as int? ?? 0;
                          final isVid = url != null && _isVideo(url);
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                            onTap: () => context.push('/post/${p['id']}'),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Stack(fit: StackFit.expand, children: [
                                if (isVid)
                                  // Видеоны эхний кадрыг cover болгож харуулна
                                  // (профайлын grid-тэй ижил — posterOnly дарагдана)
                                  NetworkVideo(url: url,
                                      posterOnly: true, showPosterIcon: false)
                                else if (url != null)
                                  CachedNetworkImage(
                                    imageUrl: url, fit: BoxFit.cover,
                                    memCacheWidth: 400,
                                    fadeInDuration:
                                        const Duration(milliseconds: 150),
                                    placeholder: (_, __) =>
                                        Container(color: AppColors.bgSurface),
                                    errorWidget: (_, __, ___) =>
                                        Container(color: AppColors.bgSurface))
                                else
                                  Container(color: AppColors.bgSurface),
                                // Видео badge — баруун дээд (профайлтай ижил)
                                if (isVid)
                                  Positioned(
                                    top: 6, right: 6,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: AppColors.bgBase
                                            .withValues(alpha: 0.5),
                                        border: Border.all(
                                            color: AppColors.hairline2),
                                      ),
                                      child: const Icon(Icons.videocam_rounded,
                                          color: AppColors.neonCyan, size: 14),
                                    ),
                                  ),
                                // Likes overlay on hover
                                Positioned(bottom: 6, left: 6,
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.favorite,
                                      color: Colors.white, size: 13),
                                    const SizedBox(width: 3),
                                    Text(_fmt(likes),
                                      style: const TextStyle(
                                        color: Colors.white, fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        shadows: [Shadow(blurRadius: 4,
                                          color: Colors.black)])),
                                  ])),
                              ]),
                            ),
                            ),
                          );
                        }, childCount: _posts.length),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
                      )),
            ]),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n/1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Creator cover — бүтэн өргөн 160, доошоо bgBase руу уусна,
/// cover байхгүй бол неон gradient wash fallback.
class _CreatorCover extends StatelessWidget {
  final String? url;
  const _CreatorCover({required this.url});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        if (url != null && url!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            memCacheWidth: 900,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => Container(color: AppColors.bgSurface),
            errorWidget: (_, __, ___) => _fallback())
        else
          _fallback(),
        // Доод fade — void bg руу бүрэн уусаж avatar ялгарна
        const DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0x66050505), AppColors.bgBase],
            stops: [0.4, 0.75, 1.0]))),
      ]),
    );
  }

  // Неон wash — magenta дээрээс void bg руу уусна (хуучин header-ийн өнгө)
  Widget _fallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomCenter,
            colors: [
              AppColors.magenta.withValues(alpha: 0.22),
              AppColors.accentPurple.withValues(alpha: 0.10),
              AppColors.bgBase,
            ],
            stops: const [0.0, 0.45, 1.0])),
      );
}

/// Glass round button — cover дээгүүрх navigation товч
class _GlassRoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassRoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgBase.withValues(alpha: 0.55),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 19),
          ),
        ),
      );
}

// ─── Icon-only таб — сонгогдсон үед cyan underline glow bar 24×3 ───
// (профайлын дэлгэцтэй ижил харагдац — creator mirror)
class _IconTab extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _IconTab(
      {required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 24,
                  color:
                      selected ? AppColors.neonCyan : AppColors.textTertiary),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 24,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color:
                      selected ? AppColors.neonCyan : Colors.transparent,
                  boxShadow: selected
                      ? AppColors.glowShadow(AppColors.neonCyan)
                      : null,
                ),
              ),
            ]),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final bool gradient;
  const _Stat({required this.label, required this.value, this.gradient = false});
  @override
  Widget build(BuildContext context) {
    final numStyle = AppTextStyles.displaySm.copyWith(fontSize: 22, height: 1);
    final numWidget = gradient
        ? ShaderMask(
            shaderCallback: (r) => AppColors.accentGradient.createShader(r),
            child: Text(_fmt(value),
                style: numStyle.copyWith(color: Colors.white)),
          )
        : Text(_fmt(value), style: numStyle);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      numWidget,
      const SizedBox(height: 6),
      Text(label,
          style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
              letterSpacing: 1.2)),
    ]);
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n/1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Glass pill товч — бүтэн өргөн (Мессеж)
class _GlassPillBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GlassPillBtn(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: AppColors.textPrimary),
              const SizedBox(width: 7),
              Text(label,
                  style: AppTextStyles.btn
                      .copyWith(color: AppColors.textPrimary)),
            ]),
          ),
        ),
      );
}

/// Дагах / Дагасан — бүтэн өргөн pill (gradient ↔ glass)
class _FollowBtn extends StatelessWidget {
  final bool isFollowing;
  final bool loading;
  final VoidCallback onTap;
  const _FollowBtn({
    required this.isFollowing,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filled = !isFollowing; // Дагах = gradient, Дагасан = glass
    return MouseRegion(
      cursor: loading ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? AppColors.accentGradient : null,
          color: filled ? null : AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: filled ? null : Border.all(color: AppColors.hairline2),
          // Primary үед неон glow
          boxShadow: filled
              ? AppColors.glowShadow(AppColors.accentStart)
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else ...[
            Icon(isFollowing ? Icons.check : Icons.person_add_alt_1,
              size: 16, color: filled ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 7),
            Text(isFollowing ? 'Дагасан' : 'Дагах',
                style: AppTextStyles.btn.copyWith(
                    color: filled ? Colors.white : AppColors.textPrimary)),
          ],
        ]),
      )));
  }
}
