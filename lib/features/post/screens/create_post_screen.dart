import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/router/app_router.dart' show AppRoutes;
import '../../auth/providers/auth_provider.dart';
import '../../discovery/widgets/venue_picker.dart';
import '../../feed/providers/feed_provider.dart';
import '../../map/providers/venue_story_activity_provider.dart';
import '../utils/post_media.dart';
import '../services/content_publication.dart';

const int _maxImages = 10;
// Файлын дээд хэмжээ — placeholder дээр амласантай нийцнэ
const int _maxVideoBytes = 50 * 1024 * 1024; // Storage bucket limit
const int _maxImageBytes = 25 * 1024 * 1024; // 25MB

class CreatePostScreen extends ConsumerStatefulWidget {
  final ContentPublicationService? publicationService;
  final Future<List<PickedMediaFile>> Function({bool multiple})? mediaPicker;
  final VenueCatalogLoader? venueLoader;
  const CreatePostScreen(
      {super.key, this.publicationService, this.mediaPicker, this.venueLoader});

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final List<PickedMediaFile> _media = [];
  final PageController _pageCtrl = PageController();
  int _page = 0;

  VideoPlayerController? _videoCtrl;
  bool _videoPlaying = false;

  final _captionCtrl = TextEditingController();
  String? _venueName;
  String? _venueRef;
  String? _venueId;
  bool _loading = false;
  String? _error;
  late final ContentPublicationService _publisher;
  late final PublicationSession _session;
  bool _picking = false;
  bool _choosingVenue = false;
  bool _allowExit = false;
  Map<String, dynamic>? _pendingRow;
  double? _uploadProgress;
  int _uploadIndex = 0;

  bool get _hasMedia => _media.isNotEmpty;
  bool get _isVideoPost => _media.length == 1 && _media.first.isVideo;

  bool get _canEdit =>
      !_loading && !_picking && _pendingRow == null && _session.isCurrent;
  bool get _hasDraft =>
      _hasMedia || _captionCtrl.text.trim().isNotEmpty || _venueRef != null;

