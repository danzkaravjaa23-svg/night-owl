import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
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
              titleSpacing: 20,
              toolbarHeight: 64,
              actions: [
                // 💬 Чат (DM)
                _GlassRoundBtn(
                  icon: Icons.chat_bubble_outline,
                  onTap: () => context.push(AppRoutes.dmList),
                ),
                const SizedBox(width: 8),
                // 🔖 Хадгалсан
                _GlassRoundBtn(
                  icon: Icons.bookmark_border,
                  onTap: () => context.push(AppRoutes.saved),
                ),
                const SizedBox(width: 8),
                // 🔗 Хуваалцах (clipboard)
                _GlassRoundBtn(
                  icon: Icons.ios_share,
                  onTap: () => _shareProfile(context, profile),
                ),
                const SizedBox(width: 8),
                // ⚙️ Тохиргоо
                _GlassRoundBtn(
                  icon: Icons.menu,
                  onTap: () => context.push(AppRoutes.settings),
                ),
                const SizedBox(width: 20),
              ],
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('@${profile.username ?? 'profile'}',
                      style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.neonCyan, letterSpacing: 1.6)),
                  const SizedBox(height: 2),
                  Text('Профайл', style: AppTextStyles.h1),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                  // ── Avatar (centered, neon ring) ──
                  _ProfileStoryAvatar(
                    avatarUrl: profile.avatarUrl,
                    initial: profile.initial,
                    ring: myRing,
                  ),
                  const SizedBox(height: 16),

                  // ── Name (centered) ──
                  if (profile.name?.isNotEmpty == true)
                    Text(profile.name!,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.displaySm.copyWith(fontSize: 22)),

                  // ── Username eyebrow under name ──
                  const SizedBox(height: 2),
                  Text('@${profile.username ?? 'profile'}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.mono
                          .copyWith(color: AppColors.textSecondary)),

                  // ── Bio (centered) ──
                  if (profile.bio?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(profile.bio!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.textSecondary, height: 1.45)),
                    ),
                  ],

                  // ── Interests (cyan chips, centered) ──
                  if (profile.interests.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: profile.interests
                          .map((tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 5),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.neonCyan.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.neonCyan
                                          .withValues(alpha: 0.35)),
                                ),
                                child: Text(tag,
                                    style: AppTextStyles.bodyXs.copyWith(
                                        color: AppColors.neonCyan,
                                        fontWeight: FontWeight.w600)),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // ── Stats (one glass block, 3 columns) ──
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(children: [
                      Expanded(
                          child: _Stat(
                              count: _fmt(profile.postsCount),
                              label: 'Пост')),
                      Container(
                          width: 1, height: 34, color: AppColors.hairline),
                      Expanded(
                          child: _Stat(
                              count: _fmt(profile.followersCount),
                              label: 'Дагагч',
                              gradient: true)),
                      Container(
                          width: 1, height: 34, color: AppColors.hairline),
                      Expanded(
                          child: _Stat(
                              count: _fmt(profile.followingCount),
                              label: 'Дагаж буй')),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // ── Action buttons row ──
                  Row(children: [
                    Expanded(
                      child: GradientButton(
                        label: 'Edit Profile',
                        height: 44,
                        icon: const Icon(Icons.edit_outlined,
                            color: Colors.white, size: 16),
                        onPressed: () => context.push(AppRoutes.setup),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.ios_share,
                      onTap: () => _shareProfile(context, profile),
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
                      padding: const EdgeInsets.symmetric(
                          vertical: 13, horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.neonCyan.withValues(alpha: 0.45)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.storefront_outlined,
                            color: AppColors.neonCyan, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text('Бизнес самбар',
                                style: AppTextStyles.labelMd
                                    .copyWith(color: AppColors.textPrimary))),
                        Text('Газраа удирдах · Event · Live',
                            style: AppTextStyles.bodyXs
                                .copyWith(color: AppColors.textSecondary)),
                        const Icon(Icons.chevron_right,
                            color: AppColors.textTertiary, size: 18),
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
                        padding: const EdgeInsets.symmetric(
                            vertical: 13, horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.5)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.shield_outlined,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text('Админ панел',
                                  style: AppTextStyles.labelMd
                                      .copyWith(color: AppColors.textPrimary))),
                          const Icon(Icons.chevron_right,
                              color: AppColors.textTertiary, size: 18),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // ── Segmented control (Постууд / Reels) ──
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(children: [
                      _ProfileTab(
                          icon: Icons.grid_on,
                          label: 'Постууд',
                          selected: _tab == 0,
                          onTap: () => setState(() => _tab = 0)),
                      _ProfileTab(
                          icon: Icons.slow_motion_video,
                          label: 'Reels',
                          selected: _tab == 1,
                          onTap: () => setState(() => _tab = 1)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                ]),
              ),
            ),

            // ── Grid (tab-аас хамаарна) ──
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: _PostsGrid(
                  key: ValueKey(_refreshTick),
                  userId: profile.id,
                  reelsOnly: _tab == 1),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
          );
        },
      ),
    );
  }

  // Профайл холбоосыг clipboard-д хуулах (одоо байгаа handler)
  Future<void> _shareProfile(BuildContext context, dynamic profile) async {
    HapticFeedback.lightImpact();
    final link =
        'https://nightowl.ub/u/${profile.username ?? profile.id}';
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Профайл холбоос хуулагдлаа 🔗 $link')));
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Glass round button (top bar)
class _GlassRoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassRoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgSurface.withValues(alpha: 0.7),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 19),
        ),
      );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline2),
            color: AppColors.bgSurface,
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 19),
        ),
      );
}

