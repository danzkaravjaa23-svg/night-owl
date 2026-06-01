import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/image_uploader.dart';
import '../providers/feed_provider.dart';

class CreateReelScreen extends ConsumerStatefulWidget {
  const CreateReelScreen({super.key});
  @override
  ConsumerState<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends ConsumerState<CreateReelScreen> {
  Uint8List? _bytes;
  String _ext = 'mp4';
  final _captionCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  String _contentType(String ext) => switch (ext) {
    'webm' => 'video/webm',
    'mov'  => 'video/quicktime',
    'm4v'  => 'video/x-m4v',
    _      => 'video/mp4',
  };

  Future<void> _pick() async {
    final v = await ImageUploader.pickVideo();
    if (v != null && mounted) setState(() { _bytes = v.bytes; _ext = v.ext; });
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
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() { _captionCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black, elevation: 0,
        leading: IconButton(onPressed: () => context.pop(),
          icon: const Icon(Icons.close, color: Colors.white)),
        title: Text('Шинэ Reel', style: AppTextStyles.labelLg.copyWith(color: Colors.white)),
      ),
      body: Column(children: [
        Expanded(child: Center(child: _bytes == null
          ? GestureDetector(
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
                  child: Text('Gallery-с сонгох',
                    style: AppTextStyles.btn.copyWith(color: Colors.white))),
              ]))
          : Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.movie_creation_rounded, color: Colors.white70, size: 64),
              const SizedBox(height: 12),
              Text('Видео бэлэн', style: AppTextStyles.bodyMd.copyWith(color: Colors.white70)),
              const SizedBox(height: 8),
              TextButton(onPressed: _pick,
                child: const Text('Өөр видео сонгох')),
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
              GestureDetector(
                onTap: _busy ? null : _share,
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
                        style: AppTextStyles.btn.copyWith(color: Colors.white))),
              ),
              const SizedBox(height: 8),
            ]),
          ),
      ]),
    );
  }
}
