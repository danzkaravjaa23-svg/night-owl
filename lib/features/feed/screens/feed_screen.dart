import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/router/app_router.dart';
import '../providers/feed_provider.dart';
import '../providers/stories_provider.dart';
import '../providers/saved_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../widgets/live_story_bar.dart';
import '../../live/providers/live_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../events/widgets/events_rail.dart';
import '../../profile/widgets/block_report_sheet.dart';
import '../../../core/widgets/ger_icon.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    Future.delayed(const Duration(milliseconds: 900), () => _introDone = true);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(feedProvider.notifier).loadFeed();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(children: [
        // ── Агаар мандлын неон гэрэл — маш бүдэг radial угаалт (дээд-зүүн magenta, доод-баруун cyan) ──
        const Positioned.fill(child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(
            center: Alignment(-0.9, -0.9), radius: 1.1,
            colors: [Color(0x12E935C8), Colors.transparent]))))),
        const Positioned.fill(child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(
            center: Alignment(1.0, 1.0), radius: 1.1,
            colors: [Color(0x0E22E7FF), Colors.transparent]))))),
        SafeArea(
        child: Column(children: [
          _FeedTopBar(),
          Expanded(
            child: feedAsync.when(
              loading: () => const _FeedSkeleton(),
              error: (e, _) => _ErrorView(
                message: e.toString(),
                onRetry: () =>
                    ref.read(feedProvider.notifier).loadFeed(refresh: true)),
              data: (posts) {
                final storiesAsync = ref.watch(storiesProvider);
                final rings = storiesAsync.value ?? [];
                return posts.isEmpty && rings.isEmpty
                    ? _EmptyFeed(
                        onPost: () => context.push(AppRoutes.createPost))
                    : RefreshIndicator(
                        color: AppColors.accentStart,
                        backgroundColor: AppColors.bgElevated,
                        onRefresh: () async {
                          await ref
                              .read(feedProvider.notifier)
                              .loadFeed(refresh: true);
                          ref.invalidate(storiesProvider);
                          ref.invalidate(activeLivesProvider);
                          ref.invalidate(upcomingEventsProvider);
                        },
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          physics: const AlwaysScrollableScrollPhysics(),
                          // Дараагийн картуудыг урьдчилан бэлдэж scroll гөлгөр болгоно
                          scrollCacheExtent:
                              const ScrollCacheExtent.pixels(1200),
                          // +1 for stories bar, +1 for footer
                          itemCount: posts.length + 2,
                          itemBuilder: (ctx, i) {
                            if (i == 0) {
                              // ── Story rail + Event постерууд (хуваагч шугамгүй,
                              //    секц хоорондын агаараар ялгарна) ──
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  LiveStoryBar(rings: rings),
                                  const EventsRail(),
                                ],
                              );
                            }
                            final postIdx = i - 1;
                            if (postIdx == posts.length) {
                              return _FeedFooter(
                                notifier: ref.read(feedProvider.notifier),
                                hasPosts: posts.isNotEmpty,
                              );
                            }
                            final card = _PostCard(
                              post: posts[postIdx],
                              isLast: postIdx == posts.length - 1,
                              onLike: () => ref
                                  .read(feedProvider.notifier)
                                  .toggleLike(posts[postIdx].id),
                            );
                            // Эхний картуудад шатлалтай орох анимац (нэг л удаа)
                            if (!_introDone && postIdx < 4) {
                              return _Entrance(index: postIdx, child: card);
                            }
                            return card;
                          },
                        ),
                      );
              },
            ),
          ),
        ]),
        ),
      ]),
    );
  }
}

