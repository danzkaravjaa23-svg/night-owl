import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/router/app_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/stories_provider.dart';
import '../providers/saved_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../widgets/live_story_bar.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../profile/widgets/block_report_sheet.dart';
import '../../profile/utils/app_links.dart' show appOrigin;
import '../../profile/providers/follow_provider.dart';
import '../../events/widgets/events_rail.dart';
import '../../events/providers/event_provider.dart';
import '../../../models/post.dart';

/// Query string-ийг хасаад нийтлэг isVideoUrl-ээр шалгана —
/// бүх дэлгэц дээр видео ангилал нэг мөр байх ёстой
bool _isVideoUrl(String? url) => isVideoUrl(url?.split('?').first);

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollCtrl = ScrollController();
  // Орох анимац зөвхөн эхний build дээр — scroll-оор буцахад дахин тоглохгүй
  // (setState хэрэггүй: дараагийн itemBuilder-ууд шинэ утгыг нь уншина)
  bool _introDone = false;
  bool _followingOnly = false;
  Timer? _introTimer;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _introTimer =
        Timer(const Duration(milliseconds: 900), () => _introDone = true);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(feedProvider.notifier).loadFeed();
    }
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await ref.read(feedProvider.notifier).loadFeed(refresh: true);
    if (!mounted) return;
    ref.invalidate(storiesProvider);
    ref.invalidate(feedFollowingIdsProvider);
    ref.invalidate(upcomingEventsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);
    final rings = ref.watch(storiesProvider).valueOrNull ?? [];
    final following = ref.watch(feedFollowingIdsProvider);
    final posts = feedAsync.valueOrNull ?? [];
    final visiblePosts = _followingOnly
        ? posts
            .where(
                (post) => following.valueOrNull?.contains(post.userId) ?? false)
            .toList()
        : posts;
    final notifier = ref.read(feedProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(children: [
          _FeedTopBar(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accentStart,
              backgroundColor: AppColors.bgElevated,
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
                slivers: [
                  SliverToBoxAdapter(child: LiveStoryBar(rings: rings)),
                  SliverToBoxAdapter(
                    child: _FeedToolbar(
                      followingOnly: _followingOnly,
                      onFilterChanged: (value) {
                        setState(() => _followingOnly = value);
                        if (value) ref.invalidate(feedFollowingIdsProvider);
                      },
                    ),
                  ),
                  if (feedAsync.isLoading && feedAsync.valueOrNull == null)
                    SliverList.builder(
                        itemCount: 2, itemBuilder: (_, __) => _SkeletonCard())
                  else if (feedAsync.hasError && feedAsync.valueOrNull == null)
                    SliverToBoxAdapter(
                      child: SizedBox(
                          height: 360,
                          child: _ErrorView(
                            message: feedAsync.error.toString(),
                            onRetry: _refresh,
                          )),
                    )
                  else if (_followingOnly && following.isLoading)
                    const SliverToBoxAdapter(
                        child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ))
                  else if (_followingOnly && following.hasError)
                    SliverToBoxAdapter(
                        child: SizedBox(
                            height: 300,
                            child: _ErrorView(
                              message: 'Дагаж буй хүмүүсийг ачаалж чадсангүй.',
                              onRetry: () =>
                                  ref.invalidate(feedFollowingIdsProvider),
                            )))
                  else ...[
                    if (visiblePosts.isEmpty)
                      SliverToBoxAdapter(
                          child: _EmptyFeed(
                        followingOnly: _followingOnly,
                        onPost: () => context.push(AppRoutes.createPost),
                      ))
                    else
                      SliverList.builder(
                        itemCount: visiblePosts.length,
                        itemBuilder: (_, postIdx) {
                          final post = visiblePosts[postIdx];
                          final card = _PostCard(
                            key: ValueKey(post.id),
                            post: post,
                            isLast: postIdx == visiblePosts.length - 1,
                            onLike: () async {
                              final ok = await notifier.toggleLike(post.id);
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text(
                                      'Лайк хадгалж чадсангүй. Дахин оролдоно уу.'),
                                ));
                              }
                            },
                          );
                          return !_introDone && postIdx < 4
                              ? _Entrance(index: postIdx, child: card)
                              : card;
                        },
                      ),
                    SliverToBoxAdapter(
                        child: _FeedFooter(
                      notifier: notifier,
                      hasPosts: visiblePosts.isNotEmpty,
                      loadMoreButton: _followingOnly,
                    )),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Filter identifiers are scoped to the signed-in account, independent of
/// the currently fetched feed page. Pull-to-refresh also refreshes this list.
final feedFollowingIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(sessionUserIdProvider);
  return FollowService.myFollowingIds();
});

