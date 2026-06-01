import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/router/app_router.dart';
import '../providers/feed_provider.dart';
import '../providers/stories_provider.dart';
import '../widgets/live_story_bar.dart';
import '../../live/providers/live_provider.dart';
import '../../events/widgets/events_rail.dart';
import '../../events/providers/event_provider.dart';
import '../../../models/post.dart';

bool _isVideoUrl(String? url) {
  if (url == null) return false;
  final lower = url.toLowerCase().split('?').first;
  return lower.endsWith('.mp4') || lower.endsWith('.mov') ||
      lower.endsWith('.webm') || lower.endsWith('.avi') ||
      lower.endsWith('.m4v');
}

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(feedProvider.notifier).loadFeed();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
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
                          // +1 for stories bar, +1 for load-more
                          itemCount: posts.length + 2,
                          itemBuilder: (ctx, i) {
                            if (i == 0) {
                              // ── Live rail + Stories bar ──
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LiveStoryBar(rings: rings),
                                  const Divider(
                                      color: AppColors.hairline, height: 1),
                                  const EventsRail(),
                                ],
                              );
                            }
                            final postIdx = i - 1;
                            if (postIdx == posts.length) {
                              return const _LoadMoreIndicator();
                            }
                            return _PostCard(
                              post: posts[postIdx],
                              isLast: postIdx == posts.length - 1,
                              onLike: () => ref
                                  .read(feedProvider.notifier)
                                  .toggleLike(posts[postIdx].id),
                            );
                          },
                        ),
                      );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Top bar ───
class _FeedTopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
      child: Row(children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradient,
            ),
            child: const Center(
                child: Text('🦉', style: TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NightOwlLogoText(fontSize: 20),
            Text('UB · Шөнийн нийгэм',
                style: AppTextStyles.mono
                    .copyWith(fontSize: 9, color: AppColors.textTertiary)),
          ]),
        ]),
        const Spacer(),
        IconButton(
          onPressed: () => context.push(AppRoutes.notifications),
          icon: const Icon(Icons.favorite_border,
              color: AppColors.textPrimary, size: 22),
        ),
        IconButton(
          onPressed: () => context.push(AppRoutes.dmList),
          icon: const Icon(Icons.send_outlined,
              color: AppColors.textPrimary, size: 22),
        ),
      ]),
    );
  }
}

// ─── Post card with double-tap like ───
class _PostCard extends StatefulWidget {
  final Post post;
  final bool isLast;
  final VoidCallback onLike;

  const _PostCard(
      {required this.post, this.isLast = false, required this.onLike});

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartCtrl;
  late Animation<double> _heartAnim;
  bool _showHeart = false;

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

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Author row ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(children: [
            GestureDetector(
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
              child: GestureDetector(
                onTap: () =>
                    context.push('/creator/${widget.post.userId}'),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author?.username ?? 'Unknown',
                          style: AppTextStyles.labelMd),
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
            Text(widget.post.timeAgo, style: AppTextStyles.bodyXs),
            const SizedBox(width: 4),
            const Icon(Icons.more_horiz,
                color: AppColors.textTertiary, size: 20),
          ]),
        ),

        // ── Media with double-tap ──
        GestureDetector(
          onDoubleTap: _doubleTapLike,
          onTap: () => context.push('/post/${widget.post.id}'),
          child: Stack(children: [
            if (widget.post.mediaUrl != null)
              _isVideoUrl(widget.post.mediaUrl)
                  ? NetworkVideo(url: widget.post.mediaUrl!, height: 380)
                  : CachedNetworkImage(
                      imageUrl: widget.post.mediaUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
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
        ),

        // ── Actions ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
              label: widget.post.formattedLikes,
            ),
            const SizedBox(width: 16),
            // Comment
            _ActionBtn(
              onTap: () => context.push('/post/${widget.post.id}'),
              icon: Icons.chat_bubble_outline,
              color: AppColors.textSecondary,
              label: widget.post.commentsCount > 0
                  ? widget.post.formattedComments
                  : 'Comment',
            ),
            const Spacer(),
            // Share
            GestureDetector(
              onTap: () {},
              child: const Icon(Icons.send_outlined,
                  color: AppColors.textSecondary, size: 22),
            ),
          ]),
        ),

        // ── Caption ──
        if (widget.post.caption?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: RichText(
              text: TextSpan(style: AppTextStyles.bodyMd, children: [
                TextSpan(
                  text: '${author?.username ?? ''} ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: widget.post.caption),
              ]),
            ),
          ),

        // ── View comments ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: GestureDetector(
            onTap: () => context.push('/post/${widget.post.id}'),
            child: Text('View comments',
                style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textTertiary)),
          ),
        ),
      ]),
    );
  }
}

