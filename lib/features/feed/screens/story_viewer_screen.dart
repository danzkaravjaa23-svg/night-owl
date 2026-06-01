import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/story.dart';
import '../providers/stories_provider.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<StoryRing> rings;
  final int initialRingIndex;

  const StoryViewerScreen({
    super.key,
    required this.rings,
    this.initialRingIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  late int _ringIndex;
  int _storyIndex = 0;
  late AnimationController _progressCtrl;
  late PageController _pageCtrl;
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _ringIndex = widget.initialRingIndex;
    _pageCtrl  = PageController(initialPage: _ringIndex);
    _progressCtrl = AnimationController(vsync: this);
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) _progressCtrl.stop();
    });
    _startProgress();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _pageCtrl.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _sendReply(String body) async {
    final text = body.trim();
    final authorId = _currentRing.userId;
    if (text.isEmpty || _myId.isEmpty || authorId == _myId) return;
    _replyCtrl.clear();
    _replyFocus.unfocus();
    try {
      await SupabaseService.client.from('messages').insert({
        'sender_id': _myId, 'receiver_id': authorId,
        'body': text, 'is_read': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Илгээлээ ✓'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating));
      }
    } catch (_) {}
    // үргэлжлүүлэх
    _progressCtrl.forward().then((_) { if (mounted) _nextStory(); });
  }

  StoryRing get _currentRing => widget.rings[_ringIndex];
  Story     get _currentStory => _currentRing.stories[_storyIndex];
  int       get _totalStories => _currentRing.stories.length;

  void _startProgress() {
    _progressCtrl.reset();
    final duration = Duration(seconds: _currentStory.duration);
    _progressCtrl.duration = duration;
    _progressCtrl.forward().then((_) {
      if (mounted) _nextStory();
    });
    StoryService.markViewed(_currentStory.id);
  }

  void _nextStory() {
    if (_storyIndex < _totalStories - 1) {
      setState(() => _storyIndex++);
      _startProgress();
    } else {
      _nextRing();
    }
  }

  void _prevStory() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startProgress();
    } else if (_ringIndex > 0) {
      setState(() {
        _ringIndex--;
        _storyIndex = widget.rings[_ringIndex].stories.length - 1;
      });
      _pageCtrl.jumpToPage(_ringIndex);
      _startProgress();
    }
  }

  void _nextRing() {
    if (_ringIndex < widget.rings.length - 1) {
      setState(() { _ringIndex++; _storyIndex = 0; });
      _pageCtrl.animateToPage(_ringIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
      _startProgress();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story  = _currentStory;
    final author = _currentRing.author;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final x = d.globalPosition.dx;
          final w = MediaQuery.of(context).size.width;
          if (x < w * 0.35) {
            _progressCtrl.stop();
            _prevStory();
          } else if (x > w * 0.65) {
            _progressCtrl.stop();
            _nextStory();
          } else {
            // Center tap: pause/resume
            if (_progressCtrl.isAnimating) {
              _progressCtrl.stop();
            } else {
              _progressCtrl.forward().then((_) {
                if (mounted) _nextStory();
              });
            }
          }
        },
        onLongPressStart: (_) => _progressCtrl.stop(),
        onLongPressEnd:   (_) => _progressCtrl.forward().then((_) {
          if (mounted) _nextStory();
        }),
        child: Stack(fit: StackFit.expand, children: [
          // ── Media (зураг эсвэл видео) ──
          if (isVideoUrl(story.mediaUrl))
            NetworkVideo(
              url: story.mediaUrl,
              autoplay: true,
              height: MediaQuery.of(context).size.height)
          else
            CachedNetworkImage(
              imageUrl: story.mediaUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF1a0a2e),
                child: const Center(child: Text('📸',
                    style: TextStyle(fontSize: 64))),
              ),
            ),

          // ── Gradient overlay ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Colors.black45, Colors.transparent],
              ),
            ),
          ),

          // ── Progress bars ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12, right: 12,
            child: Row(
              children: List.generate(_totalStories, (i) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: i < _storyIndex
                      ? Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2)))
                      : i == _storyIndex
                          ? AnimatedBuilder(
                              animation: _progressCtrl,
                              builder: (_, __) => FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: _progressCtrl.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2))),
                              ))
                          : const SizedBox.shrink(),
                ),
              )),
            ),
          ),

          // ── Author header ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 22,
            left: 12, right: 12,
            child: Row(children: [
              AppAvatar(
                imageUrl: author.avatarUrl,
                initial:  author.initial,
                size: 38, showRing: true,
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(author.username ?? '—',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Text(_timeAgo(story.createdAt),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                ],
              )),
              GestureDetector(
                onTap: () => context.pop(),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 24),
              ),
            ]),
          ),

          // ── Доод хэсэг: venue/mention + caption + reply ──
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(top: false, child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                left: 14, right: 14, top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (story.venueName != null || story.mentions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        alignment: WrapAlignment.center, spacing: 8, runSpacing: 6,
                        children: [
                          if (story.venueName != null)
                            _storyPill(Icons.location_on, story.venueName!),
                          if (story.mentions.isNotEmpty)
                            _storyPill(Icons.alternate_email_rounded,
                                '${story.mentions.length} хүн'),
                        ])),
                  if (story.caption?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(story.caption!, textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 15,
                          fontWeight: FontWeight.w500, height: 1.4,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black54)]))),
                  // ── Reply (зөвхөн бусдын story дээр) ──
                  if (_currentRing.userId != _myId)
                    Row(children: [
                      Expanded(child: TextField(
                        controller: _replyCtrl,
                        focusNode: _replyFocus,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: _sendReply,
                        decoration: InputDecoration(
                          hintText: 'Мессеж илгээх...',
                          hintStyle: const TextStyle(color: Colors.white70),
                          filled: true, fillColor: Colors.white.withOpacity(0.12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: const BorderSide(color: Colors.white30)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: const BorderSide(color: Colors.white30)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26),
                            borderSide: const BorderSide(color: Colors.white)),
                        ))),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => _sendReply('❤️'),
                        child: const Icon(Icons.favorite_border,
                            color: Colors.white, size: 28)),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: () => _sendReply(_replyCtrl.text),
                        child: const Icon(Icons.send_rounded,
                            color: Colors.white, size: 26)),
                    ]),
                ])),
            )),
        ]),
      ),
    );
  }

  Widget _storyPill(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black54, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white, size: 13),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(
        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    ]));

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}м өмнө';
    return '${diff.inHours}ц өмнө';
  }
}