// ─── Орох анимац: fade + 12px дээш гулсалт, 220ms easeOut, 40ms шатлал ───
class _Entrance extends StatelessWidget {
  final int index;
  final Widget child;
  const _Entrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
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
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline, width: 1)),
      ),
      child: Row(children: [
        const NightOwlLogoText(fontSize: 22),
        const Spacer(),
        _TopIconBtn(
          icon: const Icon(Icons.search,
              color: AppColors.textPrimary, size: 20),
          onTap: () => context.push(AppRoutes.search),
        ),
        const SizedBox(width: 10),
        _TopIconBtn(
          icon: const GerIcon(size: 22),
          tooltip: 'Мэдэгдэл',
          badgeCount: unread,
          onTap: () => context.push(AppRoutes.notifications),
        ),
        const SizedBox(width: 10),
        _TopIconBtn(
          icon: const Icon(Icons.send_outlined,
              color: AppColors.textPrimary, size: 19),
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
  const _TopIconBtn({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn = _Press(
      scale: 0.9,
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
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
          right: -2, top: -2,
          child: IgnorePointer(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: AppColors.accentStart,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.bgBase, width: 1.5)),
            child: Text(badgeCount > 99 ? '99+' : '$badgeCount',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 9,
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
      {required this.post, this.isLast = false, required this.onLike});

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

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heartAnim = CurvedAnimation(parent: _heartCtrl, curve: Curves.elasticOut);
    _heartCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _showHeart = false);
        _heartCtrl.reset();
      }
    });
  }

  /// Хадгалсан эсэх: optimistic override эсвэл нийтлэг provider-оос
  /// (бүх карт нэг л query хуваалцана — N+1 байхгүй)
  bool get _saved => _savedOverride ??
      (ref.watch(savedPostIdsProvider).valueOrNull?.contains(widget.post.id) ?? false);

  Future<void> _toggleSave() async {
    final was = _savedOverride ??
        (ref.read(savedPostIdsProvider).valueOrNull?.contains(widget.post.id) ?? false);
    setState(() => _savedOverride = !was);
    HapticFeedback.lightImpact();
    final err = await SavedService.toggle(widget.post.id, was);
    if (!mounted) return;
    if (err != null) {
      // Бүтэлгүйтвэл rollback + мэдэгдэнэ (чимээгүй алдахгүй)
      setState(() => _savedOverride = was);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err), backgroundColor: AppColors.error));
      return;
    }
    // Refetch дуустал override-оо барина — icon буцаж анивчихгүй
    ref.invalidate(savedPostIdsProvider);
    try { await ref.read(savedPostIdsProvider.future); } catch (_) {}
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

    if (_hidden) return const SizedBox.shrink();

    // IG-2025 карт: радиус 24 глас, media EDGE-TO-EDGE (радиус 20),
    // caption нь media-ийн ДООР "username caption" rich хэлбэрээр
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline, width: 1),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Author row ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
          child: Row(children: [
            _Press(
              scale: 0.94,
              onTap: () => context.push('/creator/${widget.post.userId}'),
              child: AppAvatar(
                imageUrl: author?.avatarUrl,
                initial: author?.initial ?? '?',
                size: 38,
                showRing: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      context.push('/creator/${widget.post.userId}'),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author?.username ?? 'Хэрэглэгч',
                            style: AppTextStyles.labelMd.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.1)),
                        if ((widget.post.venueName ?? venue?.name) != null)
                          Row(children: [
                            const Icon(Icons.location_on,
                                size: 10, color: AppColors.accentStart),
                            const SizedBox(width: 2),
                            Text(widget.post.venueName ?? venue!.name,
                                style: AppTextStyles.bodyXs.copyWith(
                                    color: AppColors.textSecondary)),
                          ]),
                      ]),
                ),
              ),
            ),
            Text(widget.post.timeAgo,
                style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.textTertiary)),
            const SizedBox(width: 4),
            _Press(
              onTap: () => showPostOptionsSheet(
                context,
                postId: widget.post.id,
                authorId: widget.post.userId,
                authorUsername: (author?.username ?? 'user').replaceAll('@', ''),
                isOwn: widget.post.userId == SupabaseService.currentUser?.id,
                currentCaption: widget.post.caption,
                onBlocked: () => setState(() => _hidden = true),
                onDelete: () async {
                  final ok = await ref.read(feedProvider.notifier)
                      .deletePost(widget.post.id);
                  if (mounted && ok) setState(() => _hidden = true);
                },
                onEditCaption: (text) => ref.read(feedProvider.notifier)
                    .editCaption(widget.post.id, text),
              ),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.more_horiz,
                    color: AppColors.textTertiary, size: 20),
              ),
            ),
          ]),
        ),

        // ── Media with double-tap — картын ирмэгт шахсан (радиус 20) ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: GestureDetector(
          onDoubleTap: _doubleTapLike,
          onTap: () => context.push('/post/${widget.post.id}'),
          child: Stack(children: [
            if (widget.post.mediaUrls.length > 1)
              _PostCarousel(urls: widget.post.mediaUrls)
            else if (widget.post.mediaUrl != null)
              _isVideoUrl(widget.post.mediaUrl)
                  ? NetworkVideo(url: widget.post.mediaUrl!, height: 380)
                  : CachedNetworkImage(
                      imageUrl: widget.post.mediaUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: 900, // feed зураг — дэлгэцийн өргөнөөр decode
                      fadeInDuration: const Duration(milliseconds: 180),
                      placeholder: (_, __) => Container(
                          height: 380, color: AppColors.bgSurface),
                      errorWidget: (_, __, ___) => Container(
                        height: 300,
                        color: AppColors.bgSurface,
                        child: const Center(
                            child: Text('📸', style: TextStyle(fontSize: 48))),
                      ),
                    )
            else
              Container(
                height: 280,
                color: AppColors.bgSurface,
                child: const Center(
                    child: Text('📸', style: TextStyle(fontSize: 48))),
              ),

            // Double-tap heart overlay
            if (_showHeart)
              Positioned.fill(
                child: Center(
                  child: ScaleTransition(
                    scale: _heartAnim,
                    child: const Icon(Icons.favorite,
                        color: Colors.white, size: 80),
                  ),
                ),
              ),
          ]),
        ))),

        // ── Actions — IG-2025 эрэмбэ: зүүнд heart/comment/share кластер (26px
        //    icon + labelMd count), баруунд bookmark ганцаараа ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
          child: Row(children: [
            // Like
            _ActionBtn(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onLike();
              },
              icon: widget.post.isLikedByMe
                  ? Icons.favorite
                  : Icons.favorite_border,
              color: widget.post.isLikedByMe
                  ? AppColors.accentStart
                  : AppColors.textSecondary,
              label: widget.post.likesCount > 0
                  ? widget.post.formattedLikes
                  : '',
            ),
            const SizedBox(width: 14),
            // Comment
            _ActionBtn(
              onTap: () => context.push('/post/${widget.post.id}'),
              icon: Icons.chat_bubble_outline,
              color: AppColors.textSecondary,
              label: widget.post.commentsCount > 0
                  ? widget.post.formattedComments
                  : '',
            ),
            const SizedBox(width: 14),
            // Share — зүүн кластерын гишүүн (IG эрэмбэ), handler хэвээрээ
            _ActionBtn(
              onTap: () async {
                // Deploy хийсэн домэйноо ашиглана — үхмэл линк өгөхгүй
                final link = '${Uri.base.origin}/post/${widget.post.id}';
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Холбоос хуулагдлаа 🔗'),
                    duration: Duration(seconds: 2)));
                }
              },
              icon: Icons.send_outlined,
              color: AppColors.textSecondary,
              label: '',
            ),
            const Spacer(),
            // Save / bookmark — баруун талд ганцаараа
            _Press(
              scale: 0.85,
              onTap: _toggleSave,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(_saved ? Icons.bookmark : Icons.bookmark_border,
                    color: _saved ? AppColors.accentStart : AppColors.textSecondary,
                    size: 24),
              ),
            ),
          ]),
        ),

        // ── Caption — "username бол caption" rich text, 2 мөр (IG темплэйт) ──
        if ((widget.post.caption ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push('/post/${widget.post.id}'),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: author?.username ?? 'Хэрэглэгч',
                        style: AppTextStyles.labelMd.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1)),
                    const TextSpan(text: '  '),
                    TextSpan(
                        text: widget.post.caption!.trim(),
                        style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.textSecondary, height: 1.35)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),

        // ── "Бүх N сэтгэгдэл" — tertiary линк (тоотой, IG темплэйт) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: _Press(
            scale: 0.97,
            onTap: () => context.push('/post/${widget.post.id}'),
            child: Text(
                widget.post.commentsCount > 0
                    ? 'Бүх ${widget.post.formattedComments} сэтгэгдэл'
                    : 'Сэтгэгдэл үлдээх…',
                style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textTertiary)),
          ),
        ),
      ]),
    );
  }
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
    return SizedBox(
      height: 380,
      child: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final url = widget.urls[i];
            if (_isVideoUrl(url)) {
              return NetworkVideo(url: url, height: 380);
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
        // Count badge (1/3)
        Positioned(top: 12, right: 12, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Text('${_page + 1}/${widget.urls.length}',
            style: const TextStyle(color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w600)),
        )),
        // Dots
        Positioned(bottom: 12, left: 0, right: 0, child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.urls.length; i++)
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? Colors.white : Colors.white38),
              ),
          ],
        )),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final String label;

  const _ActionBtn({
    required this.onTap,
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => _Press(
    scale: 0.88,
    onTap: onTap,
    // Тухтай хүрэлтийн талбай — Padding-оор тэлсэн hit area
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(children: [
        Icon(icon, color: color, size: 26),
        // Тоо байхгүй бол icon ганцаараа (хоосон зай үлдээхгүй)
        if (label.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(label,
              style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
        ],
      ]),
    ),
  );
}

// ─── Feed footer: spinner / retry / төгсгөл ───
class _FeedFooter extends StatelessWidget {
  final FeedNotifier notifier;
  final bool hasPosts;
  const _FeedFooter({required this.notifier, required this.hasPosts});

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
                style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.textTertiary)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => notifier.loadFeed(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.hairline),
                foregroundColor: AppColors.accentStart),
              child: const Text('Дахин оролдох'),
            ),
          ]),
        );
      }
      return ValueListenableBuilder<bool>(
        valueListenable: notifier.hasMore,
        builder: (_, more, __) {
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
                  style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textTertiary)),
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
  const _EmptyFeed({required this.onPost});

  @override
  Widget build(BuildContext context) => EmptyState(
    illustration: 'assets/images/illustrations/empty_feed.svg',
    title: 'Фийд хоосон байна',
    subtitle: 'Өнөө шөнийн мөчөө хамгийн түрүүнд хуваалцаарай.',
    action: ElevatedButton.icon(
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
        const Icon(Icons.wifi_off_outlined,
            color: AppColors.textTertiary, size: 48),
        const SizedBox(height: 16),
        Text('Алдаа гарлаа', style: AppTextStyles.h2),
        const SizedBox(height: 8),
        Text(message,
            style: AppTextStyles.bodyXs
                .copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: onRetry, child: const Text('Дахин оролдох')),
      ]),
    ),
  );
}

// ─── Shimmer skeleton ───
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: AppColors.bgElevated,
    highlightColor: AppColors.bgSurface,
    child: ListView(children: List.generate(3, (_) => _SkeletonCard())),
  );
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    // Жинхэнэ картын геометртэй ижил — 20 margin, радиус 24 глас
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    decoration: BoxDecoration(
      color: AppColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.hairline, width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            _box(w: 38, h: 38, r: 19),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _box(w: 110, h: 11),
              const SizedBox(height: 5),
              _box(w: 70, h: 9),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: _box(w: double.infinity, h: 320, r: 20),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(children: [
            _box(w: 26, h: 26, r: 8),
            const SizedBox(width: 14),
            _box(w: 26, h: 26, r: 8),
            const Spacer(),
            _box(w: 24, h: 24, r: 8),
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
