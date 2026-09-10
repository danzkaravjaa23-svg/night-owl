import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart' show isVideoUrl;
import '../../../core/services/supabase_service.dart';
import '../providers/saved_provider.dart';
import '../widgets/story_video.dart';

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});
  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  List<Map<String, dynamic>> _reels = [];
  bool _loading = true;
  String? _error;
  bool _canCreate = false; // зөвхөн venue эзэн оруулна
  final Set<String> _liked = {};
  final Set<String> _savedIds = {};
  final Set<String> _followingIds = {};
  bool _forYou = true; // Танд / Дагадаг таб
  final PageController _pageCtrl = PageController();
  int _page = 0; // идэвхтэй (харагдаж буй) reel — зөвхөн энэ дуутай тоглоно
  bool _covered = false; // дээр нь өөр дэлгэц нээгдсэн үед видео зогсоно
  // Browser autoplay бодлого — muted эхэлж, эхний товшилтоор дуу нээгдэнэ
  final ValueNotifier<bool> _muted = ValueNotifier<bool>(true);

  String get _myId => SupabaseService.currentUser?.id ?? '';

  // Идэвхтэй табын жагсаалт: Танд = бүгд, Дагадаг = дагадаг хүмүүсийнх
  List<Map<String, dynamic>> get _visible => _forYou
      ? _reels
      : _reels.where((r) => _followingIds.contains(r['user_id'])).toList();

  @override
  void initState() {
    super.initState();
    _load();
    _checkOwner();
    // Хадгалсан постуудын эхний төлөв
    ref.read(savedPostIdsProvider.future).then((v) {
      if (mounted) setState(() => _savedIds.addAll(v));
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _muted.dispose();
    super.dispose();
  }

  Future<void> _checkOwner() async {
    if (_myId.isEmpty) return;
    try {
      final r = await SupabaseService.client.from('venues')
          .select('id').eq('owner_id', _myId).limit(1).maybeSingle();
      if (mounted) setState(() => _canCreate = r != null);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      // Дагадаг хүмүүсийн id (Дагадаг таб + Дагах pill-ийн төлөв)
      if (_myId.isNotEmpty) {
        try {
          final f = await SupabaseService.client.from('follows')
              .select('following_id').eq('follower_id', _myId);
          _followingIds
            ..clear()
            ..addAll((f as List).map((e) => e['following_id'].toString()));
        } catch (_) {}
      }

      final data = await SupabaseService.client
          .from('posts')
          .select('id, user_id, caption, media_url, likes_count, comments_count, '
              'profiles!user_id (username, avatar_url)')
          .order('created_at', ascending: false)
          .limit(50);
      final all = (data as List).cast<Map<String, dynamic>>();
      final reels = all.where((p) => isVideoUrl(p['media_url'] as String?)).toList();

      // Аль reel-уудыг лайкласныг шалгах
      if (_myId.isNotEmpty && reels.isNotEmpty) {
        final ids = reels.map((r) => r['id'] as String).toList();
        final likes = await SupabaseService.client
            .from('likes').select('post_id').eq('user_id', _myId).inFilter('post_id', ids);
        for (final l in (likes as List)) { _liked.add(l['post_id'] as String); }
      }
      if (mounted) setState(() { _reels = reels; _loading = false; _error = null; });
    } catch (_) {
      // Сүлжээний алдааг "контент алга" гэж худал харуулахгүй
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Сүлжээний алдаа. Холболтоо шалгана уу.';
        });
      }
    }
  }

  void _retry() {
    setState(() { _loading = true; _error = null; });
    _load();
  }

  void _switchTab(bool forYou) {
    if (_forYou == forYou) return;
    setState(() { _forYou = forYou; _page = 0; });
    if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
  }

  // Дээр нь дэлгэц нээхдээ идэвхтэй видеог зогсооно (дуу нь цааш явахгүй)
  Future<void> _pushCovered(String route) async {
    setState(() => _covered = true);
    await context.push(route);
    if (mounted) setState(() => _covered = false);
  }

  Future<void> _toggleLike(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final user = _myId;
    if (user.isEmpty) return;
    final wasLiked = _liked.contains(id);
    setState(() {
      if (wasLiked) {
        _liked.remove(id);
        reel['likes_count'] = (reel['likes_count'] as int? ?? 1) - 1;
      } else {
        _liked.add(id);
        reel['likes_count'] = (reel['likes_count'] as int? ?? 0) + 1;
      }
    });
    try {
      if (wasLiked) {
        await SupabaseService.client.from('likes').delete()
            .eq('user_id', user).eq('post_id', id);
      } else {
        await SupabaseService.client.from('likes').insert({'user_id': user, 'post_id': id});
      }
    } catch (_) {
      // Алдаа гарвал optimistic төлөвийг буцаана
      if (mounted) {
        setState(() {
          if (wasLiked) {
            _liked.add(id);
            reel['likes_count'] = (reel['likes_count'] as int? ?? 0) + 1;
          } else {
            _liked.remove(id);
            reel['likes_count'] = (reel['likes_count'] as int? ?? 1) - 1;
          }
        });
      }
    }
  }

  Future<void> _toggleSave(String id) async {
    if (_myId.isEmpty) return;
    final was = _savedIds.contains(id);
    setState(() { was ? _savedIds.remove(id) : _savedIds.add(id); });
    await SavedService.toggle(id, was);
    ref.invalidate(savedPostIdsProvider);
    if (!was && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Хадгаллаа'), behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1)));
    }
  }

  Future<void> _follow(String userId) async {
    if (_myId.isEmpty || userId == _myId || _followingIds.contains(userId)) return;
    setState(() => _followingIds.add(userId));
    try {
      await SupabaseService.client.from('follows').insert({
        'follower_id': _myId, 'following_id': userId});
    } catch (_) {
      if (mounted) {
        setState(() => _followingIds.remove(userId));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Дагаж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _shareReel(Map<String, dynamic> reel) async {
    final link = '${Uri.base.origin}/#/post/${reel['id']}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Линк хуулагдлаа'), behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2)));
    }
  }

  void _moreSheet(Map<String, dynamic> reel) {
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (s) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: AppColors.hairline2, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 6),
          ListTile(
            leading: const Icon(Icons.link_rounded, color: Colors.white70),
            title: Text('Линк хуулах', style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textPrimary)),
            onTap: () { Navigator.pop(s); _shareReel(reel); }),
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: AppColors.error),
            title: Text('Мэдэгдэх', style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.error)),
            onTap: () {
              Navigator.pop(s);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Мэдэгдлийг хүлээн авлаа. Баярлалаа'),
                behavior: SnackBarBehavior.floating));
            }),
          const SizedBox(height: 8),
        ])),
    );
  }

  Future<void> _deleteReel(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Бичлэг устгах уу?', style: AppTextStyles.h3),
        content: Text('Энэ live/reel бичлэгийг бүрмөсөн устгана.',
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
    try {
      await SupabaseService.client.from('posts')
          .delete().eq('id', id).eq('user_id', _myId);
      if (mounted) {
        setState(() => _reels.removeWhere((r) => r['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Бичлэг устгагдлаа')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_loading)
          const _ReelsSkeleton()
        else if (_error != null)
          _errorView()
        else if (visible.isEmpty)
          _empty(context)
        else
          PageView.builder(
            controller: _pageCtrl,
            scrollDirection: Axis.vertical,
            itemCount: visible.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final reel = visible[i];
              final id = reel['id'] as String;
              final uid = reel['user_id'] as String;
              return _ReelPage(
                key: ValueKey('reel-$id'),
                reel: reel,
                active: i == _page && !_covered,
                muted: _muted,
                liked: _liked.contains(id),
                saved: _savedIds.contains(id),
                following: uid == _myId || _followingIds.contains(uid),
                isOwn: uid == _myId,
                onLike: () => _toggleLike(reel),
                onSave: () => _toggleSave(id),
                onShare: () => _shareReel(reel),
                onMore: () => _moreSheet(reel),
                onFollow: () => _follow(uid),
                onDelete: () => _deleteReel(reel),
                onNavigate: _pushCovered,
              );
            },
          ),
        // Дээд overlay: сегмент (Дагадаг / Танд) + дуу + хайлт + нэмэх
        SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Venue эзэн create (+) — зүүн дээд
              if (_canCreate)
                _GlassIconButton(
                  icon: Icons.add_box_outlined,
                  onTap: () => _pushCovered('/reels/create'),
                )
              else
                const SizedBox(width: 40),
              const Spacer(),
              _SegmentedTabs(
                forYou: _forYou,
                onChanged: _switchTab,
              ),
              const Spacer(),
              // Дуу асаах/хаах
              ValueListenableBuilder<bool>(
                valueListenable: _muted,
                builder: (_, m, __) => _GlassIconButton(
                  icon: m ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  onTap: () => _muted.value = !m,
                )),
              const SizedBox(width: 8),
              // Хайлт
              _GlassIconButton(
                icon: Icons.search,
                onTap: () => _pushCovered('/search'),
              ),
            ],
          ))),
      ]),
    );
  }

  Widget _errorView() => Center(child: Column(mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 64),
      const SizedBox(height: 16),
      Text('Ачаалж чадсангүй', style: AppTextStyles.h2.copyWith(color: Colors.white)),
      const SizedBox(height: 8),
      Text(_error ?? '', textAlign: TextAlign.center,
        style: AppTextStyles.bodyMd.copyWith(color: Colors.white54)),
      const SizedBox(height: 20),
      _Pressable(
        onTap: _retry,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(999),
            boxShadow: AppColors.glowShadow(AppColors.accentStart)),
          child: Text('Дахин оролдох',
            style: AppTextStyles.btn.copyWith(color: Colors.white)))),
    ]));

  Widget _empty(BuildContext context) {
    // Дагадаг таб хоосон ч нийт контент байгаа эсэхийг ялгана
    final followingEmpty = !_forYou && _reels.isNotEmpty;
    return SafeArea(child: Stack(children: [
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(followingEmpty
            ? Icons.person_search_outlined : Icons.explore_outlined,
          color: Colors.white38, size: 72),
        const SizedBox(height: 16),
        Text('Контент алга байна', style: AppTextStyles.h2.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text(followingEmpty
            ? 'Дагасан хүмүүс бичлэг оруулаагүй байна'
            : _canCreate
                ? 'Эхний бичлэгээ хуваалцаарай!'
                : 'Venue эзэд богино видео нийтэлдэг',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd.copyWith(color: Colors.white54)),
        if (_canCreate && !followingEmpty) ...[
          const SizedBox(height: 20),
          // Нэгдсэн primary CTA — гараар бүтээсэн градиент товчны оронд
          GradientButton(
            label: 'Бичлэг нэмэх',
            fullWidth: false,
            borderRadius: AppRadii.pill,
            onPressed: () => _pushCovered('/reels/create'),
          ),
        ],
        const SizedBox(height: 14),
        _Pressable(
          onTap: _retry,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Дахин ачаалах', style: AppTextStyles.bodySm.copyWith(
              color: AppColors.neonCyan)))),
      ])),
      Align(alignment: Alignment.topLeft, child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Discovery', style: AppTextStyles.h2.copyWith(color: Colors.white)))),
    ]));
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
          scale: _down ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child),
      ),
    );
  }
}

