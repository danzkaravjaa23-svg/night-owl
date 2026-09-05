// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../utils/live_unload.dart';
import '../widgets/tap_scale.dart';

class GoLiveScreen extends ConsumerStatefulWidget {
  const GoLiveScreen({super.key});
  @override
  ConsumerState<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends ConsumerState<GoLiveScreen> {
  final _titleCtrl  = TextEditingController(text: 'Live 🎤');
  final _chatCtrl   = TextEditingController();
  final _chatScroll = ScrollController();

  html.MediaStream?    _stream;
  bool _cameraReady = false;
  bool _isFront     = true;

  String? _streamId;
  String? _venueId;     // бизнес эзний venue
  String? _venueName;
  bool _isLive   = false;
  bool _starting = false;
  bool _saving   = false;
  bool _saved    = false;
  int  _viewers  = 0;
  String? _error;

  final List<Map<String, dynamic>> _comments = [];
  final Map<String, String> _names = {}; // userId → username кэш
  StreamSubscription? _chatSub;
  Timer? _chatRetry;
  Timer? _viewerTimer;

  html.MediaRecorder? _recorder;
  final List<html.Blob> _chunks = [];

  // Video element-ийг НЭГ удаа үүсгэж, factory-г нэг удаа бүртгэнэ.
  // Flip хийхэд зөвхөн srcObject солино (давхар бүртгэл = хөлдсөн preview).
  final html.VideoElement _videoEl = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..setAttribute('playsinline', '');

  late final String _viewId =
      'live-cam-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _videoEl.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover';
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) => _videoEl);
    _initCamera(front: true);
    _prefillVenue();
  }

  // Бизнес эзэн бол live-ийг газрынх нь нэрээр
  Future<void> _prefillVenue() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    try {
      final v = await SupabaseService.client.from('venues')
          .select('id, name').eq('owner_id', me).limit(1).maybeSingle();
      if (v != null && mounted) {
        setState(() {
          _venueId = v['id'] as String;
          _venueName = v['name'] as String?;
          if (_venueName != null && _venueName!.isNotEmpty) _titleCtrl.text = _venueName!;
        });
      }
    } catch (_) {}
  }

  Future<void> _initCamera({bool front = true}) async {
    _stream?.getTracks().forEach((t) => t.stop());
    if (mounted) setState(() { _cameraReady = false; _error = null; });

    try {
      // Эхлээд facingMode-той оролдоод, болохгүй бол энгийн video:true
      html.MediaStream? stream;
      try {
        stream = await html.window.navigator.mediaDevices!.getUserMedia({
          'video': {'facingMode': front ? 'user' : 'environment'},
          'audio': true,
        });
      } catch (_) {
        stream = await html.window.navigator.mediaDevices!.getUserMedia({
          'video': true, 'audio': true,
        });
      }

      _stream = stream;
      _isFront = front;

      // Ижил element дээр stream-ээ солино — preview хэзээ ч хөлддөггүй
      _videoEl.srcObject = stream;
      _videoEl.style.transform = front ? 'scaleX(-1)' : 'none';

      // Metadata ачаалагдахыг хүлээнэ; 5с-с удаавал шууд үргэлжлүүлнэ
      try {
        await _videoEl.onLoadedMetadata.first
            .timeout(const Duration(seconds: 5));
      } on TimeoutException catch (_) {}

      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
          'Камер нэвтрэх боломжгүй.\nBrowser-т камерын зөвшөөрөл олгоно уу.');
      }
    }
  }

  Future<void> _flipCamera() async => _initCamera(front: !_isFront);

  // Live-ийн мөрийг дуусгах (fire & forget)
  void _endStreamRow(String sid) {
    SupabaseService.client.from('live_streams').update({
      'is_live': false,
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', sid).then((_) {}).catchError((_) {});
  }

  // Таб хаагдах/refresh үед live-г автоматаар дуусгах хамгаалалт
  void _registerUnloadGuard(String sid) {
    final token = SupabaseService.client.auth.currentSession?.accessToken
        ?? AppConstants.supabaseAnonKey;
    registerUnloadRequest('go-live',
      url: '${AppConstants.supabaseUrl}/rest/v1/live_streams?id=eq.$sid',
      method: 'PATCH',
      headers: {
        'apikey': AppConstants.supabaseAnonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: () => jsonEncode({
        'is_live': false,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }));
  }

  Future<void> _goLive() async {
    if (_starting) return;
    setState(() { _starting = true; _error = null; });
    try {
      final user = SupabaseService.currentUser!;
      final res = await SupabaseService.client
          .from('live_streams')
          .insert({
            'user_id': user.id,
            'title': _titleCtrl.text.trim().isEmpty ? 'Live' : _titleCtrl.text.trim(),
            'is_live': true,
            'started_at': DateTime.now().toIso8601String(),
            if (_venueId != null) 'venue_id': _venueId,
          })
          .select().single();

      final sid = res['id'] as String;

      // Хэрэглэгч хүлээлгүй гарчихсан бол — ghost live үлдээхгүй шууд хаана
      if (!mounted) { _endStreamRow(sid); return; }

      _streamId = sid;
      _subscribeChat(sid);
      _registerUnloadGuard(sid);

      // Үзэгчийн тоог 5с тутам шалгана
      _viewerTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        try {
          final r = await SupabaseService.client
              .from('live_streams').select('viewer_count')
              .eq('id', sid).single();
          if (mounted) setState(() => _viewers = r['viewer_count'] as int? ?? 0);
        } catch (_) {}
      });

      // MediaRecorder эхлүүлнэ (replay-д зориулж)
      if (_stream != null) {
        _chunks.clear();
        try {
          _recorder = html.MediaRecorder(_stream!,
              {'mimeType': 'video/webm;codecs=vp9,opus'});
        } catch (_) {
          try { _recorder = html.MediaRecorder(_stream!, {'mimeType': 'video/webm'}); }
          catch (_) { _recorder = html.MediaRecorder(_stream!); }
        }
        _recorder!.addEventListener('dataavailable', (event) {
          final e = event as html.BlobEvent;
          if (e.data != null && e.data!.size > 0) _chunks.add(e.data!);
        });
        _recorder!.start(5000);
      }

      setState(() { _isLive = true; _starting = false; });
    } catch (e) {
      debugPrint('goLive error: $e');
      if (mounted) {
        setState(() {
          _error = 'Live эхлүүлж чадсангүй. Дахин оролдоно уу.';
          _starting = false;
        });
      }
    }
  }

  // Чат subscription — тасарвал 2с дараа дахин холбогдоно
  void _subscribeChat(String sid) {
    _chatSub?.cancel();
    _chatSub = SupabaseService.client
        .from('live_comments')
        .stream(primaryKey: ['id'])
        .eq('stream_id', sid)
        .order('created_at', ascending: true)
        .listen((data) async {
          final list = List<Map<String, dynamic>>.from(data);
          await _resolveNames(list);
          if (!mounted) return;
          setState(() { _comments..clear()..addAll(list); });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_chatScroll.hasClients) {
              _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut);
            }
          });
        }, onError: (e) {
          debugPrint('live chat stream error: $e');
          _chatRetry?.cancel();
          _chatRetry = Timer(const Duration(seconds: 2), () {
            if (mounted && _isLive && _streamId != null) _subscribeChat(_streamId!);
          });
        });
  }

  // Сэтгэгдэл бичигчдийн нэрийг profiles-оос тайлна (stream join хийдэггүй)
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

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Live дуусгах уу?',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text('Бичлэг тань feed дээр replay болж хадгалагдана.',
          style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Үгүй', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Дуусгах',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
        ]));
    if (ok == true && mounted) _endLive();
  }

  Future<void> _endLive() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);

    // 1. Recorder зогсооно (дээд тал нь 2с хүлээнэ)
    if (_recorder != null && _recorder!.state != 'inactive') {
      final c = Completer<void>();
      _recorder!.addEventListener('stop', (_) { if (!c.isCompleted) c.complete(); });
      _recorder!.stop();
      await c.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    }

    // 2. Камер, subscription-уудыг унтраана
    _stream?.getTracks().forEach((t) => t.stop());
    _chatSub?.cancel();
    _chatRetry?.cancel();
    _viewerTimer?.cancel();

    // 3. Stream дууссан гэж тэмдэглэнэ (fire & forget)
    final sid = _streamId;
    if (sid != null) _endStreamRow(sid);
    unregisterUnloadRequest('go-live');

    // 4. Бичлэгийг ард нь upload хийнэ (хүлээхгүй)
    final chunks = List<html.Blob>.from(_chunks);
    final title  = _titleCtrl.text.trim();
    if (chunks.isNotEmpty) {
      _uploadRecording(chunks, title);
    }

    // 5. "Хадгаллаа" харуулаад шууд гарна
    if (mounted) {
      // _isLive=false — dispose() давхар end update илгээхгүй
      setState(() { _saving = false; _saved = true; _isLive = false; });
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) context.go('/feed');
    }
  }

  void _uploadRecording(List<html.Blob> chunks, String title, {int attempt = 0}) {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    final blob  = html.Blob(chunks, 'video/webm');
    final ts    = DateTime.now().millisecondsSinceEpoch;
    final path  = '${user.id}/$ts.webm';
    final token = SupabaseService.client.auth.currentSession?.accessToken ?? '';

    final xhr = html.HttpRequest()
      ..open('POST', '${AppConstants.supabaseUrl}/storage/v1/object/posts/$path')
      ..setRequestHeader('Authorization', 'Bearer $token')
      ..setRequestHeader('Content-Type', 'video/webm')
      ..setRequestHeader('x-upsert', 'true');

    // Сүлжээний алдаа/timeout → 3с дараа НЭГ удаа дахин оролдоно
    void retryOnce(String reason) {
      debugPrint('Live replay upload амжилтгүй ($reason), attempt=$attempt');
      if (attempt == 0) {
        Timer(const Duration(seconds: 3),
            () => _uploadRecording(chunks, title, attempt: 1));
      }
    }

    xhr.onError.listen((_) => retryOnce('network'));
    xhr.onTimeout.listen((_) => retryOnce('timeout'));
    xhr.onLoad.listen((_) {
      final st = xhr.status ?? 0;
      if (st >= 200 && st < 300) {
        final mediaUrl = SupabaseService.client.storage
            .from('posts').getPublicUrl(path);
        _insertReplayPost(user.id, mediaUrl, title);
      } else if (st >= 500 || st == 0) {
        retryOnce('http $st');
      } else {
        // 4xx (хэт том файл г.м) — дахин оролдоод нэмэргүй
        debugPrint('Live replay upload татгалзав: http $st');
      }
    });

    xhr.send(blob);
  }

  Future<void> _insertReplayPost(String userId, String mediaUrl, String title,
      {int attempt = 0}) async {
    try {
      await SupabaseService.client.from('posts').insert({
        'user_id':   userId,
        'caption':   '🔴 Live replay: $title',
        'media_url': mediaUrl,
      });
    } catch (e) {
      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 3));
        return _insertReplayPost(userId, mediaUrl, title, attempt: 1);
      }
      debugPrint('Replay post insert алдаа: $e');
    }
  }

  Future<void> _sendComment() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty || _streamId == null) return;
    _chatCtrl.clear();
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      await SupabaseService.client.from('live_comments').insert({
        'stream_id': _streamId, 'user_id': user.id, 'text': text,
      });
    } catch (_) {
      if (mounted) {
        _chatCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Илгээж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/feed');
    }
  }

  @override
  void dispose() {
    // END дараагүй байж дэлгэцээс гарвал — live-г дуусгаж, бичлэгийг хадгална
    if (_isLive && _streamId != null) {
      try {
        if (_recorder != null && _recorder!.state != 'inactive') _recorder!.stop();
      } catch (_) {}
      if (_chunks.isNotEmpty) {
        _uploadRecording(List<html.Blob>.from(_chunks), _titleCtrl.text.trim());
      }
      _endStreamRow(_streamId!);
    }
    unregisterUnloadRequest('go-live');
    _stream?.getTracks().forEach((t) => t.stop());
    _chatSub?.cancel();
    _chatRetry?.cancel();
    _viewerTimer?.cancel();
    _titleCtrl.dispose();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final size    = MediaQuery.of(context).size;

    return PopScope(
      // Live явж байхад back → эхлээд баталгаажуулна
      canPop: !_isLive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isLive) _confirmEnd();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(fit: StackFit.expand, children: [

            // ── Camera (үргэлж модонд байлгаж, зөөлөн fade хийнэ) ──
            AnimatedOpacity(
              opacity: _cameraReady ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: HtmlElementView(viewType: _viewId)),
            if (!_cameraReady)
              Container(color: Colors.black,
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _error != null
                      ? const Icon(Icons.videocam_off_rounded, color: Colors.white30, size: 64)
                      : const _CamWarmup(),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(_error ?? 'Камер асаж байна...',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                      textAlign: TextAlign.center)),
                ]))),

            // ── Gradients ───────────────────────────────
            Positioned(top: 0, left: 0, right: 0, height: size.height * 0.25,
              child: Container(decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent])))),

            Positioned(bottom: 0, left: 0, right: 0, height: size.height * 0.45,
              child: Container(decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.95), Colors.transparent])))),

            // ── Top bar ─────────────────────────────────
            Positioned(top: 0, left: 0, right: 0,
              child: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(children: [
                  _CircleBtn(
                    icon: Icons.close,
                    onTap: _isLive ? _confirmEnd : _close),
                  const SizedBox(width: 10),
                  if (_isLive) ...[
                    const _LiveBadge(),
                    const SizedBox(width: 8),
                    _ViewerBadge(count: _viewers),
                  ],
                  const Spacer(),
                  _CircleBtn(icon: Icons.flip_camera_ios_rounded, onTap: _flipCamera),
                  const SizedBox(width: 10),
                  _ProfileChip(profile: profile),
                ])))),

            // ── Bottom panel ─────────────────────────────
            Positioned(bottom: 0, left: 0, right: 0,
              child: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: (_isLive || _saving || _saved)
                    ? _ChatPanel(
                        comments: _comments, names: _names,
                        scrollCtrl: _chatScroll,
                        ctrl: _chatCtrl, onSend: _sendComment,
                        onEnd: _confirmEnd, saving: _saving, saved: _saved)
                    : _PreLivePanel(
                        ctrl: _titleCtrl, starting: _starting,
                        error: _error, ready: _cameraReady,
                        onGo: _cameraReady ? _goLive : null)))),
          ]),
        ),
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────

