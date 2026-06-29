import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../models/story.dart';
import '../../feed/providers/stories_provider.dart';
import '../../feed/screens/story_viewer_screen.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/invite_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _tab = 0; // 0 = Posts, 1 = Reels
  int _refreshTick = 0; // pull-to-refresh-д grid дахин ачаалах

  @override
  Widget build(BuildContext context) {
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

          return RefreshIndicator(
            color: AppColors.accentStart,
            backgroundColor: AppColors.bgElevated,
            onRefresh: () async {
              ref.invalidate(currentProfileProvider);
              ref.invalidate(storiesProvider);
              setState(() => _refreshTick++);
              await ref.read(currentProfileProvider.future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
            // ── App bar ──
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.bgBase,
              actions: [
                IconButton(
                  onPressed: () => context.push(AppRoutes.saved),
                  icon: const Icon(Icons.bookmark_border, color: AppColors.textPrimary)),
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
                      // posts_count нь trigger-ээр хадгалагддаг — бүх мөр татах
                      // шаардлагагүй (500к scale-д хямд)
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Stat(
                              count: _fmt(profile.postsCount),
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
                                      AppColors.accentStart.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.accentStart
                                          .withValues(alpha: 0.3)),
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
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final link =
                            'https://nightowl.ub/u/${profile.username ?? profile.id}';
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Профайл холбоос хуулагдлаа 🔗 $link')));
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.person_add_outlined,
                      onTap: () => showInviteSheet(context),
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
                        border: Border.all(color: AppColors.accentStart.withValues(alpha: 0.5))),
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
                  // 🛡️ Админ — мэдээллүүд (зөвхөн админд)
                  if (profile.isAdmin) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => context.push(AppRoutes.adminPanel),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.5))),
                        child: Row(children: [
                          const Icon(Icons.shield_outlined,
                            color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text('Админ панел',
                            style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary))),
                          const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ]),
              ),
            ),

            // ── Tab bar (Posts / Reels) ──
            SliverToBoxAdapter(
              child: Row(children: [
                _ProfileTab(
                  icon: Icons.grid_on,
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0)),
                _ProfileTab(
                  icon: Icons.slow_motion_video,
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1)),
              ]),
            ),

            // ── Grid (tab-аас хамаарна) ──
            _PostsGrid(
                key: ValueKey(_refreshTick),
                userId: profile.id, reelsOnly: _tab == 1),
          ]),
          );
        },
      ),
    );
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

// ─── Профайлын tab ───
class _ProfileTab extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ProfileTab({required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: const BorderSide(color: AppColors.hairline),
            bottom: BorderSide(
              color: selected ? AppColors.textPrimary : Colors.transparent,
              width: 1.5),
          ),
        ),
        child: Icon(icon,
            color: selected ? AppColors.textPrimary : AppColors.textTertiary,
            size: 24),
      ),
    ),
  );
}

// ─── Posts grid (cursor pagination / infinite scroll) ───
class _PostsGrid extends StatefulWidget {
  final String userId;
  final bool reelsOnly;
  const _PostsGrid({super.key, required this.userId, this.reelsOnly = false});

  @override
  State<_PostsGrid> createState() => _PostsGridState();
}

class _PostsGridState extends State<_PostsGrid> {
  static const _pageSize = 30;
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _hasMore = true;
  DateTime? _cursor;

  static bool _isVid(String? url) => url != null && (
      url.endsWith('.mp4') || url.endsWith('.webm') ||
      url.endsWith('.mov') || url.endsWith('.m4v'));

  // Профайлын постыг (live/reel/зураг) шууд устгах (удаан дарахад)
  Future<void> _confirmDeleteTile(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Устгах уу?', style: AppTextStyles.h3),
        content: Text('Энэ пост/бичлэгийг бүрмөсөн устгана.',
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
    final me = SupabaseService.currentUser?.id;
    try {
      await SupabaseService.client.from('posts')
          .delete().eq('id', id).eq('user_id', me!);
      if (mounted) {
        setState(() => _posts.removeWhere((p) => p['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Устгагдлаа')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    try {
      var q = SupabaseService.client
          .from('posts')
          .select('id, media_url, likes_count, created_at')
          .eq('user_id', widget.userId);
      if (_cursor != null) {
        q = q.lt('created_at', _cursor!.toIso8601String());
      }
      final data = await q
          .order('created_at', ascending: false)
          .limit(_pageSize);
      final rows = (data as List).cast<Map<String, dynamic>>();
      if (rows.isNotEmpty) {
        _cursor = DateTime.tryParse(rows.last['created_at'] as String? ?? '');
      }
      _hasMore = rows.length == _pageSize;
      _posts.addAll(rows);
    } catch (_) {
      _hasMore = false;
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.reelsOnly
        ? _posts.where((p) => _isVid(p['media_url'] as String?)).toList()
        : _posts;

    // Хоосон (бүгд ачаалагдсан)
    if (shown.isEmpty && !_hasMore && !_loading) {
      return SliverToBoxAdapter(
        child: Center(child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.reelsOnly ? '🎬' : '📸', style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(widget.reelsOnly ? 'No reels yet' : 'No posts yet',
                style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(widget.reelsOnly
                    ? 'Share a video to see it here'
                    : 'Share your first night out!',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
          ]),
        )),
      );
    }

    return SliverMainAxisGroup(slivers: [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _tile(shown[i]),
          childCount: shown.length,
        ),
      ),
      // Footer — доод хүрэхэд дараагийн хуудсыг автоматаар ачаална
      SliverToBoxAdapter(
        child: _hasMore
            ? Builder(builder: (_) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _loadMore());
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(
                      color: AppColors.accentStart, strokeWidth: 2)),
                );
              })
            : const SizedBox(height: 24),
      ),
    ]);
  }

  Widget _tile(Map<String, dynamic> post) {
    final mediaUrl = post['media_url'] as String?;
    final likes = post['likes_count'] as int? ?? 0;
    final isVideo = _isVid(mediaUrl);

    return GestureDetector(
      onTap: () async {
        await context.push('/post/${post['id']}');
        // Detail-аас буцахад устгасан/засагдсаныг тусгахаар grid дахин ачаална
        if (mounted) {
          setState(() { _posts.clear(); _cursor = null; _hasMore = true; });
          _loadMore();
        }
      },
      onLongPress: () => _confirmDeleteTile(post['id'] as String),
      child: Stack(fit: StackFit.expand, children: [
        if (mediaUrl != null && !isVideo)
          CachedNetworkImage(
            imageUrl: mediaUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.bgSurface),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.bgSurface,
              child: const Icon(Icons.image_not_supported_outlined,
                  color: AppColors.textTertiary)),
          )
        else if (isVideo)
          // Видеоны эхний кадрыг cover болгож харуулна (icon-гүй — grid өөрөө
          // videocam badge нэмдэг; posterOnly нь pointerEvents=none тул дарагдана).
          NetworkVideo(url: mediaUrl!, posterOnly: true, showPosterIcon: false)
        else
          Container(
            color: AppColors.bgSurface,
            child: const Icon(Icons.image_outlined, color: AppColors.textTertiary)),

        if (isVideo)
          const Positioned(
            top: 6, right: 6,
            child: Icon(Icons.videocam_rounded,
                color: Colors.white, size: 16,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
          ),

        if (likes > 0)
          Positioned(
            bottom: 6, left: 6,
            child: Row(children: [
              const Icon(Icons.favorite, color: Colors.white, size: 12),
              const SizedBox(width: 3),
              Text('$likes', style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)])),
            ]),
          ),
      ]),
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