class _FeedToolbar extends StatelessWidget {
  final bool followingOnly;
  final ValueChanged<bool> onFilterChanged;
  const _FeedToolbar(
      {required this.followingOnly, required this.onFilterChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
        child: Row(children: [
          Expanded(
              child: Text('Нийтлэл',
                  style: AppTextStyles.h2.copyWith(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ))),
          IconButton(
            tooltip: 'Reels',
            onPressed: () => context.push(AppRoutes.reels),
            icon: SculptedIcon(Icons.movie_rounded,
                color: AppColors.textSecondary, size: 21),
          ),
          PopupMenuButton<String>(
            tooltip: 'Нийтлэлийн шүүлтүүр',
            initialValue: followingOnly ? 'following' : 'all',
            onSelected: (value) {
              if (value == 'events') {
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: AppColors.bgBase,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (_) => const _FeedEventsSheet(),
                );
              } else {
                onFilterChanged(value == 'following');
              }
            },
            color: AppColors.bgElevated,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Бүх нийтлэл')),
              PopupMenuItem(value: 'following', child: Text('Дагаж буй')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'events', child: Text('Эвентүүд')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(followingOnly ? 'Дагаж буй' : 'Бүгд',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textPrimary, size: 19),
              ]),
            ),
          ),
        ]),
      );
}

class _FeedEventsSheet extends ConsumerWidget {
  const _FeedEventsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(upcomingEventsProvider);
    return SafeArea(
        child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text('Эвентүүд', style: AppTextStyles.h2)),
            IconButton(
                tooltip: 'Хаах',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
        ),
        if (events.hasError)
          Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Text('Эвентүүдийг ачаалж чадсангүй.'),
                TextButton(
                    onPressed: () => ref.invalidate(upcomingEventsProvider),
                    child: const Text('Дахин оролдох')),
              ]))
        else if (!events.isLoading && (events.valueOrNull?.isEmpty ?? true))
          Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Удахгүй болох эвент одоогоор алга.',
                  style: AppTextStyles.bodyMd))
        else
          const EventsRail(),
      ]),
    ));
  }
}

// ─── Орох анимац: fade + 12px дээш гулсалт, 220ms easeOut, 40ms шатлал ───
class _Entrance extends StatelessWidget {
  final int index;
  final Widget child;
  const _Entrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final delay = index * 40;
    final total = 220 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOut),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

// ─── Top bar — нимгэн (56) IG-2025 маягийн бар: wordmark зүүн, icon кластер баруун ───
class _FeedTopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotifCountProvider);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        // Лого зай хүрэлцэхгүй (360px утас) үед багасна — overflow болохгүй
        const Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: NightOwlBrand(size: 28),
            ),
          ),
        ),
        const ThemeToggleButton(),
        const SizedBox(width: 4),
        _TopIconBtn(
          icon: SculptedIcon(Icons.notifications_rounded,
              color: AppColors.textPrimary, size: 22),
          tooltip: 'Мэдэгдэл',
          bare: true,
          badgeCount: unread,
          onTap: () => context.push(AppRoutes.notifications),
        ),
        const SizedBox(width: 8),
        _TopIconBtn(
          tooltip: 'Мессеж',
          bare: true,
          icon: SculptedIcon(Icons.chat_bubble_rounded,
              color: AppColors.textPrimary, size: 22),
          onTap: () => context.push(AppRoutes.dmList),
        ),
      ]),
    );
  }
}