/// Камер асах хүлээлт — bare spinner-ийн оронд зөөлөн лугшдаг камер тэмдэг
class _CamWarmup extends StatefulWidget {
  const _CamWarmup();
  @override State<_CamWarmup> createState() => _CamWarmupState();
}
class _CamWarmupState extends State<_CamWarmup> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) {
      final t = Curves.easeInOut.transform(_c.value);
      return Container(
        width: 78, height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentGradient,
          boxShadow: [BoxShadow(
            color: AppColors.accentStart.withValues(alpha: 0.25 + t * 0.35),
            blurRadius: 18 + t * 22, spreadRadius: t * 4)]),
        child: Transform.scale(
          scale: 0.94 + t * 0.06,
          child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 34)));
    });
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
    onTap: onTap,
    child: Container(width: 38, height: 38,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black45),
      child: Icon(icon, color: Colors.white, size: 20)));
}

class _ProfileChip extends StatelessWidget {
  final dynamic profile;
  const _ProfileChip({this.profile});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      AppAvatar(initial: profile?.initial ?? '?', imageUrl: profile?.avatarUrl, size: 22),
      const SizedBox(width: 6),
      Text(profile?.username ?? '',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    ]));
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge();
  @override State<_LiveBadge> createState() => _LiveBadgeState();
}
class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    FadeTransition(opacity: _c, child: Container(width: 8, height: 8,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red))),
    const SizedBox(width: 6),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
      child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
  ]);
}

