import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../utils/live_unload.dart';
import '../widgets/tap_scale.dart';

class LiveViewerScreen extends StatefulWidget {
  final String liveId;
  const LiveViewerScreen({super.key, required this.liveId});
  @override
  State<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<LiveViewerScreen> {
  Map<String, dynamic>? _stream;
  Map<String, dynamic>? _host;
  String? _venueName;
  List<Map<String, dynamic>> _comments = [];
  final Map<String, String> _names = {};
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  StreamSubscription? _commentSub;
  StreamSubscription? _streamSub;
  Timer? _commentRetry;
  Timer? _streamRetry;
  bool _ended = false;
  bool _loading = true;
  bool _loadError = false;
  bool _counted = false;     // increment оролдсон эсэх
  bool _incremented = false; // increment амжилттай болсон эсэх
  bool _disposed = false;

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeComments();
    _subscribeStream();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _loadError = false; });
    try {
      final s = await SupabaseService.client
          .from('live_streams')
          .select('id, user_id, title, viewer_count, is_live, venue_id')
          .eq('id', widget.liveId)
          .maybeSingle();
      if (s == null) {
        if (mounted) setState(() { _ended = true; _loading = false; });
        return;
      }
      final host = await SupabaseService.client
          .from('profiles')
          .select('id, username, avatar_url')
          .eq('id', s['user_id'])
          .maybeSingle();
      String? venueName;
      if (s['venue_id'] != null) {
        final v = await SupabaseService.client.from('venues')
            .select('name').eq('id', s['venue_id']).maybeSingle();
        venueName = v?['name'] as String?;
      }
      if (mounted) {
        setState(() {
          _stream = s;
          _host = host;
          _venueName = venueName;
          _ended = s['is_live'] != true;
          _loading = false;
        });
      }
      // Viewer count +1 (нэг л удаа, амжилттай болсон үед л буцааж хасна)
      if (!_counted && s['is_live'] == true) {
        _counted = true;
        SupabaseService.client.rpc('increment_viewer',
            params: {'p_stream': widget.liveId}).then((_) {
          if (_disposed) {
            // Дэлгэц аль хэдийн хаагдчихсан — шууд буцааж хасна
            _decrement();
          } else {
            _incremented = true;
            _registerUnloadDecrement();
          }
        }).catchError((_) {});
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  void _decrement() {
    SupabaseService.client.rpc('decrement_viewer',
        params: {'p_stream': widget.liveId}).then((_) {}).catchError((_) {});
  }

  // Таб хаагдах/refresh үед ч viewer тоог буцааж хасна
  void _registerUnloadDecrement() {
    final token = SupabaseService.client.auth.currentSession?.accessToken
        ?? AppConstants.supabaseAnonKey;
    registerUnloadRequest('live-viewer-${widget.liveId}',
      url: '${AppConstants.supabaseUrl}/rest/v1/rpc/decrement_viewer',
      method: 'POST',
      headers: {
        'apikey': AppConstants.supabaseAnonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: () => jsonEncode({'p_stream': widget.liveId}));
  }

  void _subscribeComments() {
    _commentSub?.cancel();
    _commentSub = SupabaseService.client
        .from('live_comments')
        .stream(primaryKey: ['id'])
        .eq('stream_id', widget.liveId)
        .order('created_at', ascending: true)
        .listen((rows) async {
          final list = List<Map<String, dynamic>>.from(rows);
          await _resolveNames(list);
          if (mounted) {
            setState(() => _comments = list);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              }
            });
          }
        }, onError: (e) {
          // Realtime тасарвал 2с дараа дахин холбогдоно
          debugPrint('live comments stream error: $e');
          _commentRetry?.cancel();
          _commentRetry = Timer(const Duration(seconds: 2), () {
            if (mounted) _subscribeComments();
          });
        });
  }

  void _subscribeStream() {
    _streamSub?.cancel();
    _streamSub = SupabaseService.client
        .from('live_streams')
        .stream(primaryKey: ['id'])
        .eq('id', widget.liveId)
        .listen((rows) {
          if (rows.isEmpty) return;
          final s = rows.first;
          if (mounted) {
            setState(() {
              _stream = {...?_stream, ...s};
              if (s['is_live'] != true) _ended = true;
            });
          }
        }, onError: (e) {
          debugPrint('live stream watcher error: $e');
          _streamRetry?.cancel();
          _streamRetry = Timer(const Duration(seconds: 2), () {
            if (mounted) _subscribeStream();
          });
        });
  }

  Future<void> _resolveNames(List<Map<String, dynamic>> comments) async {
    final missing = comments
        .map((c) => c['user_id'] as String?)
        .whereType<String>()
        .where((id) => !_names.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    try {
      final profs = await SupabaseService.client
          .from('profiles')
          .select('id, username')
          .inFilter('id', missing);
      for (final p in (profs as List).cast<Map<String, dynamic>>()) {
        _names[p['id'] as String] = p['username'] as String? ?? 'User';
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _myId.isEmpty) return;
    _ctrl.clear();
    try {
      await SupabaseService.client.from('live_comments').insert({
        'stream_id': widget.liveId,
        'user_id': _myId,
        'text': text,
      });
    } catch (_) {
      if (mounted) {
        _ctrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Илгээж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  void _back() {
    // Deep link-ээр орсон бол pop хийх юм байхгүй → feed рүү
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/feed');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_incremented) _decrement();
    unregisterUnloadRequest('live-viewer-${widget.liveId}');
    _commentSub?.cancel();
    _streamSub?.cancel();
    _commentRetry?.cancel();
    _streamRetry?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _stream?['title'] as String? ?? 'Live';
    final viewers = _stream?['viewer_count'] as int? ?? 0;
    final hostName = _host?['username'] as String? ?? 'User';
    // Газрын нэр байвал түүгээр харуулна
    final username = (_venueName != null && _venueName!.isNotEmpty) ? _venueName! : hostName;
    final avatarUrl = _host?['avatar_url'] as String?;
    final initial = username.replaceAll('@', '').isNotEmpty
        ? username.replaceAll('@', '')[0].toUpperCase() : '?';
    final showError = _loadError && _stream == null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Видео талбай (LiveKit залгах хүртэл placeholder) ──
        Positioned.fill(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1024), Color(0xFF0A0A0F)])),
          child: Center(child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _loading
              ? const _CenterSkeleton()
              : showError
                ? Column(key: const ValueKey('err'),
                    mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_rounded,
                      color: Colors.white30, size: 56),
                    const SizedBox(height: 14),
                    Text('Мэдээлэл ачаалж чадсангүй',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary)),
                    const SizedBox(height: 14),
                    TapScale(
                      onTap: _load,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: AppColors.accentGradient,
                          borderRadius: BorderRadius.circular(22)),
                        child: Text('Дахин оролдох',
                          style: AppTextStyles.btnSm.copyWith(
                            color: Colors.white)))),
                  ])
                : Column(key: const ValueKey('info'),
                    mainAxisSize: MainAxisSize.min, children: [
                    _ended
                        ? AppAvatar(imageUrl: avatarUrl, initial: initial,
                            size: 96, showRing: true)
                        : _PulseAvatar(avatarUrl: avatarUrl, initial: initial),
                    const SizedBox(height: 18),
                    if (_ended)
                      Text('Live дууслаа', style: AppTextStyles.h2)
                    else ...[
                      Text(username.replaceAll('@', ''), style: AppTextStyles.h2),
                      const SizedBox(height: 6),
                      Text('🔴 Шууд дамжуулж байна',
                        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      // Видео дамжуулалт (WebRTC) хараахан залгагдаагүй тул
                      // хэрэглэгчид чат горимд байгааг илэн далангүй мэдэгдэнэ
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Одоохондоо чат горимд — сэтгэгдэл бичээд оролцоорой',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary))),
                    ],
                  ]),
          )),
        )),

        // ── Дээд мэдээлэл ──
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            // Буцах — шилэн дугуй товч
            TapScale(
              onTap: _back,
              child: Container(
                width: 40, height: 40,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgElevated.withValues(alpha: 0.72),
                  border: Border.all(color: AppColors.hairline2)),
                alignment: Alignment.center,
                child: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 18))),
            if (_loading) ...[
              // Skeleton — profile ирэхээс өмнө '?' аватар анивчихгүй
              const _BarSkeleton(width: 34, height: 34, radius: 17),
              const SizedBox(width: 8),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _BarSkeleton(width: 110, height: 12, radius: 6),
                  SizedBox(height: 5),
                  _BarSkeleton(width: 70, height: 9, radius: 5),
                ])),
            ] else ...[
              // Хостын мэдээлэл — шилэн pill chip (TikTok live header маяг)
              Expanded(child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.hairline2),
                    boxShadow: AppColors.shadowCard),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    AppAvatar(imageUrl: avatarUrl, initial: initial, size: 34),
                    const SizedBox(width: 8),
                    Flexible(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(username.replaceAll('@', ''),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelLg.copyWith(
                            color: Colors.white)),
                        Text(title, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyXs.copyWith(
                            color: Colors.white70)),
                      ])),
                  ])))),
              const SizedBox(width: 8),
            ],
            // LIVE / ДУУССАН — лугшдаг цэгтэй pill badge
            if (!_loading) _LivePill(ended: _ended),
            // Viewer count — шилэн chip (дууссан бол нуана)
            if (!_loading && !_ended) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.hairline2)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.visibility_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text('$viewers', style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ])),
            ],
          ]),
        )),

        // ── Доод: коммент + оруулах ──
        if (!_ended && !_loading && !showError)
          Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Comments overlay — өндөрссөн (320), дээд ирмэг нь илүү урт
              // зөөлөн уусна; мөр бүр TikTok live маягийн шилэн bubble
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.white],
                    stops: [0.0, 0.30]).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    itemCount: _comments.length,
                    itemBuilder: (_, i) {
                      final c = _comments[i];
                      final name = _names[c['user_id']] ?? 'User';
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(14)),
                          child: RichText(text: TextSpan(
                            style: AppTextStyles.bodySm.copyWith(
                              color: Colors.white),
                            children: [
                              TextSpan(text: '${name.replaceAll('@', '')}  ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF9500))),
                              TextSpan(text: c['text'] as String? ?? ''),
                            ]))));
                    }))),
              // Input
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  Expanded(child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Сэтгэгдэл...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                      filled: true,
                      fillColor: AppColors.bgElevated.withValues(alpha: 0.72),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: AppColors.hairline2)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: AppColors.hairline2)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: Colors.white70))))),
                  const SizedBox(width: 8),
                  // Илгээх — градиент дугуй CTA + glow
                  TapScale(
                    onTap: _send,
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.accentGradient,
                        boxShadow: AppColors.glowShadow(AppColors.accentStart)),
                      child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18))),
                ])),
            ]),
          )),

        if (_ended)
          Positioned(left: 0, right: 0, bottom: 40, child: Center(
            child: TapScale(
              onTap: _back,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.hairline)),
                child: Text('Буцах', style: AppTextStyles.btn.copyWith(
                  color: AppColors.textPrimary)))))),
      ]),
    );
  }
}

