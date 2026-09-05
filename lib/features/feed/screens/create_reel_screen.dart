import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/image_uploader.dart';
import '../providers/feed_provider.dart';
import '../widgets/story_video.dart';
import '../../map/providers/venue_provider.dart' show isVenueOwnerProvider;

class CreateReelScreen extends ConsumerStatefulWidget {
  const CreateReelScreen({super.key});
  @override
  ConsumerState<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends ConsumerState<CreateReelScreen> {
  Uint8List? _bytes;
  String _ext = 'mp4';
  String? _previewUrl;   // blob URL — сонгосон видеог урьдчилан харах
  final _captionCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  String _contentType(String ext) => switch (ext) {
    'webm' => 'video/webm',
    'mov'  => 'video/quicktime',
    'm4v'  => 'video/x-m4v',
    _      => 'video/mp4',
  };

  // Preview blob URL-ыг цэвэрлэнэ
  void _clearPreview() {
    if (_previewUrl != null) { revokeBlobUrl(_previewUrl!); _previewUrl = null; }
  }

  Future<void> _pick() async {
    final v = await ImageUploader.pickVideo();
    if (v != null && mounted) {
      setState(() {
        _clearPreview();
        _bytes = v.bytes; _ext = v.ext;
        // Веб дээр сонгосон клипээ шууд харна (буруу файл сонгосныг илрүүлнэ)
        _previewUrl = createBlobUrl(v.bytes, _contentType(v.ext));
      });
    }
  }

  Future<void> _share() async {
    if (_bytes == null || _busy) return;
    final user = SupabaseService.currentUser;
    if (user == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = await ImageUploader.uploadBytes(
        bytes: _bytes!,
        bucket: 'posts',
        path: '${user.id}/$ts.$_ext',
        contentType: _contentType(_ext),
      );
      // Том видео upload удаан — энэ хооронд дэлгэц хаагдвал setState хийхгүй
      if (!mounted) return;
      if (url == null) {
        setState(() { _busy = false; _error = 'Видео upload амжилтгүй (хэмжээ 50MB-аас бага байх ёстой)'; });
        return;
      }
      await SupabaseService.client.from('posts').insert({
        'user_id': user.id,
        'caption': _captionCtrl.text.trim(),
        'media_url': url,
        'media_type': 'video',
      });
      if (!mounted) return;
      ref.read(feedProvider.notifier).loadFeed(refresh: true);
      context.go('/reels');
    } catch (_) {
      // Supabase/Postgres-ийн англи алдааг харуулахгүй — Монгол мессеж
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Алдаа гарлаа. Дахин оролдоно уу.';
        });
      }
    }
  }

  @override
  void dispose() { _clearPreview(); _captionCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isOwner = ref.watch(isVenueOwnerProvider).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0,
        leading: IconButton(onPressed: () => context.pop(),
          icon: const Icon(Icons.close, color: Colors.white)),
        title: Text('Шинэ Discovery', style: AppTextStyles.labelLg.copyWith(color: Colors.white)),
      ),
      body: isOwner == null
          // Эрх шалгаж дуустал л loader — эзэн биш хэрэглэгчид create UI гарахгүй
          ? const Center(child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2))
          : isOwner == false
          ? Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.storefront_outlined, color: Colors.white38, size: 64),
                const SizedBox(height: 16),
                Text('Зөвхөн venue эзэд', style: AppTextStyles.h2.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Text('Discovery контентыг зөвхөн газрын эзэд оруулна. '
                    'Та эхлээд газраа бүртгүүлнэ үү.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd.copyWith(color: Colors.white54)),
              ])))
          : Column(children: [
        Expanded(child: Center(child: _bytes == null
          ? _Pressable(
              onTap: _pick,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.slow_motion_video_outlined,
                    color: Colors.white38, size: 72),
                const SizedBox(height: 16),
                Text('Видео сонгох', style: AppTextStyles.bodyMd.copyWith(color: Colors.white54)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(14)),
                  child: Text('Зургийн сангаас сонгох',
                    style: AppTextStyles.btn.copyWith(color: Colors.white))),
              ]))
          // Сонгосон клипээ шууд харна — muted/loop preview
          : Stack(alignment: Alignment.bottomCenter, children: [
              _previewUrl != null
                ? Positioned.fill(child: StoryVideoView(
                    url: _previewUrl!, loop: true))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.movie_creation_rounded,
                        color: Colors.white70, size: 64),
                    const SizedBox(height: 12),
                    Text('Видео бэлэн',
                        style: AppTextStyles.bodyMd.copyWith(color: Colors.white70)),
                  ]),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _Pressable(
                  onTap: _pick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24)),
                    child: Text('Өөр видео сонгох',
                      style: AppTextStyles.bodySm.copyWith(color: Colors.white)))),
              ),
            ]))),
        if (_bytes != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: AppColors.bgElevated,
            child: Column(children: [
              TextField(
                controller: _captionCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Тайлбар бичих...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true, fillColor: Colors.white10, isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppTextStyles.bodyXs.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: 10),
              _Pressable(
                onTap: _busy ? null : _share,
                child: AnimatedOpacity(
                  opacity: _busy ? 0.75 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    height: 50, width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: AppColors.accentGradient,
                      borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: _busy
                      ? const SizedBox(width: 22, height: 22, child:
                          CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Reel хуваалцах',
                          style: AppTextStyles.btn.copyWith(color: Colors.white)))),
              ),
              const SizedBox(height: 8),
            ]),
          ),
      ]),
    );
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
          scale: _down ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child),
      ),
    );
  }
}