class _ViewerBadge extends StatelessWidget {
  final int count;
  const _ViewerBadge({required this.count});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 14),
      const SizedBox(width: 4),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim, child: ScaleTransition(scale: anim, child: child)),
        child: Text('$count', key: ValueKey(count),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
    ]));
}

class _PreLivePanel extends StatelessWidget {
  final TextEditingController ctrl;
  final bool starting, ready;
  final String? error;
  final VoidCallback? onGo;
  const _PreLivePanel({required this.ctrl, required this.starting, required this.ready, this.error, this.onGo});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null)
        Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
          child: Text(error!, style: const TextStyle(color: Colors.white70, fontSize: 13))),

      Container(
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24)),
        child: TextField(controller: ctrl, style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLength: 60,
          decoration: const InputDecoration(
            hintText: 'Live гарчиг...', hintStyle: TextStyle(color: Colors.white38),
            prefixIcon: Icon(Icons.title_rounded, color: Colors.white38),
            border: InputBorder.none,
            counterStyle: TextStyle(color: Colors.white24, fontSize: 11),
            contentPadding: EdgeInsets.symmetric(vertical: 14)))),
      const SizedBox(height: 14),

      TapScale(onTap: starting ? null : onGo,
        child: AnimatedContainer(duration: const Duration(milliseconds: 200), height: 54,
          decoration: BoxDecoration(
            gradient: ready ? const LinearGradient(colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)]) : null,
            color: ready ? null : Colors.white12,
            borderRadius: BorderRadius.circular(14)),
          child: Center(child: starting
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, color: ready ? Colors.white : Colors.white30, size: 11),
                const SizedBox(width: 8),
                Text('GO LIVE', style: TextStyle(
                  color: ready ? Colors.white : Colors.white30,
                  fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 1.5)),
              ])))),
    ]);
}