  @override
  void initState() {
    super.initState();
    _publisher = widget.publicationService ?? ContentPublicationService();
    _session = _publisher.captureSession();
    _captionCtrl.addListener(_draftChanged);
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _requestClose() async {
    if (_loading || _picking) {
      _toast('Илгээх эсвэл файл сонгох үйлдэл дуусахыг хүлээнэ үү.');
      return;
    }
    if (_hasDraft) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Нооргоос гарах уу?'),
                content: Text(_pendingRow == null
                    ? 'Сонгосон медиа, бичсэн тайлбар энэ дэлгэцээс гарахад хадгалагдахгүй.'
                    : 'Нийтлэлийн төлөв тодорхойгүй байна. Feed-ээ шалгана уу; гарснаар серверийн хүсэлт цуцлагдахгүй.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Үргэлжлүүлэх')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Гарах'))
                ],
              ));
      if (!mounted || discard != true) return;
    }
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.canPop() ? context.pop() : context.go(AppRoutes.feed);
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  // ─── Media сонгох (олон зураг эсвэл нэг видео) ───
  Future<void> _pickMedia({bool append = false}) async {
    if (!_canEdit) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await (widget.mediaPicker ?? pickPostMedia)(
          multiple: !append || !_isVideoPost);
      if (!mounted || !_session.isCurrent) {
        for (final media in picked) {
          revokePreviewUrl(media.previewUrl);
        }
        return;
      }
      if (picked.isEmpty) return;
      final acceptVideo = !append && picked.first.isVideo;
      final accepted = <PickedMediaFile>[];
      final room = acceptVideo ? 1 : _maxImages - (append ? _media.length : 0);
      for (final file in picked) {
        final supported = file.isVideo
            ? const {
                'video/mp4',
                'video/webm',
                'video/quicktime',
                'video/x-m4v'
              }.contains(file.mimeType)
            : file.mimeType.startsWith('image/');
        if (accepted.length >= room ||
            file.isVideo != acceptVideo ||
            !supported ||
            file.size <= 0 ||
            file.size > (file.isVideo ? _maxVideoBytes : _maxImageBytes)) {
          revokePreviewUrl(file.previewUrl);
        } else {
          accepted.add(file);
        }
      }
      if (accepted.isEmpty) {
        setState(() => _error =
            'Тохирох файл алга. Зураг 25MB, видео 50MB хүртэл; MP4, MOV, WebM эсвэл зураг сонгоно уу.');
        return;
      }
      // Validate replacement before releasing the existing draft.
      if (!append) {
        _videoCtrl?.dispose();
        _videoCtrl = null;
        for (final media in _media) {
          revokePreviewUrl(media.previewUrl);
        }
        _media.clear();
        _page = 0;
      }
      setState(() {
        _media.addAll(accepted);
        _uploadProgress = null;
        _videoPlaying = false;
      });
      if (accepted.length < picked.length) {
        _toast(
            'Зөвшөөрөгдсөн ${accepted.length} файл нэмлээ. Бусад файлыг төрөл, хэмжээ эсвэл тооны хязгаараар алгаслаа.');
      }
      if (acceptVideo) {
        final file = accepted.first;
        final controller = previewVideoController(file);
        try {
          await controller.initialize().timeout(const Duration(seconds: 15));
          if (mounted && _session.isCurrent && _media.contains(file)) {
            setState(() => _videoCtrl = controller);
            return;
          }
        } catch (_) {
          if (mounted && _session.isCurrent) {
            _toast('Видео урьдчилан тоглуулах боломжгүй байна.');
          }
        }
        controller.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Медиа сонгож чадсангүй. Зөвшөөрлөө шалгаад дахин оролдоно уу.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeAt(int i) {
    if (!_canEdit || i < 0 || i >= _media.length) return;
    revokePreviewUrl(_media[i].previewUrl);
    if (_media[i].isVideo) {
      _videoCtrl?.dispose();
      _videoCtrl = null;
    }
    setState(() {
      _media.removeAt(i);
      if (_page >= _media.length) {
        _page = _media.isEmpty ? 0 : _media.length - 1;
      }
    });
  }

  // ─── Хуваалцах ───
  Future<void> _post() async {
    if (_loading || _picking || _choosingVenue) return;
    if (!_session.isCurrent) {
      setState(() => _error =
          'Нэвтрэх хаяг өөрчлөгдсөн байна. Нооргийг өөр хаягаар нийтлэхгүй.');
      return;
    }
    if (_media.isEmpty) {
      setState(() => _error = 'Зураг эсвэл видео сонгоно уу');
      return;
    }
    final media = List<PickedMediaFile>.of(_media);
    final caption = _captionCtrl.text.trim();
    final venueName = _venueName;
    final venueRef = _venueRef;
    final venueId = _venueId;
    final video = _isVideoPost;
    setState(() {
      _loading = true;
      _error = null;
      _uploadProgress = 0;
      _uploadIndex = 0;
    });
    try {
      if (_pendingRow == null) {
        final id = ContentPublicationService.newId();
        final urls = <String>[];
        for (var i = 0; i < media.length; i++) {
          _session.check();
          if (!mounted) return;
          setState(() {
            _uploadIndex = i;
            _uploadProgress = 0;
          });
          final file = media[i];
          final blob = file.isVideo
              ? file.file!
              : await _publisher.preparePostImage(file);
          _session.check();
          if (!mounted) return;
          final ext =
              file.isVideo ? file.name.split('.').last.toLowerCase() : 'jpg';
          urls.add(await _publisher.uploadPost(_session, blob,
              path: '${_session.ownerId}/${id}_$i.$ext',
              contentType: file.isVideo ? file.mimeType : 'image/jpeg',
              onProgress: (progress) {
            if (mounted && _session.isCurrent) {
              setState(() => _uploadProgress = progress.clamp(0, 1));
            }
          }));
        }
        _session.check();
        if (!mounted) return;
        _pendingRow = Map.unmodifiable({
          'id': id,
          'user_id': _session.ownerId,
          'caption': caption,
          'media_url': urls.first,
          'media_urls': List<String>.unmodifiable(urls),
          'media_type': video ? 'video' : 'image',
          if (venueName != null) 'venue_name': venueName,
          if (venueRef != null) 'venue_ref': venueRef,
          if (venueId != null) 'venue_id': venueId,
        });
      }
      setState(() => _uploadProgress = null);
      await _publisher.publish(_session, 'posts', _pendingRow!);
      if (!mounted || !_session.isCurrent) return;
      ref.invalidate(feedProvider);
      ref.read(postsVersionProvider.notifier).state++;
      ref.invalidate(currentProfileProvider);
      ref.invalidate(venueStoryActivityProvider);
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _session.isCurrent) {
          context.canPop() ? context.pop() : context.go(AppRoutes.feed);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is PublicationFailure
            ? error.message
            : 'Илгээж чадсангүй. Ноорог хэвээр байна; дахин оролдоно уу.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _session.close();
    _captionCtrl.removeListener(_draftChanged);
    _captionCtrl.dispose();
    _pageCtrl.dispose();
    _videoCtrl?.dispose();
    for (final m in _media) {
      revokePreviewUrl(m.previewUrl);
    }
    super.dispose();
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _allowExit || (!_hasDraft && !_loading && !_picking),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          backgroundColor: AppColors.bgBase,
          leading: IconButton(
              tooltip: 'Хаах',
              onPressed: (_loading || _picking) ? null : _requestClose,
              icon: const Icon(Icons.close)),
          title: Text('Шинэ пост', style: AppTextStyles.h2),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: (_loading || _picking || !_hasMedia) ? null : _post,
                style: TextButton.styleFrom(
                  backgroundColor:
                      _hasMedia ? AppColors.accentStart : AppColors.bgSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_pendingRow == null ? 'Хуваалцах' : 'Дахин шалгах',
                        style: AppTextStyles.labelMd.copyWith(
                            color: _hasMedia
                                ? Colors.white
                                : AppColors.textTertiary)),
              ),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (_picking)
            const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Row(children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Expanded(child: Text('Медиа сонгож байна…'))
                ])),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: AppTextStyles.bodyXs
                            .copyWith(color: AppColors.error))),
              ]),
            ),

          // ── Media picker / carousel preview ──
          _hasMedia
              ? _buildPreview()
              : _Press(
                  scale: 0.98,
                  onTap: _canEdit ? () => _pickMedia() : null,
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
                      image: previewImageProvider(_media[i]),
                      selected: i == _page,
                      onTap: () {
                        setState(() => _page = i);
                        _pageCtrl.animateToPage(i,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut);
                      },
                      onRemove: _canEdit ? () => _removeAt(i) : null,
                    ),
                  if (_media.length < _maxImages)
                    _Press(
                      onTap: _canEdit ? () => _pickMedia(append: true) : null,
                      child: Container(
                        width: 56,
                        height: 56,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Icon(Icons.add,
                            color: AppColors.textSecondary, size: 24),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          Text('ТАЙЛБАР',
              style: AppTextStyles.labelSm.copyWith(
                  color: AppColors.textSecondary, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          TextField(
            controller: _captionCtrl,
            enabled: _canEdit,
            maxLines: 4,
            maxLength: 300,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
                hintText: 'Өнөө шөнө юу болов?...',
                counterStyle: AppTextStyles.bodyXs
                    .copyWith(color: AppColors.textTertiary)),
          ),
          const SizedBox(height: 20),

          Text('БАЙРШИЛ',
              style: AppTextStyles.labelSm.copyWith(
                  color: AppColors.textSecondary, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          _Press(
            key: const ValueKey('post-location-picker'),
            scale: 0.98,
            onTap: _canEdit && !_choosingVenue ? _showVenuePicker : null,
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
                        ? AppColors.accentStart
                        : AppColors.textSecondary,
                    size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_venueName ?? 'Байршил нэмэх (сонголтоор)',
                        style: AppTextStyles.bodyMd.copyWith(
                            color: _venueName != null
                                ? AppColors.textPrimary
                                : AppColors.textTertiary))),
                if (_venueName != null)
                  IconButton(
                      tooltip: 'Байршлыг хасах',
                      onPressed: _canEdit
                          ? () => setState(() {
                                _venueName = null;
                                _venueRef = null;
                                _venueId = null;
                              })
                          : null,
                      icon: Icon(Icons.close,
                          color: AppColors.textTertiary, size: 18))
                else
                  Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Байршилтай пост газрын хэмнэлд 7 хоног тооцогдоно. Пост болон байршил хэвээр үлдэнэ.',
            style:
                AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 40),

          GradientButton(
            label: _pendingRow != null
                ? 'Дахин шалгах'
                : _media.length > 1
                    ? 'Хуваалцах (${_media.length})'
                    : 'Хуваалцах',
            onPressed: (!_hasMedia || _loading || _picking) ? null : _post,
          ),
          const SizedBox(height: 40),
        ]),
      ));

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
                        _videoPlaying
                            ? _videoCtrl!.play()
                            : _videoCtrl!.pause();
                      });
                    },
                    child: Stack(children: [
                      SizedBox.expand(
                          child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _videoCtrl!.value.size.width,
                          height: _videoCtrl!.value.size.height,
                          child: VideoPlayer(_videoCtrl!),
                        ),
                      )),
                      if (!_videoPlaying)
                        const Center(
                            child: Icon(Icons.play_circle_fill,
                                color: Colors.white70, size: 60)),
                    ]),
                  );
                }
                return Container(
                    color: Colors.black87,
                    child: const Center(
                        child: Icon(Icons.videocam_rounded,
                            color: Colors.white54, size: 64)));
              }
              return Image(
                  image: previewImageProvider(m),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity);
            },
          ),

          // Count badge (1/3)
          if (_media.length > 1)
            Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${_page + 1}/${_media.length}',
                      style:
                          AppTextStyles.bodyXs.copyWith(color: Colors.white)),
                )),

          // Remove current
          if (_canEdit)
            Positioned(
                top: 12,
                right: 12,
                child: _Press(
                  scale: 0.85,
                  onTap: () => _removeAt(_page),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                )),

          // Dots
          if (_media.length > 1)
            Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _media.length; i++)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page
                                ? AppColors.accentStart
                                : Colors.white54),
                      ),
                  ],
                )),

          // Upload overlay
          if (_loading)
            Positioned.fill(
                child: Container(
              color: Colors.black.withValues(alpha: 0.65),
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
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
                Text(
                    _media.length > 1
                        ? 'Илгээж байна ${_uploadIndex + 1}/${_media.length}...'
                        : 'Илгээж байна...',
                    style:
                        AppTextStyles.bodyMd.copyWith(color: Colors.white70)),
              ])),
            )),
        ]),
      ),
    );
  }

  Future<void> _showVenuePicker() async {
    if (!_canEdit || _choosingVenue) return;
    _choosingVenue = true;
    try {
      final venue = await pickDiscoveryVenue(
        context,
        selectedRef: _venueRef,
        title: 'Постын байршил',
        helperText:
            'Нийтэлснээс хойш 7 хоног газрын хэмнэлд тооцогдоно. Пост болон байршил хэвээр үлдэнэ.',
        loader: widget.venueLoader,
      );
      if (venue != null && mounted && _canEdit) {
        setState(() {
          _venueName = venue['name'] as String;
          _venueRef = venue['ref'] as String;
          _venueId = venue['venue_id'] as String?;
        });
      }
    } finally {
      _choosingVenue = false;
    }
  }
}

// ─── Дарахад жижигрэх + hover cursor (веб мэдрэмж) ───
class _Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const _Press({super.key, required this.child, this.onTap, this.scale = 0.92});

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              widget.onTap == null ? null : (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _down ? widget.scale : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      );
}

// ─── Thumbnail ───
class _Thumb extends StatelessWidget {
  final ImageProvider image;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _Thumb(
      {required this.image,
      required this.selected,
      required this.onTap,
      this.onRemove});

  @override
  Widget build(BuildContext context) => _Press(
        scale: 0.9,
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppColors.accentStart : AppColors.hairline,
                width: selected ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            Image(image: image, fit: BoxFit.cover),
            if (onRemove != null)
              Positioned(
                  top: 2,
                  right: 2,
                  child: _Press(
                    scale: 0.8,
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 12),
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
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
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
          Text('Зураг 25MB · Видео 50MB хүртэл\nMP4, MOV, WebM, JPG, PNG',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary)),
        ],
      );
}