/// Дугуй шилэн товч (хайлт / нэмэх) — neon hairline glass
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.42),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline2),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Дагадаг / Танд — TikTok маягийн текст таб + неон градиент underline
class _SegmentedTabs extends StatelessWidget {
  final bool forYou;
  final ValueChanged<bool> onChanged;
  const _SegmentedTabs({required this.forYou, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _tab('Дагадаг', !forYou, () => onChanged(false)),
      const SizedBox(width: 24),
      _tab('Танд', forYou, () => onChanged(true)),
    ]);
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              color: active
                  ? Colors.white : Colors.white.withValues(alpha: 0.55),
              fontSize: 15,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: -0.1,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
            child: Text(label),
          ),
          const SizedBox(height: 5),
          // Идэвхтэй табын неон underline индикатор
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: active ? 22 : 0,
            height: 3,
            decoration: BoxDecoration(
              gradient: active ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(2),
              boxShadow: active
                  ? [BoxShadow(
                      color: AppColors.magenta.withValues(alpha: 0.7),
                      blurRadius: 8)]
                  : null,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  final Map<String, dynamic> reel;
  final bool active;
  final ValueNotifier<bool> muted;
  final bool liked;
  final bool saved;
  final bool following;
  final bool isOwn;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final VoidCallback onFollow;
  final VoidCallback? onDelete;
  final Future<void> Function(String route) onNavigate;
  const _ReelPage({
    super.key,
    required this.reel,
    this.active = true,
    required this.muted,
    required this.liked, required this.saved,
    required this.following,
    required this.onLike, required this.onSave,
    required this.onShare, required this.onMore,
    required this.onFollow,
    required this.onNavigate,
    this.isOwn = false, this.onDelete,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with SingleTickerProviderStateMixin {
  // Spinning music disc
  late final AnimationController _spin;
  // Видеоны бодит тоглуулах явц (0..1) — доод progress bar
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  // Товшилтоор түр зогсоох
  final ValueNotifier<bool> _paused = ValueNotifier<bool>(false);
  IconData? _flashIcon;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    // Дахин идэвхжихэд pause төлөвийг цэвэрлэнэ
    if (widget.active && !old.active) _paused.value = false;
  }

  @override
  void dispose() {
    _spin.dispose();
    _progress.dispose();
    _paused.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  // Товшилт: эхлээд дуу нээнэ, дараа нь pause/play toggle
  void _tapVideo() {
    if (widget.muted.value) {
      widget.muted.value = false;
      _flash(Icons.volume_up_rounded);
    } else {
      _paused.value = !_paused.value;
      _flash(_paused.value ? Icons.pause_rounded : Icons.play_arrow_rounded);
    }
  }

  void _flash(IconData ic) {
    _flashTimer?.cancel();
    setState(() => _flashIcon = ic);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashIcon = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final liked = widget.liked;
    final prof = reel['profiles'] as Map?;
    final username = (prof?['username'] as String? ?? 'User').replaceAll('@', '');
    final avatarUrl = prof?['avatar_url'] as String?;
    final caption = reel['caption'] as String? ?? '';
    final likes = reel['likes_count'] as int? ?? 0;
    final comments = reel['comments_count'] as int? ?? 0;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final userId = reel['user_id'];
    // Overlay-ууд док (dockClearance) + системийн доод зайг (home indicator)
    // хоёуланг нь тооцно — эс бөгөөс индикаторын доогуур орж далдлагдана
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final dock = AppSpacing.dockClearance + bottomInset;

    return Stack(fit: StackFit.expand, children: [
      // Видео (autoplay loop) — идэвхтэй reel л тоглоно, явцыг _progress руу
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tapVideo,
        child: StoryVideoView(
          url: reel['media_url'] as String,
          // Өндрийг MediaQuery-ээс таамаглахгүй — Stack(fit: expand) хуудасны
          // БОДИТ өндрийг өгнө. Таамаглал нь PageView-ийн жинхэнэ өндрөөс
          // зөрөхөд доод талд хар зурвас үлдээж байсан.
          height: null,
          loop: true,
          active: widget.active,
          paused: _paused,
          muted: widget.muted,
          progress: _progress)),

      // Дээд + доод скрим — олон зогсоолтой зөөлөн шилжилт (уншигдах байдал)
      const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.center,
          colors: [Color(0x99000000), Color(0x33000000), Colors.transparent],
          stops: [0.0, 0.5, 1.0])))),
      const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.center,
          colors: [Color(0xE6000000), Color(0x66000000), Colors.transparent],
          stops: [0.0, 0.55, 1.0])))),

      // Товшилтын feedback icon (дуу/pause)
      IgnorePointer(child: Center(child: AnimatedOpacity(
        opacity: _flashIcon != null ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle),
          child: Icon(_flashIcon ?? Icons.play_arrow_rounded,
            color: Colors.white, size: 40)),
      ))),

      // ── Баруун үйлдлийн рейл — TikTok маягийн босоо стек ──
      Positioned(right: 10, bottom: dock + 66, child: Column(children: [
        // (1) Зохиогчийн avatar 44 — градиент ring + "+" badge → /creator/:id
        _Pressable(
          onTap: () => widget.onNavigate('/creator/$userId'),
          child: SizedBox(
            width: 48,
            height: 54,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                  boxShadow: [
                    BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.2), blurRadius: 10),
                  ],
                ),
                child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 40),
              ),
              // "+" badge — дагаагүй үед л (дарахад шууд дагана)
              if (!widget.following)
                Positioned(
                  bottom: 0,
                  child: GestureDetector(
                    onTap: widget.onFollow,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.accentGradient,
                        border: Border.all(color: Colors.black, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.magenta.withValues(alpha: 0.7),
                            blurRadius: 8, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 12),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 18),

        // (2) LIKE 30 + шахсан тоолуур — magenta glow when liked
        _RailButton(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          iconColor: liked ? AppColors.like : Colors.white,
          glow: liked ? AppColors.like : null,
          label: _fmtCount(likes),
          onTap: widget.onLike,
        ),
        const SizedBox(height: 18),

        // (3) COMMENT 30 → /post/:id (reel-ийн дуу зогсоно)
        _RailButton(
          icon: Icons.mode_comment_outlined,
          label: _fmtCount(comments),
          onTap: () => widget.onNavigate('/post/${reel['id']}'),
        ),
        const SizedBox(height: 18),

        // (4) SHARE 30 — линк хуулна
        _RailButton(
          icon: Icons.send_outlined,
          label: 'Хуваалцах',
          onTap: widget.onShare,
        ),
        const SizedBox(height: 18),

        // (5) BOOKMARK — saved_posts руу хадгална
        _RailButton(
          icon: widget.saved ? Icons.bookmark : Icons.bookmark_border,
          iconColor: widget.saved ? AppColors.saved : Colors.white,
          glow: widget.saved ? AppColors.saved : null,
          label: 'Хадгалах',
          onTap: widget.onSave,
        ),
        const SizedBox(height: 18),

        // (6) MORE — линк хуулах / мэдэгдэх
        _RailButton(icon: Icons.more_horiz, size: 26, onTap: widget.onMore),

        // Өөрийн бичлэг (live/reel) бол устгах
        if (widget.isOwn) ...[
          const SizedBox(height: 18),
          _RailButton(
            icon: Icons.delete_outline,
            iconColor: AppColors.error,
            size: 26,
            onTap: widget.onDelete,
          ),
        ],
        const SizedBox(height: 18),

        // Доод: эргэлддэг музикийн диск (creator avatar дотор)
        RotationTransition(
          turns: _spin,
          child: Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppColors.bgSurface, AppColors.bgBase]),
              border: Border.all(color: AppColors.hairline2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 16),
                BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.2), blurRadius: 14),
              ],
            ),
            child: AppAvatar(imageUrl: avatarUrl, initial: initial, size: 34),
          ),
        ),
      ])),

      // ── Доод зүүн: зохиогч + дагах pill + тайлбар + аудио мөр ──
      Positioned(left: 14, right: 84, bottom: dock + 16, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Pressable(
              onTap: () => widget.onNavigate('/creator/$userId'),
              child: Text('@$username', style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
                letterSpacing: -0.16,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
            ),
            const SizedBox(width: 10),
            // "Дагах" pill — primary градиент CTA → жинхэнэ follow (follows table)
            if (!widget.isOwn)
              widget.following
                ? Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.hairline2)),
                    child: Text('Дагасан', style: AppTextStyles.labelMd.copyWith(
                      color: Colors.white70, fontWeight: FontWeight.w700)))
                : _Pressable(
                    onTap: widget.onFollow,
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: AppColors.glowShadow(AppColors.accentStart),
                      ),
                      child: Text('Дагах', style: AppTextStyles.labelMd.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                  ),
          ]),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white, fontSize: 13.5, height: 1.5,
                shadows: [Shadow(color: Colors.black, blurRadius: 5)])),
          ],
          const SizedBox(height: 12),
          // Аудио мөр — TikTok шиг note icon + гүйдэг (marquee) текст
          Row(children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.16),
                border: Border.all(color: Colors.white24)),
              alignment: Alignment.center,
              child: const Icon(Icons.music_note, color: Colors.white, size: 13)),
            const SizedBox(width: 8),
            Flexible(
              child: SizedBox(
                height: 16,
                child: _MusicMarquee(text: '@$username · эх дуу'))),
          ]),
        ])),

      // ── Доод нимгэн прогресс шугам — үзүүр рүүгээ тодрох glow tip ──
      Positioned(left: 0, right: 0, bottom: dock, child: IgnorePointer(child: Container(
        height: 2,
        color: Colors.white.withValues(alpha: 0.14),
        child: ValueListenableBuilder<double>(
          valueListenable: _progress,
          builder: (_, p, __) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: p <= 0 ? 0.001 : p.clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0x8022E7FF), AppColors.neonCyan]),
              boxShadow: [
                BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.7), blurRadius: 8),
              ],
            )),
          ),
        ),
      ))),
    ]);
  }
}

