import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../models/story.dart';
import '../../feed/providers/stories_provider.dart';
import '../../feed/screens/story_viewer_screen.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentStart)),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          if (profile == null) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('👤', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text('Profile not found', style: AppTextStyles.h2),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.go(AppRoutes.setup),
                  child: const Text('Set up profile'),
                ),
              ]),
            );
          }

          // Өөрийн идэвхтэй story (байвал avatar дээр ринг харагдана)
          final myRing = ref.watch(storiesProvider).maybeWhen<StoryRing?>(
            data: (rings) {
              for (final r in rings) {
                if (r.userId == profile.id) return r;
              }
              return null;
            },
            orElse: () => null,
          );

          return CustomScrollView(slivers: [
            // ── App bar ──
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bgBase,
              actions: [
                IconButton(
                  onPressed: () => context.push(AppRoutes.settings),
                  icon: const Icon(Icons.menu, color: AppColors.textPrimary)),
              ],
              title: Text('@${profile.username ?? 'profile'}',
                  style: AppTextStyles.h2),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // ── Avatar + stats ──
                  Row(children: [
                    _ProfileStoryAvatar(
                      avatarUrl: profile.avatarUrl,
                      initial: profile.initial,
                      ring: myRing,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: FutureBuilder<int>(
                        future: _fetchPostCount(profile.id),
                        builder: (ctx, snap) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _Stat(
                                count: '${snap.data ?? profile.postsCount}',
                                label: 'Posts'),
                            _Stat(
                                count: _fmt(profile.followersCount),
                                label: 'Followers'),
                            _Stat(
                                count: _fmt(profile.followingCount),
                                label: 'Following'),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  // ── Name + bio ──
                  if (profile.name?.isNotEmpty == true)
                    Text(profile.name!, style: AppTextStyles.labelLg),
                  if (profile.bio?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(profile.bio!,
                        style: AppTextStyles.bodyMd.copyWith(
                            color: AppColors.textSecondary, height: 1.4)),
                  ],

                  // ── Interests ──
                  if (profile.interests.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: profile.interests
                          .map((tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.accentStart.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.accentStart
                                          .withOpacity(0.3)),
                                ),
                                child: Text(tag,
                                    style: AppTextStyles.bodyXs.copyWith(
                                        color: AppColors.accentStart)),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── Buttons ──
                  Row(children: [
                    Expanded(
                      child: GradientButton(
                        label: 'Edit Profile',
                        height: 38,
                        onPressed: () => context.push(AppRoutes.setup),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.share_outlined,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Share link copied!')));
                      },
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.person_add_outlined,
                      onTap: () =>
                          context.push(AppRoutes.affiliateUnlock),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // 🏪 Бизнес самбар (Газраа удирдах / Event / Live)
                  GestureDetector(
                    onTap: () => context.push(AppRoutes.business),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.accentStart.withOpacity(0.5))),
                      child: Row(children: [
                        const Icon(Icons.storefront_outlined,
                          color: AppColors.accentStart, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Бизнес самбар',
                          style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary))),
                        Text('Газраа удирдах · Event · Live',
                          style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
                        const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.hairline),
                ]),
              ),
            ),

            // ── Posts grid ──
            _PostsGrid(userId: profile.id),
          ]);
        },
      ),
    );
  }

  Future<int> _fetchPostCount(String userId) async {
    try {
      final data = await SupabaseService.client
          .from('posts')
          .select('id')
          .eq('user_id', userId);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hairline2),
        color: AppColors.bgSurface,
      ),
      child: Icon(icon, color: AppColors.textPrimary, size: 18),
    ),
  );
}

// ─── Posts grid ───
class _PostsGrid extends StatelessWidget {
  final String userId;
  const _PostsGrid({required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SupabaseService.client
          .from('posts')
          .select('id, media_url, likes_count')
          .eq('user_id', userId)
          .order('created_at', ascending: false),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: CircularProgressIndicator(
                    color: AppColors.accentStart),
              ),
            ),
          );
        }

        final posts = (snap.data as List?) ?? [];
        if (posts.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('📸', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text('No posts yet', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  Text('Share your first night out!',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.textSecondary)),
                ]),
              ),
            ),
          );
        }

        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 1.5,
            mainAxisSpacing: 1.5,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final post = posts[i] as Map<String, dynamic>;
              final mediaUrl = post['media_url'] as String?;
              final likes = post['likes_count'] as int? ?? 0;

              final isVideo = mediaUrl != null && (
                mediaUrl.endsWith('.mp4') || mediaUrl.endsWith('.webm') ||
                mediaUrl.endsWith('.mov') || mediaUrl.endsWith('.m4v'));

              return GestureDetector(
                onTap: () => context.push('/post/${post['id']}'),
                child: Stack(fit: StackFit.expand, children: [
                  if (mediaUrl != null && !isVideo)
                    CachedNetworkImage(
                      imageUrl: mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.bgSurface),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.bgSurface,
                        child: const Icon(Icons.image_not_supported_outlined,
                            color: AppColors.textTertiary)),
                    )
                  else if (isVideo)
                    NetworkVideo(url: mediaUrl, posterOnly: true)
                  else
                    Container(
                      color: AppColors.bgSurface,
                      child: const Icon(Icons.image_outlined,
                          color: AppColors.textTertiary)),

                  // Likes overlay
                  if (likes > 0)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Row(children: [
                        const Icon(Icons.favorite,
                            color: Colors.white, size: 12),
                        const SizedBox(width: 3),
                        Text('$likes',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(blurRadius: 4,
                                      color: Colors.black54)
                                ])),
                      ]),
                    ),
                ]),
              );
            },
            childCount: posts.length,
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String count, label;
  const _Stat({required this.count, required this.label});

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(count,
        style: AppTextStyles.h2.copyWith(fontSize: 18)),
    const SizedBox(height: 2),
    Text(label,
        style: AppTextStyles.bodyXs
            .copyWith(color: AppColors.textSecondary)),
  ]);
}

/// Профайлын avatar — идэвхтэй story байвал өнгөт ринг + дарж үзэх,
/// доор нь "+" товч (шинэ story нэмэх). Instagram маягийн.
class _ProfileStoryAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final StoryRing? ring;
  const _ProfileStoryAvatar({
    required this.avatarUrl,
    required this.initial,
    required this.ring,
  });

  @override
  Widget build(BuildContext context) {
    final hasStory = ring != null;
    return Stack(clipBehavior: Clip.none, children: [
      GestureDetector(
        onTap: hasStory
          ? () => Navigator.of(context).push(PageRouteBuilder(
              opaque: false,
              pageBuilder: (_, __, ___) => StoryViewerScreen(rings: [ring!]),
              transitionsBuilder: (_, a, __, c) =>
                  FadeTransition(opacity: a, child: c)))
          : () => context.push('/story/create'),
        child: Container(
          width: 88, height: 88,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: hasStory ? AppColors.accentGradient : null,
            color: hasStory ? null : Colors.transparent,
            border: hasStory ? null
                : Border.all(color: AppColors.hairline, width: 2)),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.bgBase),
            child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 74),
          ),
        ),
      ),
      // "+" товч → шинэ story
      Positioned(
        right: 0, bottom: 0,
        child: GestureDetector(
          onTap: () => context.push('/story/create'),
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradient,
              border: Border.all(color: AppColors.bgBase, width: 2.5)),
            child: const Icon(Icons.add, color: Colors.white, size: 15)),
        ),
      ),
    ]);
  }
}
