// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../feed/providers/feed_provider.dart';

const int _maxImages = 10;

/// Сонгосон media нэгж
class _Picked {
  final html.File file;
  final String previewUrl;
  final bool isVideo;
  _Picked(this.file, this.previewUrl, this.isVideo);
}

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final List<_Picked> _media = [];
  final PageController _pageCtrl = PageController();
  int _page = 0;

  VideoPlayerController? _videoCtrl;
  bool _videoPlaying = false;

  final _captionCtrl = TextEditingController();
  String? _venueName;
  bool _loading = false;
  String? _error;
  double? _uploadProgress;
  int _uploadIndex = 0;

  bool get _hasMedia    => _media.isNotEmpty;
  bool get _isVideoPost => _media.length == 1 && _media.first.isVideo;

  // ─── Media сонгох (олон зураг эсвэл нэг видео) ───
  Future<void> _pickMedia({bool append = false}) async {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*,video/*'
      ..multiple = !append || !_isVideoPost
      ..click();

    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) return;

    final firstIsVideo = files.first.type.startsWith('video/');

    if (!append) {
      // Цэвэрлэх
      _videoCtrl?.dispose();
      _videoCtrl = null;
      for (final m in _media) {
        html.Url.revokeObjectUrl(m.previewUrl);
      }
      _media.clear();
      _page = 0;
    }

    if (firstIsVideo && !append) {
      // Нэг видеоны пост
      final f = files.first;
      final url = html.Url.createObjectUrl(f);
      _media.add(_Picked(f, url, true));
      setState(() {
        _error = null;
        _uploadProgress = null;
        _videoPlaying = false;
      });
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await ctrl.initialize();
        if (mounted) setState(() => _videoCtrl = ctrl);
      } catch (_) {}
      return;
    }

    // Зургийн carousel (видео файлуудыг алгасна)
    for (final f in files) {
      if (_media.length >= _maxImages) break;
      if (f.type.startsWith('video/')) continue;
      final url = html.Url.createObjectUrl(f);
      _media.add(_Picked(f, url, false));
    }
    setState(() {
      _error = null;
      _uploadProgress = null;
    });
  }

  void _removeAt(int i) {
    if (i < 0 || i >= _media.length) return;
    html.Url.revokeObjectUrl(_media[i].previewUrl);
    if (_media[i].isVideo) {
      _videoCtrl?.dispose();
      _videoCtrl = null;
    }
    setState(() {
      _media.removeAt(i);
      if (_page >= _media.length) _page = _media.isEmpty ? 0 : _media.length - 1;
    });
  }

  // ─── Зураг resize + JPEG compress (canvas) ───
  // 500к scale — түүхий 5–20MB зургийг ~1440px / JPEG q0.82 болгож
  // багасгана (ихэвчлэн 200–600KB). Алдаа гарвал эх файлаараа буцаана.
  Future<html.Blob> _resizeImage(html.File file,
      {int maxDim = 1440, num quality = 0.82}) async {
    final objUrl = html.Url.createObjectUrl(file);
    try {
      final img = html.ImageElement(src: objUrl);
      await img.onLoad.first;
      final w = img.naturalWidth;
      final h = img.naturalHeight;
      if (w == 0 || h == 0) return file;

      final longest = w > h ? w : h;
      final scale = longest > maxDim ? maxDim / longest : 1.0;
      final tw = (w * scale).round();
      final th = (h * scale).round();

      final canvas = html.CanvasElement(width: tw, height: th);
      final ctx = canvas.context2D;
      ctx.drawImageScaled(img, 0, 0, tw.toDouble(), th.toDouble());

      final blob = await canvas.toBlob('image/jpeg', quality);
      // Хэрэв ямар нэг шалтгаанаар томрсон бол эх файлаа хэрэглэнэ
      if (blob.size >= file.size && scale == 1.0) return file;
      return blob;
    } catch (_) {
      return file; // fallback — эх файл
    } finally {
      html.Url.revokeObjectUrl(objUrl);
    }
  }

  // ─── Streaming XHR upload ───
  Future<void> _uploadViaXhr(html.Blob blob, String path, String mime) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken
        ?? AppConstants.supabaseAnonKey;
    final url = '${AppConstants.supabaseUrl}/storage/v1/object/posts/$path';

    final completer = Completer<void>();
    final xhr = html.HttpRequest()
      ..open('POST', url)
      ..setRequestHeader('Authorization', 'Bearer $token')
      ..setRequestHeader('Content-Type', mime)
      ..setRequestHeader('x-upsert', 'true');

    xhr.upload.onProgress.listen((e) {
      if (e.lengthComputable && mounted) {
        setState(() => _uploadProgress = (e.loaded ?? 0) / (e.total ?? 1));
      }
    });
    xhr.onLoad.listen((_) {
      final s = xhr.status ?? 0;
      if (s >= 200 && s < 300) {
        completer.complete();
      } else {
        completer.completeError('Upload failed ($s): ${xhr.responseText}');
      }
    });
    xhr.onError.listen((_) =>
        completer.completeError('Network error — check Supabase Storage policies'));
    xhr.send(blob);
    await completer.future;
  }

  // ─── Хуваалцах ───
  Future<void> _post() async {
    if (_media.isEmpty) {
      setState(() => _error = 'Зураг эсвэл видео сонгоно уу');
      return;
    }
    setState(() { _loading = true; _error = null; _uploadProgress = 0; _uploadIndex = 0; });

    try {
      final user = SupabaseService.currentUser;
      if (user == null) { if (mounted) context.pop(); return; }

      final urls = <String>[];
      for (var i = 0; i < _media.length; i++) {
        final m = _media[i];
        if (mounted) setState(() { _uploadIndex = i; _uploadProgress = 0; });
        final ts = DateTime.now().millisecondsSinceEpoch;

        html.Blob blob;
        String mime;
        String ext;
        if (m.isVideo) {
          // Видеог хэвээр нь (browser-д найдвартай compress хийх боломжгүй)
          blob = m.file;
          mime = m.file.type.isNotEmpty ? m.file.type : 'video/mp4';
          ext = (m.file.name.contains('.')
              ? m.file.name.split('.').last.toLowerCase()
              : 'mp4');
        } else {
          // Зургийг resize + compress
          blob = await _resizeImage(m.file);
          mime = 'image/jpeg';
          ext = 'jpg';
        }

        final path = '${user.id}/${ts}_$i.$ext';
        await _uploadViaXhr(blob, path, mime);
        urls.add(SupabaseService.client.storage.from('posts').getPublicUrl(path));
      }

      await SupabaseService.client.from('posts').insert({
        'user_id':    user.id,
        'caption':    _captionCtrl.text.trim(),
        'media_url':  urls.first,
        'media_urls': urls,
        'media_type': _isVideoPost ? 'video' : 'image',
        if (_venueName != null) 'venue_name': _venueName,
      });

      ref.read(feedProvider.notifier).loadFeed(refresh: true);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _pageCtrl.dispose();
    _videoCtrl?.dispose();
    for (final m in _media) {
      html.Url.revokeObjectUrl(m.previewUrl);
    }
    super.dispose();
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bgBase,
    appBar: AppBar(
      backgroundColor: AppColors.bgBase,
      leading: IconButton(
        onPressed: _loading ? null : () => context.pop(),
        icon: const Icon(Icons.close)),
      title: Text('New Post', style: AppTextStyles.h2),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: (_loading || !_hasMedia) ? null : _post,
            style: TextButton.styleFrom(
              backgroundColor: _hasMedia
                  ? AppColors.accentStart : AppColors.bgSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: _loading
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('Share',
                    style: AppTextStyles.labelMd.copyWith(
                      color: _hasMedia ? Colors.white : AppColors.textTertiary)),
          ),
        ),
      ],
    ),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      if (_error != null)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!,
              style: AppTextStyles.bodyXs.copyWith(color: AppColors.error))),
          ]),
        ),

      // ── Media picker / carousel preview ──
      _hasMedia ? _buildPreview() : GestureDetector(
        onTap: _loading ? null : () => _pickMedia(),
        child: Container(
          height: 280,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: _PickerPlaceholder(),
        ),
      ),

      // ── Thumbnail strip (зургийн пост дээр) ──
      if (_hasMedia && !_isVideoPost) ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _media.length; i++)
                _Thumb(
                  url: _media[i].previewUrl,
                  selected: i == _page,
                  onTap: () {
                    setState(() => _page = i);
                    _pageCtrl.animateToPage(i,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut);
                  },
                  onRemove: _loading ? null : () => _removeAt(i),
                ),
              if (_media.length < _maxImages)
                GestureDetector(
                  onTap: _loading ? null : () => _pickMedia(append: true),
                  child: Container(
                    width: 56, height: 56,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.add,
                        color: AppColors.textSecondary, size: 24),
                  ),
                ),
            ],
          ),
        ),
      ],

      const SizedBox(height: 24),

      Text('CAPTION', style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textSecondary, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      TextField(
        controller: _captionCtrl,
        maxLines: 4,
        maxLength: 300,
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'What happened tonight?...',
          counterStyle: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textTertiary)),
      ),
      const SizedBox(height: 20),

      Text('LOCATION', style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textSecondary, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _showVenuePicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _venueName != null
                  ? AppColors.accentStart.withValues(alpha: 0.4)
                  : AppColors.hairline),
          ),
          child: Row(children: [
            Icon(Icons.location_on_outlined,
              color: _venueName != null
                  ? AppColors.accentStart : AppColors.textSecondary,
              size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _venueName ?? 'Tag a venue',
              style: AppTextStyles.bodyMd.copyWith(
                color: _venueName != null
                    ? AppColors.textPrimary : AppColors.textTertiary))),
            if (_venueName != null)
              GestureDetector(
                onTap: () => setState(() => _venueName = null),
                child: const Icon(Icons.close,
                    color: AppColors.textTertiary, size: 18))
            else
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ]),
        ),
      ),
      const SizedBox(height: 40),

      GradientButton(
        label: _media.length > 1 ? 'Хуваалцах (${_media.length})' : 'Share Post',
        onPressed: (!_hasMedia || _loading) ? null : _post,
      ),
      const SizedBox(height: 40),
    ]),
  );

  Widget _buildPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 380,
        child: Stack(children: [
          // PageView of media
          PageView.builder(
            controller: _pageCtrl,
            itemCount: _media.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final m = _media[i];
              if (m.isVideo) {
                if (_videoCtrl != null && _videoCtrl!.value.isInitialized) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _videoPlaying = !_videoPlaying;
                        _videoPlaying ? _videoCtrl!.play() : _videoCtrl!.pause();
                      });
                    },
                    child: Stack(children: [
                      SizedBox.expand(child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoCtrl!.value.size.width,
                          height: _videoCtrl!.value.size.height,
                          child: VideoPlayer(_videoCtrl!),
                        ),
                      )),
                      if (!_videoPlaying)
                        const Center(child: Icon(Icons.play_circle_fill,
                            color: Colors.white70, size: 60)),
                    ]),
                  );
                }
                return Container(color: Colors.black87, child: const Center(
                  child: Icon(Icons.videocam_rounded, color: Colors.white54, size: 64)));
              }
              return Image.network(m.previewUrl,
                fit: BoxFit.cover, width: double.infinity, height: double.infinity);
            },
          ),

          // Count badge (1/3)
          if (_media.length > 1)
            Positioned(top: 12, left: 12, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Text('${_page + 1}/${_media.length}',
                style: AppTextStyles.bodyXs.copyWith(color: Colors.white)),
            )),

          // Remove current
          if (!_loading)
            Positioned(top: 12, right: 12, child: GestureDetector(
              onTap: () => _removeAt(_page),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            )),

          // Dots
          if (_media.length > 1)
            Positioned(bottom: 12, left: 0, right: 0, child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _media.length; i++)
                  Container(
                    width: 7, height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? AppColors.accentStart : Colors.white54),
                  ),
              ],
            )),

          // Upload overlay
          if (_loading)
            Positioned.fill(child: Container(
              color: Colors.black.withValues(alpha: 0.65),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 72, height: 72, child: CircularProgressIndicator(
                  value: _uploadProgress,
                  color: AppColors.accentStart,
                  backgroundColor: Colors.white24,
                  strokeWidth: 4,
                )),
                const SizedBox(height: 16),
                if (_uploadProgress != null)
                  Text('${((_uploadProgress ?? 0) * 100).toStringAsFixed(0)}%',
                    style: AppTextStyles.h2.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(_media.length > 1
                  ? 'Uploading ${_uploadIndex + 1}/${_media.length}...'
                  : 'Uploading...',
                  style: AppTextStyles.bodyMd.copyWith(color: Colors.white70)),
              ])),
            )),
        ]),
      ),
    );
  }

  void _showVenuePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _VenuePicker(
        onSelect: (name) => setState(() => _venueName = name),
      ),
    );
  }
}

// ─── Thumbnail ───
class _Thumb extends StatelessWidget {
  final String url;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _Thumb({required this.url, required this.selected,
    required this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 56, height: 56,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? AppColors.accentStart : AppColors.hairline,
          width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        Image.network(url, fit: BoxFit.cover),
        if (onRemove != null)
          Positioned(top: 2, right: 2, child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, color: Colors.white, size: 12),
            ),
          )),
      ]),
    ),
  );
}

// ─── Picker placeholder ───
class _PickerPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.accentGradientSoft,
        ),
        child: const Icon(Icons.perm_media_outlined,
            color: AppColors.accentStart, size: 38),
      ),
      const SizedBox(height: 16),
      Text('Зураг (10 хүртэл) эсвэл видео сонгох',
          style: AppTextStyles.labelLg, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text('Up to 500MB  ·  MP4, MOV, JPG, PNG',
          style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textTertiary)),
    ],
  );
}

// ─── Venue picker bottom sheet with search ───
class _VenuePicker extends StatefulWidget {
  final ValueChanged<String> onSelect;
  const _VenuePicker({required this.onSelect});

  @override
  State<_VenuePicker> createState() => _VenuePickerState();
}

class _VenuePickerState extends State<_VenuePicker> {
  String _q = '';

  static const _emoji = {
    'bar': '🍺', 'lounge': '🛋️', 'nightclub': '🎵',
    'pub': '🍻', 'rooftop': '🌃',
  };

  List<Map<String, dynamic>> get _filtered => _q.isEmpty
      ? AppConstants.ubVenues
      : AppConstants.ubVenues.where((v) =>
          (v['name'] as String).toLowerCase().contains(_q.toLowerCase()) ||
          (v['district'] as String).toLowerCase().contains(_q.toLowerCase()) ||
          (v['type'] as String).toLowerCase().contains(_q.toLowerCase()),
        ).toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.hairline,
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text('Tag a Venue', style: AppTextStyles.h2),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
              padding: EdgeInsets.zero,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(children: [
              const SizedBox(width: 12),
              const Icon(Icons.search, color: AppColors.textTertiary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search venues...',
                    hintStyle: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textTertiary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppColors.hairline),
        Expanded(
          child: _filtered.isEmpty
              ? Center(child: Text('No venues found',
                  style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textTertiary)))
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final v = _filtered[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      leading: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(
                          _emoji[v['type']] ?? '📍',
                          style: const TextStyle(fontSize: 22))),
                      ),
                      title: Text(v['name']!, style: AppTextStyles.labelMd),
                      subtitle: Text(
                        '${v['district']} · ${v['type']}',
                        style: AppTextStyles.bodyXs.copyWith(
                            color: AppColors.textSecondary)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.textTertiary, size: 18),
                      onTap: () {
                        widget.onSelect(v['name']!);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