/// Рейлийн нэг товч — TikTok хэмжээс (30) + neon drop-shadow + label + feedback
class _RailButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? glow;
  final String? label;
  final double size;
  final VoidCallback? onTap;
  const _RailButton({
    required this.icon,
    this.iconColor = Colors.white,
    this.glow,
    this.label,
    this.size = 30,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: glow != null
              ? BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(color: glow!.withValues(alpha: 0.85), blurRadius: 14),
                ])
              : null,
          child: Icon(icon, color: iconColor, size: size, shadows: const [
            Shadow(color: Colors.black54, blurRadius: 6),
          ]),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label!, style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
        ],
      ]),
    );
  }
}

/// Тоолуурыг 1.2K / 3.4M хэлбэрт шахна (рейлийн label)
String _fmtCount(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v >= 10 ? v.round() : v.toStringAsFixed(1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v >= 10 ? v.round() : v.toStringAsFixed(1)}K';
  }
  return '$n';
}

/// Аудио мөрийн marquee — багтахгүй бол зүүн тийш тасралтгүй гүйнэ,
/// багтвал энгийн текстээр үлдэнэ (хоёр талдаа зөөлөн fade)
class _MusicMarquee extends StatefulWidget {
  final String text;
  const _MusicMarquee({required this.text});
  @override
  State<_MusicMarquee> createState() => _MusicMarqueeState();
}

