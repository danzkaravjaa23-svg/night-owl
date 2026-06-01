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

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  html.File? _htmlFile;
  String? _previewUrl;
  bool _isVideo = false;
  String? _fileName;
  double? _uploadProgress;

  VideoPlayerController? _videoCtrl;
  bool _videoPlaying = false;

  final _captionCtrl = TextEditingController();
  String? _venueId;
  String? _venueName;
  bool _loading = false;
  String? _error;

  // ─── Pick image OR video via native file input ───
  Future<void> _pickMedia() async {
    final input = html.FileUploadInputElement()
      ..accept = 'image/*,video/*'
      ..click();

    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;

    final file = input.files!.first;
    final isVid = file.type.startsWith('video/');

    // Cleanup previous
    _videoCtrl?.dispose();
    _videoCtrl = null;
    if (_previewUrl != null) html.Url.revokeObjectUrl(_previewUrl!);

    final objectUrl = html.Url.createObjectUrl(file);

    setState(() {
      _htmlFile = file;
      _fileName = file.name;
      _previewUrl = objectUrl;
      _isVideo = isVid;
      _error = null;
      _uploadProgress = null;
      _videoPlaying = false;
    });

    if (isVid) {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(objectUrl));
      try {
        await ctrl.initialize();
        if (mounted) setState(() => _videoCtrl = ctrl);
      } catch (_) {
        // Preview init failed — still allow upload
      }
    }
  }

  // ─── Streaming XHR upload — works for 500MB without loading into RAM ───
  Future<void> _uploadViaXhr(html.File file, String path) async {
    final token = SupabaseService.client.auth.currentSession?.accessToken
        ?? AppConstants.supabaseAnonKey;
    final url = '${AppConstants.supabaseUrl}/storage/v1/object/posts/$path';

    final mime = file.type.isNotEmpty ? file.type : 'application/octet-stream';

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

    xhr.send(file);
    await completer.future;
  }

  // ─── Share ───
  Future<void> _post() async {
    if (_htmlFile == null) {
      setState(() => _error = 'Please select a photo or video first');
      return;
    }
    setState(() { _loading = true; _error = null; _uploadProgress = 0; });

    try {
      final user = SupabaseService.currentUser;
      if (user == null) { if (mounted) context.pop(); return; }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = (_fileName?.split('.').last.toLowerCase()) ??
          (_isVideo ? 'mp4' : 'jpg');
      final path = '${user.id}/$ts.$ext';

      await _uploadViaXhr(_htmlFile!, path);

      final mediaUrl = SupabaseService.client.storage
          .from('posts').getPublicUrl(path);

      await SupabaseService.client.from('posts').insert({
        'user_id':    user.id,
        'caption':    _captionCtrl.text.trim(),
        'media_url':  mediaUrl,
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
    _videoCtrl?.dispose();
    if (_previewUrl != null) html.Url.revokeObjectUrl(_previewUrl!);
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
            onPressed: (_loading || _htmlFile == null) ? null : _post,
            style: TextButton.styleFrom(
              backgroundColor: _htmlFile != null
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
                      color: _htmlFile != null
                          ? Colors.white : AppColors.textTertiary)),
          ),
        ),
      ],
    ),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      // Error banner
      if (_error != null)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withOpacity(0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!,
              style: AppTextStyles.bodyXs.copyWith(color: AppColors.error))),
          ]),
        ),

      // Media picker tile
      GestureDetector(
        onTap: _loading ? null : _pickMedia,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _htmlFile != null ? 380 : 280,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _htmlFile != null
                  ? AppColors.accentStart.withOpacity(0.4)
                  : AppColors.hairline,
              width: _htmlFile != null ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: _htmlFile != null
              ? _MediaPreview(
                  previewUrl: _previewUrl!,
                  isVideo: _isVideo,
                  videoCtrl: _videoCtrl,
                  videoPlaying: _videoPlaying,
                  fileName: _fileName ?? '',
                  fileSize: _htmlFile!.size,
                  loading: _loading,
                  uploadProgress: _uploadProgress,
                  onTogglePlay: () {
                    if (_videoCtrl == null) return;
                    setState(() {
                      _videoPlaying = !_videoPlaying;
                      _videoPlaying
                          ? _videoCtrl!.play()
                          : _videoCtrl!.pause();
                    });
                  },
                  onChange: _pickMedia,
                )
              : _PickerPlaceholder(),
        ),
      ),

      const SizedBox(height: 24),

      // Caption
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

      // Venue
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
              color: _venueId != null
                  ? AppColors.accentStart.withOpacity(0.4)
                  : AppColors.hairline),
          ),
          child: Row(children: [
            Icon(Icons.location_on_outlined,
              color: _venueId != null
                  ? AppColors.accentStart : AppColors.textSecondary,
              size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _venueName ?? 'Tag a venue',
              style: AppTextStyles.bodyMd.copyWith(
                color: _venueName != null
                    ? AppColors.textPrimary : AppColors.textTertiary))),
            if (_venueId != null)
              GestureDetector(
                onTap: () => setState(
                    () { _venueId = null; _venueName = null; }),
                child: const Icon(Icons.close,
                    color: AppColors.textTertiary, size: 18))
            else
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ]),
        ),
      ),
      const SizedBox(height: 40),

      GradientButton(
        label: 'Share Post',
        onPressed: (_htmlFile == null || _loading) ? null : _post,
      ),
      const SizedBox(height: 40),
    ]),
  );

  void _showVenuePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _VenuePicker(
        onSelect: (name) {
          setState(() { _venueId = name; _venueName = name; });
        },
      ),
    );
  }
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
      Text('Tap to select photo or video',
          style: AppTextStyles.labelLg),
      const SizedBox(height: 6),
      Text('Up to 500MB  ·  MP4, MOV, JPG, PNG',
          style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textTertiary)),
    ],
  );
}

