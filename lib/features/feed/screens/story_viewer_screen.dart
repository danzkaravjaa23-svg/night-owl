import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/web_audio.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/network_video.dart' show isVideoUrl;
import '../../../core/services/supabase_service.dart';
import '../../../models/story.dart';
import '../providers/stories_provider.dart';
import '../widgets/story_video.dart';

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
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  final WebAudio _musicPlayer = WebAudio();
  String? _playingMusicUrl;
  // story_id → лайк дарсан эсэх (одоогийн харагдаж буй story-ийн төлөв)
  final Map<String, bool> _likedMap = {};

  // Видео удирдлага
  final ValueNotifier<bool> _videoPaused = ValueNotifier<bool>(false);
  // Browser дуутай autoplay-г блоклодог тул muted эхэлж, эхний gesture дээр нээнэ
  final ValueNotifier<bool> _videoMuted = ValueNotifier<bool>(true);
  bool _userMuted = false;   // хэрэглэгч speaker-ээр өөрөө хаасан
  bool _soundUnlocked = false;

  // Doube-tap лайкийн том зүрх
  bool _bigHeart = false;
  Timer? _bigHeartTimer;

  // Доош чирж хаах
  double _dragY = 0;
  bool _dragging = false;

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _ringIndex = widget.initialRingIndex;
    _progressCtrl = AnimationController(vsync: this);
    // Зөвхөн жинхэнэ дуустал л дараагийн story руу шилжинэ.
    // (stop() дуудахад .then() callback давхар ажиллаж story-г хурдасгадаг
    //  байсныг status listener-ээр зассан.)
    _progressCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) _nextStory();
    });
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) _pause();
    });
    _startProgress();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    _musicPlayer.dispose();
    _videoPaused.dispose();
    _videoMuted.dispose();
    _bigHeartTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  StoryRing get _currentRing => widget.rings[_ringIndex];
  Story     get _currentStory => _currentRing.stories[_storyIndex];
  int       get _totalStories => _currentRing.stories.length;
  bool      get _isVideoStory =>
      _currentStory.mediaType == 'video' || isVideoUrl(_currentStory.mediaUrl);

  // Идэвхтэй story-ийн хөгжмийг тааруулж тоглуулна
  void _syncMusic() {
    final url = _currentStory.musicUrl;
    if (url == null || url.isEmpty) {
      _playingMusicUrl = null;
      _musicPlayer.stop();
      return;
    }
    if (url == _playingMusicUrl) {
      _musicPlayer.resume();
      return;
    }
    _playingMusicUrl = url;
    _musicPlayer.play(url, loop: true);
  }

  // ── Түр зогсоох / үргэлжлүүлэх (progress + хөгжим + видео хамт) ──
  void _pause() {
    _progressCtrl.stop();
    _musicPlayer.pause();
    _videoPaused.value = true;
  }

  void _resume() {
    _musicPlayer.resume();
    _videoPaused.value = false;
    _progressCtrl.forward();
  }

  // Эхний хэрэглэгчийн gesture дээр дууг нээнэ (autoplay unlock)
  void _unlockSound() {
    if (_soundUnlocked) return;
    _soundUnlocked = true;
    if (!_userMuted) _videoMuted.value = false;
  }

  void _toggleMute() {
    _soundUnlocked = true;
    final nowMuted = !_videoMuted.value;
    _videoMuted.value = nowMuted;
    _userMuted = nowMuted;
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
        'story_media_url': _currentStory.mediaUrl, // story-д хариулсан тэмдэг
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Илгээлээ ✓'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating));
      }
    } catch (_) {
      if (mounted) {
        _replyCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Илгээж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
    // үргэлжлүүлэх (дуустал нь status listener шилжүүлнэ)
    if (mounted) _resume();
  }

  void _startProgress() {
    _progressCtrl.reset();
    _videoPaused.value = false;
    // Бага/буруу утганаас хамгаалж хязгаар тавина — зураг ~5с,
    // видеог хадгалсан бодит уртаар (metadata ирэхэд дахин нарийвчилна).
    final secs = _isVideoStory
        ? _currentStory.duration.clamp(3, 90)
        : _currentStory.duration.clamp(5, 30);
    _progressCtrl.duration = Duration(seconds: secs.toInt());
    _progressCtrl.forward();
    _syncMusic();
    StoryService.markViewed(_currentStory.id);
    _loadLiked(_currentStory.id);
  }

  // Видеоны metadata-аас бодит урт ирэхэд progress-ийг тааруулна
  void _onVideoDuration(double secs) {
    if (!mounted) return;
    final d = Duration(milliseconds: (secs.clamp(1, 120) * 1000).round());
    if (_progressCtrl.duration == d) return;
    final wasAnimating = _progressCtrl.isAnimating;
    final v = _progressCtrl.value;
    _progressCtrl.stop();
    _progressCtrl.duration = d;
    if (wasAnimating) _progressCtrl.forward(from: v);
  }

  // Видео дуусмагц дараагийн story руу (progress-оос түрүүлж дуусвал)
  void _onVideoEnded() {
    if (!mounted) return;
    _progressCtrl.value = 1.0; // status listener _nextStory дуудна
  }

  // Лайкийн төлөвийг ачаална — хэрэглэгч түрүүлж дарсан бол дарж бичихгүй
  Future<void> _loadLiked(String storyId) async {
    if (_likedMap.containsKey(storyId)) return;
    final liked = await StoryService.isLiked(storyId);
    if (mounted) setState(() => _likedMap.putIfAbsent(storyId, () => liked));
  }

  // Зүрх дарж лайк toggle хийнэ (DM илгээхгүй); алдаа гарвал буцаана
  Future<void> _toggleLike() async {
    final id = _currentStory.id;
    final now = !(_likedMap[id] ?? false);
    setState(() => _likedMap[id] = now);
    final ok = await StoryService.toggleLike(id, now);
    if (!ok && mounted) setState(() => _likedMap[id] = !now);
  }

  // Double-tap → лайк + том зүрхний анимац
  void _doubleTapLike() {
    _unlockSound();
    if (!(_likedMap[_currentStory.id] ?? false)) _toggleLike();
    _bigHeartTimer?.cancel();
    setState(() => _bigHeart = true);
    _bigHeartTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _bigHeart = false);
    });
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
      _startProgress();
    } else {
      // Хамгийн эхний story — Instagram шиг одоогийнхоо эхнээс дахин тоглуулна
      // (өмнө нь controller зогссон хэвээр үлдэж хөлддөг байсан)
      _startProgress();
    }
  }

  void _nextRing() {
    if (_ringIndex < widget.rings.length - 1) {
      setState(() { _ringIndex++; _storyIndex = 0; });
      _startProgress();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story  = _currentStory;
    final author = _currentRing.author;
    final isVideo = _isVideoStory;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedContainer(
        duration: _dragging
            ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _dragY, 0),
        color: Colors.black,
        child: GestureDetector(
        onTapUp: (d) {
          _unlockSound();
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
              _pause();
            } else {
              _resume();
            }
          }
        },
        onDoubleTap: _doubleTapLike,
        onLongPressStart: (_) { _unlockSound(); _pause(); },
        onLongPressEnd:   (_) => _resume(),
        // Доош чирж хаах
        onVerticalDragStart: (_) {
          _dragging = true;
          _progressCtrl.stop();
          _musicPlayer.pause();
          _videoPaused.value = true;
        },
        onVerticalDragUpdate: (d) => setState(() =>
            _dragY = (_dragY + d.delta.dy).clamp(0.0, 600.0)),
        onVerticalDragEnd: (_) {
          if (_dragY > 120) {
            context.pop();
          } else {
            setState(() { _dragY = 0; _dragging = false; });
            _resume();
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          // ── Media (зураг эсвэл видео) ──
          if (isVideo)
            StoryVideoView(
              key: ValueKey('story-${story.id}'),
              url: story.mediaUrl,
              height: MediaQuery.of(context).size.height,
              loop: false,
              paused: _videoPaused,
              muted: _videoMuted,
              onDuration: _onVideoDuration,
              onEnded: _onVideoEnded)
          else
            CachedNetworkImage(
              imageUrl: story.mediaUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const _ShimmerBox(),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF1a0a2e),
                child: const Center(child: Text('📸',
                    style: TextStyle(fontSize: 64))),
              ),
            ),

          // ── Скрим давхарга — олон зогсоолтой зөөлөн шилжилт (дээд + доод) ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0x99000000), Color(0x33000000), Colors.transparent],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Color(0x8C000000), Color(0x2E000000), Colors.transparent],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // ── Progress bars ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 12, right: 12,
            // Нимгэн progress — идэвхтэй хэсэг үзүүр рүүгээ тодорч glow-той
            child: Row(
              children: List.generate(_totalStories, (i) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 2,
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
                                    gradient: const LinearGradient(
                                      colors: [Colors.white70, Colors.white]),
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withValues(alpha: 0.55),
                                        blurRadius: 6),
                                    ])),
                              ))
                          : const SizedBox.shrink(),
                ),
              )),
            ),
          ),

          // ── Author header ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 22,
            left: 12, right: 4,
            child: Row(children: [
              AppAvatar(
                imageUrl: author.avatarUrl,
                initial:  author.initial,
                size: 36, showRing: true,
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
                  const SizedBox(height: 1),
                  // Micro цагийн шошго
                  Text(_timeAgo(story.createdAt),
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 10,
                          fontWeight: FontWeight.w500, letterSpacing: 0.3)),
                ],
              )),
              // Дуу асаах/хаах (зөвхөн видео story)
              if (isVideo)
                _Pressable(
                  onTap: _toggleMute,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _videoMuted,
                      builder: (_, m, __) => Icon(
                        m ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: Colors.white, size: 22)),
                  )),
              // Хаах 32 — 40px+ хүрэлтийн талбай
              _Pressable(
                onTap: () => context.pop(),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close, color: Colors.white, size: 32)),
              ),
            ]),
          ),

          // ── Хөгжмийн шошго ──
          if (story.musicUrl != null && story.musicUrl!.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 66,
              left: 12,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.hairline2),
                  boxShadow: AppColors.shadowCard),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Градиент нот диск — аудио мөрийн дохио
                  Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.accentGradient),
                    alignment: Alignment.center,
                    child: const Icon(Icons.music_note_rounded,
                      color: Colors.white, size: 13)),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.6),
                    child: Text(
                      [story.musicTitle, story.musicArtist]
                          .where((e) => e != null && e.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white,
                        fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),

          // ── Double-tap том зүрх ──
          IgnorePointer(child: Center(child: AnimatedScale(
            scale: _bigHeart ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: _bigHeart ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.favorite,
                color: Color(0xFFFF3B5C), size: 96,
                shadows: [Shadow(color: Colors.black45, blurRadius: 18)]),
            )))),

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
                  // ── Түргэн реакц — Instagram маягийн emoji мөр
                  //    (reply талбар фокустай үед л гарч ирнэ; _sendReply-г
                  //     хэвээр ашиглана → DM болж илгээгдэнэ) ──
                  if (_currentRing.userId != _myId)
                    AnimatedBuilder(
                      animation: _replyFocus,
                      builder: (_, __) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SizeTransition(
                            sizeFactor: anim,
                            alignment: Alignment.topCenter, child: child)),
                        child: _replyFocus.hasFocus
                            ? Padding(
                                key: const ValueKey('quick-reactions'),
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    for (final e in const [
                                      '🔥', '😂', '😍', '👏', '🎉', '💜'])
                                      _Pressable(
                                        onTap: () => _sendReply(e),
                                        child: Text(e, style: const TextStyle(
                                            fontSize: 30))),
                                  ]))
                            : const SizedBox.shrink(
                                key: ValueKey('no-reactions')),
                      )),
                  // ── Reply — шилэн pill бар (зөвхөн бусдын story дээр) ──
                  if (_currentRing.userId != _myId)
                    Row(children: [
                      // Шилэн pill талбар — фокуслоход хүрээ гэрэлтэнэ
                      Expanded(child: AnimatedBuilder(
                        animation: _replyFocus,
                        builder: (_, __) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: AppColors.bgElevated.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: _replyFocus.hasFocus
                                  ? Colors.white70 : AppColors.hairline2),
                            boxShadow: AppColors.shadowCard),
                          child: TextField(
                            controller: _replyCtrl,
                            focusNode: _replyFocus,
                            style: const TextStyle(color: Colors.white),
                            textInputAction: TextInputAction.send,
                            onSubmitted: _sendReply,
                            decoration: InputDecoration(
                              hintText: 'Мессеж илгээх...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55)),
                              filled: false, isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 13),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            )),
                        ))),
                      const SizedBox(width: 8),
                      // Зүрх — шилэн дугуй товч, дарахад pop анимац
                      _Pressable(
                        onTap: _toggleLike,
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.bgElevated.withValues(alpha: 0.72),
                            border: Border.all(color: AppColors.hairline2)),
                          alignment: Alignment.center,
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(
                                '${story.id}-${_likedMap[story.id] ?? false}'),
                            tween: Tween(begin: 0.7, end: 1.0),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutBack,
                            builder: (_, s, child) =>
                                Transform.scale(scale: s, child: child),
                            child: Icon(
                              (_likedMap[story.id] ?? false)
                                  ? Icons.favorite : Icons.favorite_border,
                              color: (_likedMap[story.id] ?? false)
                                  ? const Color(0xFFFF3B5C) : Colors.white,
                              size: 24)),
                        )),
                      const SizedBox(width: 8),
                      // Илгээх — градиент дугуй CTA + glow
                      _Pressable(
                        onTap: () => _sendReply(_replyCtrl.text),
                        child: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.accentGradient,
                            boxShadow:
                                AppColors.glowShadow(AppColors.accentStart)),
                          alignment: Alignment.center,
                          child: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20))),
                    ]),
                ])),
            )),
        ]),
        ),
      ),
    );
  }

  // Venue/mention pill — шилэн glass хэв (bgElevated + hairline)
  Widget _storyPill(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.hairline2),
      boxShadow: AppColors.shadowCard),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppColors.neonCyan, size: 13),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(
        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    ]));

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}м өмнө';
    return '${diff.inHours}ц өмнө';
  }
}

// Дарахад жижигрэх + hover курсор — веб мэдрэмж
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child),
      ),
    );
  }
}

// Зураг ачаалах үеийн бүдэг skeleton (spinner-ийн оронд)
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();
  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                const Color(0xFF14101f),
                Color.lerp(const Color(0xFF1e1630), const Color(0xFF2a1f42),
                    _c.value)!,
                const Color(0xFF14101f),
              ])),
        ),
      );
}