// ─── Feed video player — lazy load, cover until tapped ───
class _FeedVideoPlayer extends StatefulWidget {
  final String url;
  const _FeedVideoPlayer({required this.url});

  @override
  State<_FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<_FeedVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _loading  = false;
  bool _ready    = false;
  bool _playing  = false;

  Future<void> _startPlay() async {
    if (_loading || _ready) return;
    setState(() => _loading = true);
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await ctrl.initialize();
    if (!mounted) { ctrl.dispose(); return; }
    setState(() { _ctrl = ctrl; _ready = true; _loading = false; _playing = true; });
    ctrl.play();
  }

  void _togglePlay() {
    if (_ctrl == null) return;
    setState(() {
      _playing = !_playing;
      _playing ? _ctrl!.play() : _ctrl!.pause();
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cover / placeholder
    if (!_ready) {
      return GestureDetector(
        onTap: _startPlay,
        child: Container(
          height: 380, color: AppColors.bgSurface,
          child: Stack(children: [
            // Dark overlay with play icon
            Positioned.fill(child: Container(
              color: Colors.black.withOpacity(0.3),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.6),
                    border: Border.all(color: Colors.white54, width: 2)),
                  child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 38)),
                const SizedBox(height: 10),
                if (!_loading)
                  const Text('Tap to play',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            )),
            // VIDEO badge
            Positioned(top: 12, left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.videocam_rounded, color: Colors.white70, size: 13),
                  SizedBox(width: 4),
                  Text('VIDEO', style: TextStyle(
                    color: Colors.white70, fontSize: 10,
                    fontWeight: FontWeight.w700)),
                ]))),
          ]),
        ),
      );
    }

    // Playing
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(children: [
        SizedBox(
          width: double.infinity,
          height: _ctrl!.value.size.height > 0
              ? _ctrl!.value.size.height / _ctrl!.value.size.width
                  * MediaQuery.of(context).size.width
              : 380,
          child: VideoPlayer(_ctrl!),
        ),
        Positioned.fill(child: AnimatedOpacity(
          opacity: _playing ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Center(child: Container(
            width: 56, height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.black54),
            child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 32))))),
        Positioned(top: 10, left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black54, borderRadius: BorderRadius.circular(6)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.videocam_rounded, color: Colors.white70, size: 12),
              SizedBox(width: 3),
              Text('VIDEO', style: TextStyle(
                color: Colors.white70, fontSize: 10,
                fontWeight: FontWeight.w600)),
            ]))),
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 5),
      Text(label,
          style: AppTextStyles.labelSm.copyWith(color: AppColors.textSecondary)),
    ]),
  );
}

// ─── Load more indicator ───
class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(
      child: CircularProgressIndicator(
          color: AppColors.accentStart, strokeWidth: 2)),
  );
}

// ─── Empty feed ───
class _EmptyFeed extends StatelessWidget {
  final VoidCallback onPost;
  const _EmptyFeed({required this.onPost});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('✨', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 20),
        Text('Feed is empty', style: AppTextStyles.h1),
        const SizedBox(height: 8),
        Text('Be the first to share your night.',
            style: AppTextStyles.bodyMd
                .copyWith(color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: onPost,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Upload Photo'),
        ),
      ]),
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
        Text('Something went wrong', style: AppTextStyles.h2),
        const SizedBox(height: 8),
        Text(message,
            style: AppTextStyles.bodyXs
                .copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
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
      _box(w: double.infinity, h: 340, r: 0),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: _box(w: 140, h: 11),
      ),
    ],
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
