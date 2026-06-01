import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';

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
  bool _ended = false;
  bool _counted = false;

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeComments();
    _subscribeStream();
  }

  Future<void> _load() async {
    try {
      final s = await SupabaseService.client
          .from('live_streams')
          .select('id, user_id, title, viewer_count, is_live, venue_id')
          .eq('id', widget.liveId)
          .maybeSingle();
      if (s == null) { if (mounted) setState(() => _ended = true); return; }
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
          _stream = s as Map<String, dynamic>;
          _host = host as Map<String, dynamic>?;
          _venueName = venueName;
          _ended = s['is_live'] != true;
        });
      }
      // Viewer count +1 (нэг л удаа)
      if (!_counted && s['is_live'] == true) {
        _counted = true;
        SupabaseService.client.rpc('increment_viewer',
            params: {'p_stream': widget.liveId}).then((_) {}).catchError((_) {});
      }
    } catch (_) {}
  }

  void _subscribeComments() {
    _commentSub = SupabaseService.client
        .from('live_comments')
        .stream(primaryKey: ['id'])
        .eq('stream_id', widget.liveId)
        .order('created_at')
        .listen((rows) async {
          final list = (rows as List).cast<Map<String, dynamic>>();
          await _resolveNames(list);
          if (mounted) {
            setState(() => _comments = list);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              }
            });
          }
        });
  }

  void _subscribeStream() {
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
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_counted) {
      SupabaseService.client.rpc('decrement_viewer',
          params: {'p_stream': widget.liveId}).then((_) {}).catchError((_) {});
    }
    _commentSub?.cancel();
    _streamSub?.cancel();
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Видео талбай (LiveKit залгах хүртэл placeholder) ──
        Positioned.fill(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1024), Color(0xFF0A0A0F)])),
          child: Center(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              AppAvatar(imageUrl: avatarUrl, initial: initial, size: 96, showRing: true),
              const SizedBox(height: 18),
              if (_ended)
                Text('Live дууслаа', style: AppTextStyles.h2)
              else ...[
                Text(username.replaceAll('@', ''), style: AppTextStyles.h2),
                const SizedBox(height: 6),
                Text('🔴 Шууд дамжуулж байна',
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text('Видео тун удахгүй (LiveKit)',
                  style: AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary)),
              ],
            ]),
          ),
        )),

        // ── Дээд мэдээлэл ──
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
          child: Row(children: [
            IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20)),
            AppAvatar(imageUrl: avatarUrl, initial: initial, size: 34),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(username.replaceAll('@', ''),
                  style: AppTextStyles.labelLg.copyWith(color: Colors.white)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyXs.copyWith(color: Colors.white70)),
              ])),
            // LIVE badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(6)),
              child: const Text('LIVE', style: TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
            const SizedBox(width: 8),
            // Viewer count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.visibility_rounded, color: Colors.white, size: 13),
                const SizedBox(width: 3),
                Text('$viewers', style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ])),
          ]),
        )),

        // ── Доод: коммент + оруулах ──
        if (!_ended)
          Positioned(left: 0, right: 0, bottom: 0, child: SafeArea(top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Comments overlay
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: _comments.length,
                  itemBuilder: (_, i) {
                    final c = _comments[i];
                    final name = _names[c['user_id']] ?? 'User';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: RichText(text: TextSpan(
                        style: AppTextStyles.bodySm.copyWith(color: Colors.white),
                        children: [
                          TextSpan(text: '${name.replaceAll('@', '')}  ',
                            style: const TextStyle(fontWeight: FontWeight.w700,
                              color: Color(0xFFFF9500))),
                          TextSpan(text: c['text'] as String? ?? ''),
                        ])));
                  })),
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
                        horizontal: 16, vertical: 10),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none)))),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 42, height: 42,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, gradient: AppColors.accentGradient),
                      child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18))),
                ])),
            ]),
          )),

        if (_ended)
          Positioned(left: 0, right: 0, bottom: 40, child: Center(
            child: ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.bgSurface),
              child: Text('Буцах', style: AppTextStyles.btn.copyWith(
                color: AppColors.textPrimary))))),
      ]),
    );
  }
}