// Шилэн дугуй icon товч (40) — badge/tooltip дэмжинэ
class _TopIconBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  final int badgeCount;
  final String? tooltip;

  /// Дэвсгэр/хүрээгүй — icon өөрөө дугуй хэлбэртэй үед (ж: гэрийн зураг).
  final bool bare;

  const _TopIconBtn({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.tooltip,
    this.bare = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn = _Press(
      scale: 0.9,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: bare
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgElevated.withValues(alpha: 0.72),
                border: Border.all(color: AppColors.hairline, width: 1)),
        alignment: Alignment.center,
        child: icon,
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    if (badgeCount > 0) {
      btn = Stack(clipBehavior: Clip.none, children: [
        btn,
        Positioned(
          right: -2,
          top: -2,
          child: IgnorePointer(
              child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
                color: AppColors.error, // улаан — мэдэгдэл ирсэн
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.bgBase, width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.error.withValues(alpha: 0.55),
                      blurRadius: 6,
                      spreadRadius: 0)
                ]),
            child: Text(badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800)),
          )),
        ),
      ]);
    }
    return btn;
  }
}

// ─── Дарахад жижигрэх + hover cursor (веб мэдрэмж) ───
class _Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const _Press({required this.child, this.onTap, this.scale = 0.92});

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? widget.scale : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      );
}

// ─── Post card with double-tap like ───
class _PostCard extends ConsumerStatefulWidget {
  final Post post;
  final bool isLast;
  final VoidCallback onLike;

