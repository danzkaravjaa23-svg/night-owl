import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
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

      if (mounted) setState(() {
        _profile     = results[0] as Map<String, dynamic>?;
        _posts       = (results[1] as List).cast<Map<String, dynamic>>();
        _isFollowing = results[2] != null;
        _loading     = false;
      });
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
    final bio       = _profile?['bio'] as String?;
    final avatarUrl = _profile?['avatar_url'] as String?;
    final initial   = username.replaceAll('@', '').isNotEmpty
        ? username.replaceAll('@', '')[0].toUpperCase() : '?';
    final followers = _profile?['followers_count'] as int? ?? 0;
    final following = _profile?['following_count'] as int? ?? 0;
    final isMe = SupabaseService.currentUser?.id == widget.creatorId;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentStart))
          : CustomScrollView(slivers: [
              // ── App bar with gradient header ──
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.bgBase,
                leading: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
                actions: [
                  if (isMe)
                    IconButton(
                      onPressed: () => context.push(AppRoutes.settings),
                      icon: const Icon(Icons.settings_outlined, size: 22))
                  else
                    IconButton(
                      onPressed: () => showUserOptionsSheet(
                        context,
                        userId: widget.creatorId,
                        username: username.replaceAll('@', ''),
                        onBlocked: () => context.pop(),
                      ),
                      icon: const Icon(Icons.more_horiz, size: 24)),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [
                          AppColors.accentStart.withValues(alpha: 0.3),
                          AppColors.bgBase,
                        ])),
                  ),
                ),
              ),

              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // ── Avatar + action row ──
                  Row(children: [
                    AppAvatar(imageUrl: avatarUrl, initial: initial,
                      size: 84, showRing: true),
                    const Spacer(),
                    if (!isMe) ...[
                      _ActionBtn(
                        label: 'Message',
                        icon: Icons.send_outlined,
                        onTap: () => context.push('/dm/${widget.creatorId}'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (isMe)
                      _ActionBtn(
                        label: 'Edit Profile',
                        icon: Icons.edit_outlined,
                        onTap: () => context.push(AppRoutes.setup))
                    else
                      _FollowBtn(
                        isFollowing: _isFollowing,
                        loading: _followLoading,
                        onTap: _toggleFollow),
                  ]),
                  const SizedBox(height: 14),

                  // ── Name & bio ──
                  Text(username, style: AppTextStyles.h2),
                  if (bio != null && bio.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(bio, style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textSecondary, height: 1.4)),
                  ],
                  const SizedBox(height: 18),

                  // ── Stats ──
                  Row(children: [
                    _Stat(label: 'Posts',     value: _posts.length),
                    const SizedBox(width: 28),
                    _Stat(label: 'Followers', value: followers),
                    const SizedBox(width: 28),
                    _Stat(label: 'Following', value: following),
                  ]),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.hairline),
                  const SizedBox(height: 4),
                ]),
              )),

              // ── Posts grid ──
              _posts.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        illustration: 'assets/images/illustrations/empty_profile.svg',
                        title: 'No posts yet',
                      ))
                  : SliverPadding(
                      padding: const EdgeInsets.all(2),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate((_, i) {
                          final p = _posts[i];
                          final url = p['media_url'] as String?;
                          final likes = p['likes_count'] as int? ?? 0;
                          return GestureDetector(
                            onTap: () => context.push('/post/${p['id']}'),
                            child: Container(
                              margin: const EdgeInsets.all(1.5),
                              color: AppColors.bgSurface,
                              child: Stack(fit: StackFit.expand, children: [
                                if (url != null && _isVideo(url))
                                  Container(color: Colors.black,
                                    child: const Center(child: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Colors.white54, size: 38)))
                                else if (url != null)
                                  CachedNetworkImage(
                                    imageUrl: url, fit: BoxFit.cover,
                                    placeholder: (_, __) =>
                                        Container(color: AppColors.bgSurface),
                                    errorWidget: (_, __, ___) =>
                                        Container(color: AppColors.bgSurface))
                                else
                                  Container(color: AppColors.bgSurface),
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
                          );
                        }, childCount: _posts.length),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, mainAxisSpacing: 0, crossAxisSpacing: 0),
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

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_fmt(value), style: AppTextStyles.h2),
      Text(label, style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
    ]);
  String _fmt(int n) {
    if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n/1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.icon,
    required this.onTap, this.filled = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        gradient: filled ? AppColors.accentGradient : null,
        color: filled ? null : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: filled ? null : Border.all(color: AppColors.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15,
          color: filled ? Colors.white : AppColors.textPrimary),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          color: filled ? Colors.white : AppColors.textPrimary,
          fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ));
}

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
    final filled = !isFollowing; // Follow = filled, Following = outline
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: filled ? AppColors.accentGradient : null,
          color: filled ? null : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: AppColors.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else ...[
            Icon(isFollowing ? Icons.check : Icons.person_add_alt_1,
              size: 15, color: filled ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 5),
            Text(isFollowing ? 'Following' : 'Follow', style: TextStyle(
              color: filled ? Colors.white : AppColors.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ]),
      ));
  }
}