// ─── Stories bar widget (used in FeedScreen) ─────────────────────────────────
class StoriesBar extends StatelessWidget {
  final List<StoryRing> rings;
  const StoriesBar({super.key, required this.rings});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: rings.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return _AddStoryItem(onTap: () => context.push('/story/create'));
          }
          final idx = i - 1;
          return _StoryRingItem(
            ring: rings[idx],
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                pageBuilder: (_, __, ___) => StoryViewerScreen(
                  rings: rings,
                  initialRingIndex: idx,
                ),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "+ Your story" — story нэмэх товч
class _AddStoryItem extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStoryItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [
          Stack(children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgSurface,
                border: Border.all(color: AppColors.hairline)),
              child: const Icon(Icons.add_a_photo_outlined,
                  color: AppColors.textSecondary, size: 24)),
            Positioned(right: 0, bottom: 0, child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentGradient,
                border: Border.all(color: AppColors.bgBase, width: 2)),
              child: const Icon(Icons.add, color: Colors.white, size: 12))),
          ]),
          const SizedBox(height: 5),
          SizedBox(width: 64, child: Text('Таны story',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))),
        ]),
      ),
    );
  }
}

class _StoryRingItem extends StatelessWidget {
  final StoryRing ring;
  final VoidCallback onTap;
  const _StoryRingItem({required this.ring, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [
          // Avatar with gradient ring
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ring.hasUnseenStories
                  ? AppColors.accentGradient
                  : const LinearGradient(
                      colors: [Color(0xFF444444), Color(0xFF444444)]),
              boxShadow: ring.hasUnseenStories
                  ? [BoxShadow(
                      color: AppColors.accentStart.withOpacity(0.35),
                      blurRadius: 10, spreadRadius: 1)]
                  : null,
            ),
            padding: const EdgeInsets.all(2.5),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgBase,
              ),
              padding: const EdgeInsets.all(2),
              child: AppAvatar(
                imageUrl: ring.author.avatarUrl,
                initial:  ring.author.initial,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 64,
            child: Text(
              ring.author.username ?? '—',
              style: AppTextStyles.bodyXs.copyWith(
                  color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      ),
    );
  }
}