  const _PostCard(
      {super.key,
      required this.post,
      this.isLast = false,
      required this.onLike});

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartCtrl;
  late Animation<double> _heartAnim;
  bool _showHeart = false;
  bool? _savedOverride; // optimistic; null бол provider-оос уншина
  bool _hidden = false;
  bool _captionOpen = false; // урт тайлбарыг тэр дор нь дэлгэсэн эсэх

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    // Эхний 55%-д уян "pop", сүүлийн 30%-д бүдгэрнэ (build дахь FadeTransition)
    _heartAnim = CurvedAnimation(
        parent: _heartCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut));
    _heartCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _showHeart = false);
        _heartCtrl.reset();
      }
    });
  }

  /// Хадгалсан эсэх: optimistic override эсвэл нийтлэг provider-оос
  /// (бүх карт нэг л query хуваалцана — N+1 байхгүй)
  bool get _saved =>
      _savedOverride ??
      (ref.watch(savedPostIdsProvider).valueOrNull?.contains(widget.post.id) ??
          false);

  Future<void> _toggleSave() async {
    final was = _savedOverride ??
        (ref.read(savedPostIdsProvider).valueOrNull?.contains(widget.post.id) ??
            false);
    setState(() => _savedOverride = !was);
    HapticFeedback.lightImpact();
    final err = await SavedService.toggle(widget.post.id, was);
    if (!mounted) return;
    if (err != null) {
      // Бүтэлгүйтвэл rollback + мэдэгдэнэ (чимээгүй алдахгүй)
      setState(() => _savedOverride = was);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.error));
      return;
    }
    // Refetch дуустал override-оо барина — icon буцаж анивчихгүй
    ref.invalidate(savedPostIdsProvider);
    try {
      await ref.read(savedPostIdsProvider.future);
    } catch (_) {}
    if (mounted) setState(() => _savedOverride = null);
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    super.dispose();
  }

  void _doubleTapLike() {
    HapticFeedback.mediumImpact();
    if (!widget.post.isLikedByMe) widget.onLike();
    setState(() => _showHeart = true);
    _heartCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.post.author;
    final venue = widget.post.venue;
    final venueName = widget.post.venueName ?? venue?.name;
    final caption = (widget.post.caption ?? '').trim();
    final mediaUrl = widget.post.mediaUrl ??
        (widget.post.mediaUrls.isNotEmpty ? widget.post.mediaUrls.first : null);
    final isVideo = widget.post.mediaUrls.length <= 1 && _isVideoUrl(mediaUrl);
    final liked = widget.post.isLikedByMe;
    // Өнгөт цагираг зөвхөн үзээгүй story-той зохиогч дээр — цагираг утгатай
    final hasStory = ref.watch(storiesProvider.select((a) =>
        a.valueOrNull?.any(
            (r) => r.userId == widget.post.userId && r.hasUnseenStories) ??
        false));

    if (_hidden) return const SizedBox.shrink();

    void openPost() => context.push('/post/${widget.post.id}');
    void openAuthor() => context.push('/creator/${widget.post.userId}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Зохиогч: нэр · хугацаа / газар ──
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.x4, AppSpacing.x2, AppSpacing.x1, AppSpacing.x2),
          child: Row(children: [
            _Press(
              scale: 0.94,
              onTap: openAuthor,
              child: hasStory
                  ? AppAvatar(
                      imageUrl: author?.avatarUrl,
                      initial: author?.initial ?? '?',
                      size: 42,
                      showRing: true,
                    )
                  : DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.hairline2, width: 1),
                      ),
                      child: AppAvatar(
                        imageUrl: author?.avatarUrl,
                        initial: author?.initial ?? '?',
                        size: 42,
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: openAuthor,
                      child: Row(children: [
                        // Урт нэр эхэлж таслагдана — хугацаа үргэлж харагдана
                        Flexible(
                          child: Text(author?.username ?? 'Хэрэглэгч',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.labelLg.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1)),
                        ),
                        if (author?.isVerified ?? false) ...[
                          const SizedBox(width: 3),
                          Icon(Icons.verified_rounded,
                              size: 14, color: AppColors.neonCyan),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 2),
                  MouseRegion(
                    cursor: widget.post.venueId == null
                        ? MouseCursor.defer
                        : SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.post.venueId == null
                          ? null
                          : () => context
                              .push('/venue/reviews/${widget.post.venueId}'),
                      child: Text(
                        venueName == null
                            ? widget.post.timeAgo
                            : '${widget.post.timeAgo} · $venueName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyXs
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Бусад',
              child: _Press(
                onTap: () => showPostOptionsSheet(
                  context,
                  postId: widget.post.id,
                  authorId: widget.post.userId,
                  authorUsername:
                      (author?.username ?? 'user').replaceAll('@', ''),
                  isOwn: widget.post.userId == SupabaseService.currentUser?.id,
                  currentCaption: widget.post.caption,
                  onBlocked: () {
                    if (!mounted) return;
                    setState(() => _hidden = true);
                    // Блоклосон хүний бүх пост feed-ээс тэр дор нь алга болно
                    ref
                        .read(feedProvider.notifier)
                        .removeAuthor(widget.post.userId);
                  },
                  onDelete: () async {
                    final ok = await ref
                        .read(feedProvider.notifier)
                        .deletePost(widget.post.id);
                    if (!mounted || !ok) return ok;
                    // Профайлын grid + ПОСТ тоо шинэчлэгдэнэ
                    ref.read(postsVersionProvider.notifier).state++;
                    ref.invalidate(currentProfileProvider);
                    setState(() => _hidden = true);
                    return true;
                  },
                  onEditCaption: (text) => ref
                      .read(feedProvider.notifier)
                      .editCaption(widget.post.id, text),
                ),
                // 44px хүрэх талбай — дүрс нь баруун ирмэгээс ~16px
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Icon(Icons.more_horiz_rounded,
                        color: AppColors.textSecondary, size: 22),
                  ),
                ),
              ),
            ),
          ]),
        ),

        // ── Rounded media; double-tap retains the real like action. ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: GestureDetector(
              onDoubleTap: _doubleTapLike,
              onTap: openPost,
              child: Stack(children: [
                if (widget.post.mediaUrls.length > 1)
                  _PostCarousel(urls: widget.post.mediaUrls)
                else if (mediaUrl != null)
                  isVideo
                      // Reference media frame; full media is available in post detail.
                      // Бүтэн кадр нь пост дэлгэрэнгүй дээр харагдана.
                      ? AspectRatio(
                          aspectRatio: 3 / 2,
                          child: NetworkVideo(url: mediaUrl, cover: true),
                        )
                      // 3:2 харьцаанд түгжинэ — зураг ачаалахад пост хэмжээгээ
                      // өөрчилж фийд үсрэхгүй (placeholder ч мөн адил хайрцагт)
                      : AspectRatio(
                          aspectRatio: 3 / 2,
                          child: CachedNetworkImage(
                            imageUrl: mediaUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            memCacheWidth:
                                900, // feed зураг — дэлгэцийн өргөнөөр decode
                            fadeInDuration: const Duration(milliseconds: 180),
                            placeholder: (_, __) =>
                                Container(color: AppColors.bgSurface),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.bgSurface,
                              child: const Center(
                                  child: Text('📸',
                                      style: TextStyle(fontSize: 48))),
                            ),
                          ),
                        )
                else
                  const SizedBox.shrink(),

                // Видео тэмдэг — медиа дээр тул цагаан + сүүдэр (хоёр горимд)
                if (isVideo)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: IgnorePointer(
                      child: Icon(Icons.videocam_rounded,
                          size: 18,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Color(0x99000000), blurRadius: 6)
                          ]),
                    ),
                  ),

                // Давхар товшилтын зүрх — неон гэрэлтэй, зөөлөн бүдгэрч алга болно
                if (_showHeart)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: FadeTransition(
                          opacity: Tween(begin: 1.0, end: 0.0).animate(
                              CurvedAnimation(
                                  parent: _heartCtrl,
                                  curve: const Interval(0.7, 1.0,
                                      curve: Curves.easeIn))),
                          child: ScaleTransition(
                            scale: _heartAnim,
                            child: Icon(Icons.favorite_rounded,
                                color: Colors.white,
                                size: 92,
                                shadows: [
                                  Shadow(
                                      color: AppColors.like
                                          .withValues(alpha: 0.75),
                                      blurRadius: 28),
                                  const Shadow(
                                      color: Color(0x59000000), blurRadius: 8),
                                ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),

        // ── Үйлдлүүд — тод дүрс, 44px талбай, дүрсний ирмэг 16px-т ──
        Padding(
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
          child: LayoutBuilder(builder: (context, constraints) {
            final likes =
                widget.post.likesCount > 0 ? widget.post.formattedLikes : '';
            final comments = widget.post.commentsCount > 0
                ? widget.post.formattedComments
                : '';
            double actionWidth(String label) {
              if (label.isEmpty) return 44;
              final painter = TextPainter(
                text: TextSpan(
                    text: label,
                    style: AppTextStyles.labelLg.copyWith(
                      letterSpacing: 0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: TextDirection.ltr,
                maxLines: 1,
              )..layout();
              final width = painter.width + 46;
              painter.dispose();
              return width < 44 ? 44 : width;
            }

            final inlineCounts =
                actionWidth(likes) + actionWidth(comments) + 88 <=
                    constraints.maxWidth;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _ActionBtn(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onLike();
                      },
                      icon: liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: liked ? AppColors.like : AppColors.textPrimary,
                      glow: liked,
                      label: inlineCounts ? likes : '',
                    ),
                    _ActionBtn(
                      onTap: openPost,
                      icon: Icons.chat_bubble_outline_rounded,
                      color: AppColors.textPrimary,
                      label: inlineCounts ? comments : '',
                    ),
                    _ActionBtn(
                      onTap: () async {
                        // Deploy хийсэн домэйноо ашиглана — үхмэл линк өгөхгүй
                        final link = '${appOrigin()}/#/post/${widget.post.id}';
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Холбоос хуулагдлаа 🔗'),
                                  duration: Duration(seconds: 2)));
                        }
                      },
                      icon: Icons.send_outlined,
                      color: AppColors.textPrimary,
                      label: '',
                    ),
                    const Spacer(),
                    // Хадгалах — баруун талд ганцаараа
                    Tooltip(
                      message: _saved ? 'Хадгалснаас хасах' : 'Хадгалах',
                      child: _Press(
                        scale: 0.85,
                        onTap: _toggleSave,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutBack,
                              transitionBuilder: (c, a) => ScaleTransition(
                                  scale: Tween(begin: 0.7, end: 1.0).animate(a),
                                  child: c),
                              child: SculptedIcon(
                                  _saved
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  key: ValueKey(_saved),
                                  color: _saved
                                      ? AppColors.saved
                                      : AppColors.textPrimary,
                                  size: 24),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  if (!inlineCounts)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(9, 2, 9, 4),
                      child: Wrap(spacing: 14, runSpacing: 4, children: [
                        if (likes.isNotEmpty)
                          Text('$likes лайк', style: AppTextStyles.bodySm),
                        if (comments.isNotEmpty)
                          GestureDetector(
                            onTap: openPost,
                            child: Text('$comments сэтгэгдэл',
                                style: AppTextStyles.bodySm),
                          ),
                      ]),
                    ),
                ]);
          }),
        ),

        // ── Тайлбар — 14px, #tag/@нэр неон, урт бол "дэлгэрэнгүй" ──
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.x4, AppSpacing.x1, AppSpacing.x4, 0),
            child: LayoutBuilder(builder: (ctx, c) {
              final body = AppTextStyles.bodyMd.copyWith(height: 1.4);
              final span = TextSpan(style: body, children: [
                TextSpan(
                    text: author?.username ?? 'Хэрэглэгч',
                    style: AppTextStyles.labelLg.copyWith(
                        fontWeight: FontWeight.w700, letterSpacing: -0.1)),
                const TextSpan(text: ' '),
                ..._captionSpans(caption, body),
              ]);
              final tp = TextPainter(
                text: span,
                maxLines: 2,
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(ctx),
              )..layout(maxWidth: c.maxWidth);
              final over = tp.didExceedMaxLines;
              tp.dispose();
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Эхний товшилт тэр дор нь дэлгэнэ, дараа нь пост руу
                  onTap: over && !_captionOpen
                      ? () => setState(() => _captionOpen = true)
                      : openPost,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(span,
                          maxLines: _captionOpen ? null : 2,
                          overflow: _captionOpen
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis),
                      if (over && !_captionOpen)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('дэлгэрэнгүй',
                              style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w500)),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),

        // ── Сэтгэгдэл — зөвхөн байгаа үед ──
        if (widget.post.commentsCount > 0)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(AppSpacing.x4, 2, AppSpacing.x4, 0),
            child: _Press(
              scale: 0.97,
              onTap: openPost,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                    widget.post.commentsCount == 1
                        ? '1 сэтгэгдэл харах'
                        : 'Бүх ${widget.post.formattedComments} сэтгэгдлийг харах',
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.textTertiary)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Тайлбар доторх #hashtag / @нэр-ийг неон цэнхэрээр (кирилл дэмжинэ).
final _captionTagRe = RegExp(r'[#@][\p{L}\p{N}_]+', unicode: true);