// ─── Профайлын tab (segmented pill) ───
class _ProfileTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ProfileTab(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: selected ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.accentStart.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    color: selected
                        ? Colors.white
                        : AppColors.textTertiary,
                    size: 18),
                const SizedBox(width: 6),
                Text(label,
                    style: AppTextStyles.labelMd.copyWith(
                        color: selected
                            ? Colors.white
                            : AppColors.textTertiary)),
              ],
            ),
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

    // Хоосон (бүгд ачаалагдсан) — artistic neon empty state
    if (shown.isEmpty && !_hasMore && !_loading) {
      return SliverToBoxAdapter(
        child: EmptyState(
          illustration: widget.reelsOnly
              ? 'assets/images/illustrations/empty_creator.svg'
              : 'assets/images/illustrations/empty_profile.svg',
          title: 'Одоохондоо хоосон',
          subtitle: widget.reelsOnly
              ? 'Эхний бичлэгээ хуваалцаарай'
              : 'Эхний шөнийн мөчөө хуваалцаарай',
        ),
      );
    }

    return SliverMainAxisGroup(slivers: [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
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
            Positioned(
              top: 6, right: 6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.bgBase.withValues(alpha: 0.5),
                  border: Border.all(color: AppColors.hairline2),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: AppColors.neonCyan, size: 14),
              ),
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
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String count, label;
  final bool gradient;
  const _Stat({required this.count, required this.label, this.gradient = false});

  @override
  Widget build(BuildContext context) {
    final numStyle = AppTextStyles.displaySm.copyWith(fontSize: 20, height: 1);
    final numWidget = gradient
        ? ShaderMask(
            shaderCallback: (r) => AppColors.accentGradient.createShader(r),
            child: Text(count, style: numStyle.copyWith(color: Colors.white)),
          )
        : Text(count, style: numStyle);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      numWidget,
      const SizedBox(height: 5),
      Text(label,
          style: AppTextStyles.labelSm
              .copyWith(color: AppColors.textTertiary, letterSpacing: 0.6)),
    ]);
  }
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
          width: 112, height: 112,
          padding: const EdgeInsets.all(3.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Neon cyan→magenta ring + cyan glow
            gradient: AppColors.accentGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.neonCyan.withValues(alpha: 0.45),
                blurRadius: 26,
                spreadRadius: -2,
              ),
              BoxShadow(
                color: AppColors.magenta.withValues(alpha: 0.30),
                blurRadius: 30,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.bgBase),
            child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 92),
          ),
        ),
      ),
      // "+" товч → шинэ story
      Positioned(
        right: 2, bottom: 2,
        child: GestureDetector(
          onTap: () => context.push('/story/create'),
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradient,
              border: Border.all(color: AppColors.bgBase, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentStart.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: -1,
                ),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 16)),
        ),
      ),
    ]);
  }
}