class _ChatPanel extends StatelessWidget {
  final List<Map<String, dynamic>> comments;
  final Map<String, String> names;
  final ScrollController scrollCtrl;
  final TextEditingController ctrl;
  final VoidCallback onSend, onEnd;
  final bool saving;
  final bool saved;
  const _ChatPanel({required this.comments, required this.names,
    required this.scrollCtrl, required this.ctrl,
    required this.onSend, required this.onEnd,
    this.saving = false, this.saved = false});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Чат жагсаалт — дээд ирмэг нь зөөлөн уусна
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: comments.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(height: 150,
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.white],
                  stops: [0.0, 0.2]).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: comments.length,
                  itemBuilder: (_, i) {
                    final c = comments[i];
                    final userId   = c['user_id'] as String?;
                    final username = (userId != null ? names[userId] : null) ?? 'user';
                    return Padding(padding: const EdgeInsets.only(bottom: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        MouseRegion(
                          cursor: userId != null
                              ? SystemMouseCursors.click : MouseCursor.defer,
                          child: GestureDetector(
                            onTap: () { if (userId != null) context.push('/creator/$userId'); },
                            child: Text('$username ', style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)))),
                        Expanded(child: Text(c['text'] ?? '',
                          style: const TextStyle(color: Colors.white70, fontSize: 13))),
                      ]));
                  })))),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Container(height: 44,
          decoration: BoxDecoration(color: Colors.black54,
            borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white24)),
          child: TextField(controller: ctrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onSubmitted: (_) => onSend(),
            decoration: const InputDecoration(
              hintText: 'Сэтгэгдэл...', hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
              border: InputBorder.none, isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12))))),
        const SizedBox(width: 8),
        TapScale(onTap: onSend, child: Container(width: 44, height: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.accentGradient),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
        const SizedBox(width: 8),
        TapScale(onTap: (saving || saved) ? null : onEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 44, padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: saved ? Colors.green : saving ? Colors.grey : Colors.red,
              borderRadius: BorderRadius.circular(22)),
            child: Center(child: saved
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text('Хадгаллаа', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ])
              : saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('END',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))))),
      ]),
    ]);
}