List<InlineSpan> _captionSpans(String s, TextStyle base) {
  final out = <InlineSpan>[];
  var i = 0;
  for (final m in _captionTagRe.allMatches(s)) {
    if (m.start > i) out.add(TextSpan(text: s.substring(i, m.start)));
    out.add(TextSpan(
        text: m.group(0),
        style: base.copyWith(
            color: AppColors.silver, fontWeight: FontWeight.w600)));
    i = m.end;
  }
  if (i < s.length) out.add(TextSpan(text: s.substring(i)));
  return out;
}

// ─── Олон зурагтай пост carousel ───
class _PostCarousel extends StatefulWidget {
  final List<String> urls;
  const _PostCarousel({required this.urls});
  @override
  State<_PostCarousel> createState() => _PostCarouselState();
}

class _PostCarouselState extends State<_PostCarousel> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ганц зурагтай посттой ижил 3:2 хайрцаг — фийд үсрэхгүй
    return AspectRatio(
      aspectRatio: 3 / 2,
      child: Stack(children: [
        // Веб дээр хулганаар чирж гүйлгэнэ (анхдагч нь зөвхөн touch —
        // desktop дээр 2 дахь зураг руу хүрэх боломжгүй байсан)
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          }),
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final url = widget.urls[i];
              if (_isVideoUrl(url)) {
                return NetworkVideo(url: url, cover: true);
              }
              return CachedNetworkImage(
                imageUrl: url,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 900,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => Container(color: AppColors.bgSurface),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.bgSurface,
                  child: const Center(
                      child: Text('📸', style: TextStyle(fontSize: 48))),
                ),
              );
            },
          ),
        ),
        // Тоо (1/3) — медиа дээр тул үргэлж харанхуй шил
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: AppRadii.pillR,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18), width: 0.8),
            ),
            child: Text('${_page + 1}/${widget.urls.length}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ),
        // Цэгүүд — гэрэлтэй зураг дээр ч уншигдахаар бараан pill дотор,
        // идэвхтэй нь неон капсул
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: AppRadii.pillR,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < widget.urls.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: i == _page ? 14 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.pillR,
                      color: i == _page
                          ? AppColors.neonCyanDark
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final String label;

  /// Лайкласан зүрх — харанхуй горимд неон ягаан гэрэлтэнэ
  final bool glow;

  const _ActionBtn({
    required this.onTap,
    required this.icon,
    required this.color,
    required this.label,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) => _Press(
        scale: 0.88,
        onTap: onTap,
        // 44×44 хүрэх талбай; дүрс солигдоход (лайк) нэг удаа "pop"
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (c, a) => ScaleTransition(
                      scale: Tween(begin: 0.7, end: 1.0).animate(a), child: c),
                  child: SculptedIcon(icon,
                      key: ValueKey(icon),
                      color: color,
                      size: 24,
                      active: glow),
                ),
                // Тоо байхгүй бол дүрс ганцаараа (хоосон зай үлдээхгүй)
                if (label.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.x1),
                  Text(label,
                      style: AppTextStyles.labelLg.copyWith(
                          color: AppColors.textPrimary,
                          letterSpacing: 0,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ],
            ),
          ),
        ),
      );
}