// ─── Media preview (image or video) ───
class _MediaPreview extends StatelessWidget {
  final String previewUrl;
  final bool isVideo;
  final VideoPlayerController? videoCtrl;
  final bool videoPlaying;
  final String fileName;
  final int fileSize;
  final bool loading;
  final double? uploadProgress;
  final VoidCallback onTogglePlay;
  final VoidCallback onChange;

  const _MediaPreview({
    required this.previewUrl,
    required this.isVideo,
    required this.videoCtrl,
    required this.videoPlaying,
    required this.fileName,
    required this.fileSize,
    required this.loading,
    required this.uploadProgress,
    required this.onTogglePlay,
    required this.onChange,
  });

  String _fmt(int bytes) {
    if (bytes < 1 << 20) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1 << 30) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
    // Content
    if (isVideo && videoCtrl != null && videoCtrl!.value.isInitialized)
      SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: videoCtrl!.value.size.width,
            height: videoCtrl!.value.size.height,
            child: VideoPlayer(videoCtrl!),
          ),
        ),
      )
    else if (isVideo)
      Container(
        color: Colors.black87,
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_rounded, color: Colors.white54, size: 64),
          const SizedBox(height: 12),
          Text(fileName,
            style: AppTextStyles.bodyMd.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        ])),
      )
    else
      Image.network(previewUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity),

    // Video play/pause overlay
    if (isVideo && !loading)
      Positioned.fill(
        child: GestureDetector(
          onTap: onTogglePlay,
          child: AnimatedOpacity(
            opacity: videoPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Container(
                width: 60, height: 60,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.black54),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 36),
              ),
            ),
          ),
        ),
      ),

    // Upload progress overlay
    if (loading)
      Positioned.fill(
        child: Container(
          color: Colors.black.withOpacity(0.65),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 72, height: 72,
              child: CircularProgressIndicator(
                value: uploadProgress,
                color: AppColors.accentStart,
                backgroundColor: Colors.white24,
                strokeWidth: 4,
              ),
            ),
            const SizedBox(height: 16),
            if (uploadProgress != null)
              Text('${((uploadProgress ?? 0) * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.h2.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text('Uploading${isVideo ? ' video' : ''}...',
              style: AppTextStyles.bodyMd.copyWith(color: Colors.white70)),
          ])),
        ),
      ),

    // Change button
    if (!loading)
      Positioned(
        top: 12, right: 12,
        child: GestureDetector(
          onTap: onChange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.edit_rounded, color: Colors.white, size: 13),
              const SizedBox(width: 4),
              Text('Change',
                  style: AppTextStyles.bodyXs.copyWith(color: Colors.white)),
            ]),
          ),
        ),
      ),

    // File info badge
    Positioned(
      bottom: 12, left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isVideo ? Icons.videocam_rounded : Icons.image_rounded,
              color: Colors.white70, size: 13),
          const SizedBox(width: 4),
          Text(_fmt(fileSize),
              style: AppTextStyles.bodyXs.copyWith(color: Colors.white70)),
        ]),
      ),
    ),
  ]);
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

        // Search bar
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

        // Venue list
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