// ── LIVE pill — улаан цэг нь лугшдаг (шууд дамжуулалтын дохио) ──
class _LivePill extends StatefulWidget {
  final bool ended;
  const _LivePill({required this.ended});
  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.ended) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(999)),
        child: const Text('ДУУССАН', style: TextStyle(
          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900,
          letterSpacing: 0.6)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppColors.glowShadow(const Color(0xFFFF3B30),
            alpha: 0.5, blur: 14, offset: Offset.zero)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween<double>(begin: 0.25, end: 1.0).animate(_c),
          child: Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(
              color: Colors.white, shape: BoxShape.circle))),
        const SizedBox(width: 5),
        const Text('LIVE', style: TextStyle(
          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900,
          letterSpacing: 0.8)),
      ]));
  }
}

// ── Live хэсгийн pulsing аватар ───────────────────────────

/// Шууд дамжуулж байгаа мэдрэмж өгөх — аватарын гадуур лугшдаг цагираг
class _PulseAvatar extends StatefulWidget {
  final String? avatarUrl;
  final String initial;
  const _PulseAvatar({this.avatarUrl, required this.initial});
  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132, height: 132,
    child: Stack(alignment: Alignment.center, children: [
      // Гадуур тэлж уусах цагираг
      AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Container(
            width: 96 + t * 36, height: 96 + t * 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFF3B30).withValues(alpha: (1 - t) * 0.6),
                width: 2)));
        }),
      AppAvatar(imageUrl: widget.avatarUrl, initial: widget.initial,
        size: 96, showRing: true),
    ]));
}

// ── Skeleton widgets ─────────────────────────────────────

/// Голын том skeleton (аватар + 2 мөр) — зөөлөн анивчина
class _CenterSkeleton extends StatelessWidget {
  const _CenterSkeleton();
  @override
  Widget build(BuildContext context) => const Column(
    key: ValueKey('skeleton'),
    mainAxisSize: MainAxisSize.min, children: [
      _BarSkeleton(width: 96, height: 96, radius: 48),
      SizedBox(height: 18),
      _BarSkeleton(width: 140, height: 16, radius: 8),
      SizedBox(height: 8),
      _BarSkeleton(width: 100, height: 12, radius: 6),
    ]);
}

/// Анивчдаг skeleton хэсэг
class _BarSkeleton extends StatefulWidget {
  final double width, height, radius;
  const _BarSkeleton({required this.width, required this.height, required this.radius});
  @override
  State<_BarSkeleton> createState() => _BarSkeletonState();
}

class _BarSkeletonState extends State<_BarSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
    lowerBound: 0.35, upperBound: 0.75)..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(widget.radius))));
}