// ─── Feed footer: spinner / retry / төгсгөл ───
class _FeedFooter extends StatelessWidget {
  final FeedNotifier notifier;
  final bool hasPosts;
  final bool loadMoreButton;
  const _FeedFooter(
      {required this.notifier,
      required this.hasPosts,
      this.loadMoreButton = false});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: notifier.pageError,
        builder: (_, err, __) {
          if (err) {
            // Хуудас ачаалж чадсангүй — retry товч
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text('Ачаалж чадсангүй',
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => notifier.loadFeed(),
                  style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.hairline),
                      foregroundColor: AppColors.accentStart),
                  child: const Text('Дахин оролдох'),
                ),
              ]),
            );
          }
          return ValueListenableBuilder<bool>(
            valueListenable: notifier.hasMore,
            builder: (_, more, __) {
              if (more && loadMoreButton) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                      child: TextButton.icon(
                    onPressed: () => notifier.loadFeed(),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('Дараагийн нийтлэлүүдийг ачаалах'),
                  )),
                );
              }
              if (more) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentStart, strokeWidth: 2)),
                );
              }
              if (!hasPosts) return const SizedBox.shrink();
              // Фийдийн төгсгөл
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Center(
                  child: Text('Шөнө эндээс эхэлсэн 🦉',
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textTertiary)),
                ),
              );
            },
          );
        },
      );
}