class _MusicMarqueeState extends State<_MusicMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 7))..repeat();

  static const double _gap = 36;

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.92),
      fontSize: 12, fontWeight: FontWeight.w600,
      shadows: const [Shadow(color: Colors.black, blurRadius: 4)]);
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 1, textDirection: TextDirection.ltr)..layout();
      final textW = painter.width;
      // Багтаж байвал хөдөлгөөнгүй
      if (textW <= box.maxWidth) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(widget.text, maxLines: 1,
              overflow: TextOverflow.ellipsis, style: style));
      }
      final total = textW + _gap;
      return ClipRect(
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [
            Colors.transparent, Colors.white, Colors.white, Colors.transparent,
          ], stops: [0.0, 0.06, 0.94, 1.0]).createShader(r),
          blendMode: BlendMode.dstIn,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Transform.translate(
              offset: Offset(-_c.value * total, 0),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.text, maxLines: 1, style: style),
                  const SizedBox(width: _gap),
                  Text(widget.text, maxLines: 1, style: style),
                  const SizedBox(width: _gap),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Ачаалах үеийн бүтэн дэлгэцийн skeleton (spinner-ийн оронд)
class _ReelsSkeleton extends StatefulWidget {
  const _ReelsSkeleton();
  @override
  State<_ReelsSkeleton> createState() => _ReelsSkeletonState();
}

class _ReelsSkeletonState extends State<_ReelsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  Widget _box(double w, double h, {BoxShape shape = BoxShape.rectangle}) =>
      Container(
        width: w, height: h,
        decoration: BoxDecoration(
          color: Colors.white10,
          shape: shape,
          borderRadius:
              shape == BoxShape.circle ? null : BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Opacity(
          opacity: 0.45 + _c.value * 0.4, child: child),
        child: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF14101f), Color(0xFF1e1630), Color(0xFF14101f)]))),
          // Баруун рейлийн placeholder
          Positioned(right: 14, bottom: 170, child: Column(children: [
            for (var i = 0; i < 4; i++) ...[
              _box(34, 34, shape: BoxShape.circle),
              const SizedBox(height: 26),
            ],
          ])),
          // Доод зүүн: текстийн мөрүүд
          Positioned(left: 14, bottom: 120, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              _box(120, 14),
              const SizedBox(height: 10),
              _box(220, 10),
              const SizedBox(height: 8),
              _box(160, 10),
            ])),
        ]),
      );
}