// ─── Empty feed ───
class _EmptyFeed extends StatelessWidget {
  final VoidCallback onPost;
  final bool followingOnly;
  const _EmptyFeed({required this.onPost, this.followingOnly = false});

  @override
  Widget build(BuildContext context) => EmptyState(
        illustration: 'assets/images/illustrations/empty_feed.svg',
        title: followingOnly
            ? 'Дагаж буй хүмүүсийн нийтлэл'
            : 'Нийтлэл алга байна',
        subtitle: followingOnly
            ? 'Ачаалсан нийтлэлүүдэд дагаж буй хүмүүсийн пост алга. Бүх нийтлэлээс хүмүүсийг дагаж болно.'
            : 'Өнөө шөнийн мөчөө хамгийн түрүүнд хуваалцаарай.',
        action: followingOnly
            ? null
            : ElevatedButton.icon(
                onPressed: onPost,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Зураг оруулах'),
              ),
      );
}

// ─── Error view ───
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_outlined,
                color: AppColors.textTertiary, size: 48),
            const SizedBox(height: 16),
            Text('Алдаа гарлаа', style: AppTextStyles.h2),
            const SizedBox(height: 8),
            Text(message,
                style: AppTextStyles.bodyXs
                    .copyWith(color: AppColors.textTertiary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: onRetry, child: const Text('Дахин оролдох')),
          ]),
        ),
      );
}

// Skeleton uses the same media geometry as loaded posts.
class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        // Жинхэнэ посттой ижил геометр — хайрцаггүй, медиа ирмэгээс ирмэг
        // (skeleton → контент солигдоход үсрэхгүй)
        padding: const EdgeInsets.only(bottom: AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                _box(w: 36, h: 36, r: 18),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _box(w: 140, h: 12),
                  const SizedBox(height: 6),
                  _box(w: 80, h: 9),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AspectRatio(aspectRatio: 3 / 2, child: _box(r: 14)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(children: [
                _box(w: 26, h: 26, r: 8),
                const SizedBox(width: 18),
                _box(w: 26, h: 26, r: 8),
                const SizedBox(width: 18),
                _box(w: 26, h: 26, r: 8),
                const Spacer(),
                _box(w: 26, h: 26, r: 8),
              ]),
            ),
          ],
        ),
      );

  Widget _box({double? w, double? h, double r = 8}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(r),
        ),
      );
}
