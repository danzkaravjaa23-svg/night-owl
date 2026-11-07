import '../../../core/widgets/content_review_notice.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../discovery/widgets/venue_picker.dart';
import '../../map/providers/venue_story_activity_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/utils/image_uploader.dart';
import '../../../core/constants/stickers.dart';
import '../../../core/constants/story_music.dart';
import '../../../core/utils/web_audio.dart';
import '../../../core/utils/web_media_picker.dart';
import '../providers/stories_provider.dart';
import '../../post/services/content_publication.dart';
import '../widgets/story_video.dart';
import 'story_camera.dart';

const _kStoryEmojis = [
  '😀',
  '😂',
  '😍',
  '🥳',
  '😎',
  '🔥',
  '❤️',
  '✨',
  '💯',
  '🎉',
  '🍻',
  '🥂',
  '🌃',
  '🌙',
  '⭐',
  '🎶',
  '💃',
  '🕺',
  '📍',
  '👀',
  '🙌',
  '💋',
  '🤩',
  '🫶',
];

const _kTextColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFF3B7B),
  Color(0xFFFFD60A),
  Color(0xFF32D6FF),
  Color(0xFF7CFF6B),
];

// ── Үнэгүй өнгөний filter-ууд (ColorFilter.matrix) ──
class _StoryFilter {
  final String name;
  final List<double>? matrix; // null = Original (filter-гүй)
  const _StoryFilter(this.name, this.matrix);
}

const _kFilters = <_StoryFilter>[
  _StoryFilter('Original', null),
  // Хар цагаан
  _StoryFilter('Mono', [
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  // Sepia / vintage
  _StoryFilter('Vintage', [
    0.393,
    0.769,
    0.189,
    0,
    0,
    0.349,
    0.686,
    0.168,
    0,
    0,
    0.272,
    0.534,
    0.131,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  // Өнгө тодруулсан (saturation +50%)
  _StoryFilter('Vivid', [
    1.3937,
    -0.3576,
    -0.0361,
    0,
    0,
    -0.1063,
    1.1424,
    -0.0361,
    0,
    0,
    -0.1063,
    -0.3576,
    1.4639,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  // Хүйтэн / цэнхэр
  _StoryFilter('Cool', [
    0.9,
    0,
    0,
    0,
    0,
    0,
    1.0,
    0,
    0,
    0,
    0,
    0,
    1.2,
    0,
    10,
    0,
    0,
    0,
    1,
    0,
  ]),
  // Дулаан / улбар шар
  _StoryFilter('Warm', [
    1.15,
    0,
    0,
    0,
    12,
    0,
    1.0,
    0,
    0,
    4,
    0,
    0,
    0.85,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
  // Контраст ихтэй хар цагаан
  _StoryFilter('Noir', [
    0.2976,
    1.0013,
    0.1011,
    0,
    -51,
    0.2976,
    1.0013,
    0.1011,
    0,
    -51,
    0.2976,
    1.0013,
    0.1011,
    0,
    -51,
    0,
    0,
    0,
    1,
    0,
  ]),
  // Бүдэг / matte
  _StoryFilter('Fade', [
    0.8,
    0,
    0,
    0,
    28,
    0,
    0.8,
    0,
    0,
    28,
    0,
    0,
    0.8,
    0,
    40,
    0,
    0,
    0,
    1,
    0,
  ]),
  // Шөнийн нил ягаан өнгө (NightOwl)
  _StoryFilter('Night', [
    1.1,
    0,
    0.1,
    0,
    0,
    0,
    0.92,
    0.06,
    0,
    0,
    0.12,
    0,
    1.18,
    0,
    14,
    0,
    0,
    0,
    1,
    0,
  ]),
];

// Зурсан зураасны нэг шугам (өнгө + цэгүүд)
class _Stroke {
  final Color color;
  final double width;
  final List<Offset> points;
  _Stroke(this.color, this.width) : points = [];
}

class _DrawPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _DrawPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      if (s.points.length == 1) {
        canvas.drawPoints(ui.PointMode.points, s.points, paint);
        continue;
      }
      for (var i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_DrawPainter old) => true;
}

class CreateStoryScreen extends ConsumerStatefulWidget {
  final ContentPublicationService? publicationService;
  final Future<Uint8List?> Function()? imagePicker;
  final VenueCatalogLoader? venueLoader;
  const CreateStoryScreen(
      {super.key, this.publicationService, this.imagePicker, this.venueLoader});
  @override
  ConsumerState<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends ConsumerState<CreateStoryScreen> {
  Uint8List? _bytes;
  bool _isVideo = false;
  String _videoExt = 'mp4';
  String? _videoPreviewUrl; // blob URL — сонгосон видеог урьдчилан харах
  int _videoDurationSecs = 5; // видеоны бодит урт (metadata-аас)

  // Текст overlay
  String _text = '';
  Offset? _textPos;
  int _font = 0;
  int _color = 0;

  // Өнгөний filter
  int _filter = 0;
  bool _filterBar = false;

  String? _venueId;
  String? _venueRef;
  String? _venueName;
  bool _choosingVenue = false;
  final List<Map<String, dynamic>> _mentions = [];
  late final ContentPublicationService _publisher;
  late final PublicationSession _session;
  bool _picking = false;
  bool _allowExit = false;
  Map<String, dynamic>? _pendingRow;
  String _progressLabel = 'Медиа бэлдэж байна…';
  bool _busy = false;
  String? _error;

  // Хөгжим
  String? _songTitle;
  String? _songArtist;
  String? _songUrl;
  Offset? _songPos;
  final WebAudio _previewPlayer = WebAudio();

  // Зураас (draw)
  bool _drawMode = false;
  int _drawColor = 2; // pink
  final List<_Stroke> _strokes = [];

  final _boundaryKey = GlobalKey();

  bool get _canEdit =>
      !_busy && !_picking && _pendingRow == null && _session.isCurrent;

  @override
  void initState() {
    super.initState();
    _publisher = widget.publicationService ?? ContentPublicationService();
    _session = _publisher.captureSession();
  }

  Future<void> _requestClose() async {
    if (_busy || _picking) return;
    if (_bytes != null) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Нооргоос гарах уу?'),
                content: Text(_pendingRow == null
                    ? 'Сонгосон медиа болон засварууд энэ дэлгэцээс гарахад хадгалагдахгүй.'
                    : 'Нийтлэлийн төлөв тодорхойгүй байна. Story-гаа шалгана уу; гарах нь серверийн хүсэлтийг цуцлахгүй.'),
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
      if (mounted) context.canPop() ? context.pop() : context.go('/feed');
    });
  }

  Future<void> _acceptImage(Uint8List? bytes) async {
    if (bytes == null || !mounted || !_session.isCurrent) return;
    if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
      throw const PublicationFailure('Зураг хоосон эсвэл 25MB-ээс том байна.');
    }
    final codec = await ui
        .instantiateImageCodec(bytes, targetWidth: 32)
        .timeout(const Duration(seconds: 10));
    codec.dispose();
    if (!mounted || !_session.isCurrent) return;
    setState(() {
      _bytes = bytes;
      _isVideo = false;
      _error = null;
      _clearVideoPreview();
    });
  }

  @override
  void dispose() {
    _session.close();
    _previewPlayer.dispose();
    if (_videoPreviewUrl != null) revokeBlobUrl(_videoPreviewUrl!);
    super.dispose();
  }

  // Видеоны preview blob URL-ыг цэвэрлэнэ
  void _clearVideoPreview() {
    if (_videoPreviewUrl != null) {
      revokeBlobUrl(_videoPreviewUrl!);
      _videoPreviewUrl = null;
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2)));

  // ── Медиа сонгох ──
  Future<void> _pickGallery() async {
    if (!_canEdit) return;
    setState(() => _picking = true);
    try {
      final bytes = widget.imagePicker != null
          ? await widget.imagePicker!()
          : kIsWeb
              ? await pickImageBytes()
              : await ImageUploader.pickBytesFromGallery();
      await _acceptImage(bytes);
    } catch (error) {
      if (mounted) {
        _toast(error is PublicationFailure
            ? error.message
            : 'Зураг уншиж чадсангүй. Өөр зураг сонгоно уу.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _openCamera() async {
    if (!_canEdit) return;
    setState(() => _picking = true);
    try {
      final result = await openStoryCamera(context);
      if (!mounted || !_session.isCurrent) return;
      if (result.bytes != null) {
        await _acceptImage(result.bytes);
        return;
      }
      if (!result.unsupported) return;
      final bytes = kIsWeb
          ? await pickCameraPhoto()
          : await ImageUploader.pickBytesFromCamera();
      await _acceptImage(bytes);
    } catch (_) {
      if (mounted) {
        _toast('Камер нээж, зураг уншиж чадсангүй. Зөвшөөрлөө шалгана уу.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickVideo() async {
    if (!_canEdit) return;
    setState(() => _picking = true);
    try {
      final video =
          kIsWeb ? await pickVideoBytes() : await ImageUploader.pickVideo();
      if (video == null || !mounted || !_session.isCurrent) return;
      if (video.bytes.isEmpty ||
          video.bytes.length > 50 * 1024 * 1024 ||
          !const {'mp4', 'mov', 'm4v', 'webm'}
              .contains(video.ext.toLowerCase())) {
        throw const PublicationFailure(
            '50MB хүртэл MP4, MOV эсвэл WebM видео сонгоно уу.');
      }
      final mime = _videoContentType(video.ext.toLowerCase());
      final seconds = await videoDurationOf(video.bytes, mime);
      if (!mounted || !_session.isCurrent) return;
      if (seconds == null ||
          !seconds.isFinite ||
          seconds <= 0 ||
          seconds > 60) {
        throw const PublicationFailure(
            'Видео тоглуулах боломжгүй эсвэл 60 секундээс урт байна. Богино видео сонгоно уу.');
      }
      setState(() {
        _clearVideoPreview();
        _error = null;
        _bytes = video.bytes;
        _isVideo = true;
        _videoExt = video.ext.toLowerCase();
        _videoDurationSecs = seconds.ceil();
        _videoPreviewUrl = createBlobUrl(video.bytes, mime);
      });
    } on VideoTooLargeException catch (error) {
      if (mounted) {
        _toast('Видео хэт том байна (дээд тал нь ${error.limitMb} MB)');
      }
    } catch (error) {
      if (mounted) {
        _toast(error is PublicationFailure
            ? error.message
            : 'Видео сонгоход алдаа гарлаа.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // Сонгосон filter-ийг widget дээр хэрэглэнэ (idx 0 = Original)
  Widget _filtered(int idx, Widget child) {
    final m = _kFilters[idx].matrix;
    if (m == null) return child;
    return ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
  }

  TextStyle _textStyle(double size) {
    final c = _kTextColors[_color];
    switch (_font) {
      case 1:
        return GoogleFonts.playfairDisplay(
            fontSize: size, color: c, fontWeight: FontWeight.w700);
      case 2:
        return GoogleFonts.pacifico(fontSize: size * 0.92, color: c);
      case 3:
        return GoogleFonts.bebasNeue(
                fontSize: size * 1.15, color: c, letterSpacing: 1.5)
            .copyWith(fontFamilyFallback: [
          GoogleFonts.inter(fontWeight: FontWeight.w700).fontFamily!
        ]);
      default:
        return GoogleFonts.manrope(
            fontSize: size, color: c, fontWeight: FontWeight.w800);
    }
  }

  Future<void> _editText() async {
    if (!_canEdit) return;
    final ctrl = TextEditingController(text: _text);
    // Диалог/sheet нь энгийн UI гадаргуу — theme-ийг дагана
    // (зөвхөн story канвас өөрөө үргэлж харанхуй)
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Текст', style: AppTextStyles.labelLg),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
              hintText: 'Текст бичих...',
              hintStyle: TextStyle(color: AppColors.textTertiary)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Болих')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Болсон')),
        ],
      ),
    );
    if (res != null && mounted && _canEdit) setState(() => _text = res);
  }

  Future<void> _pickSticker() async {
    if (!_canEdit) return;
    final e = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🦉 Owl stickers',
                        style: AppTextStyles.labelMd
                            .copyWith(color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in kOwlStickers)
                        GestureDetector(
                            onTap: () => Navigator.pop(context, s),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                    gradient: AppColors.accentGradient,
                                    borderRadius: BorderRadius.circular(16)),
                                child: Text(s,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)))),
                    ]),
                    const SizedBox(height: 18),
                    Text('Emoji',
                        style: AppTextStyles.labelMd
                            .copyWith(color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: _kStoryEmojis
                            .map((s) => GestureDetector(
                                onTap: () => Navigator.pop(context, s),
                                child: Text(s,
                                    style: const TextStyle(fontSize: 34))))
                            .toList()),
                    const SizedBox(height: 12),
                  ]))),
    );
    if (e != null && mounted && _canEdit) {
      setState(() => _text = isOwlSticker(e) ? e : '$_text$e');
    }
  }

  Future<void> _pickVenue() async {
    if (!_canEdit || _choosingVenue) return;
    _choosingVenue = true;
    try {
      final v = await pickDiscoveryVenue(context,
          selectedRef: _venueRef,
          title: 'Story-гийн байршил',
          helperText:
              'Байршил нэмбэл энэ story газрын зураг дээрх өнөөдрийн идэвхэд тооцогдоно. Story-гийн нууцлал хэвээр үлдэнэ.',
          loader: widget.venueLoader);
      if (v != null && mounted && _canEdit) {
        setState(() {
          _venueId = v['venue_id'] as String?;
          _venueRef = v['ref'] as String;
          _venueName = v['name'] as String;
        });
      }
    } finally {
      _choosingVenue = false;
    }
  }

  Future<void> _pickMentions() async {
    if (!_canEdit) return;
    final u = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _PickerSheet(mode: _PickerMode.user),
    );
    if (u != null &&
        mounted &&
        _canEdit &&
        !_mentions.any((m) => m['id'] == u['id'])) {
      setState(() => _mentions.add(u));
    }
  }

  // Хөгжмийн цуглуулга — дуу сонгох
  Future<void> _musicSheet() async {
    if (!_canEdit) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: AppColors.hairline2,
                            borderRadius: BorderRadius.circular(2))),
                    Row(children: [
                      const Text('🎵 ', style: TextStyle(fontSize: 18)),
                      Text('Хөгжим',
                          style: AppTextStyles.labelLg
                              .copyWith(color: AppColors.textPrimary)),
                      const Spacer(),
                      if (_songTitle != null)
                        GestureDetector(
                            onTap: () => Navigator.pop(context, -1),
                            child: Text('Хасах',
                                style: AppTextStyles.bodySm
                                    .copyWith(color: AppColors.error))),
                    ]),
                    const SizedBox(height: 8),
                    if (kStorySongs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Хөгжмийн сан бэлтгэгдэж байна. Одоогоор зураг эсвэл өөрийн дуу оруулсан видеогоор story хуваалцаарай.',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.5),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: kStorySongs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final s = kStorySongs[i];
                          final sel = _songUrl == s.url;
                          return GestureDetector(
                            onTap: () {
                              _previewSong(s); // даруй сонсгоно
                              Navigator.pop(context, i); // сонгоод хаана
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                  color: sel
                                      ? AppColors.accentStart
                                          .withValues(alpha: 0.18)
                                      : AppColors.bgSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: sel
                                          ? AppColors.accentStart
                                          : AppColors.hairline)),
                              child: Row(children: [
                                Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                        gradient: AppColors.accentGradient,
                                        borderRadius: BorderRadius.circular(8)),
                                    child: const Icon(Icons.play_arrow_rounded,
                                        color: Colors.white, size: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(s.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodyMd.copyWith(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w600)),
                                      Text(s.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.bodyXs.copyWith(
                                              color: AppColors.textSecondary)),
                                    ])),
                                if (sel)
                                  const Icon(Icons.check_circle,
                                      color: AppColors.accentStart, size: 20),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ]))),
    );
    if (picked == null || !mounted || !_canEdit) return;
    if (picked < 0) {
      _previewPlayer.stop();
      setState(() {
        _songTitle = null;
        _songArtist = null;
        _songUrl = null;
        _songPos = null;
      });
    }
    // picked >= 0 үед сонголт _previewSong дотор хийгдсэн
  }

  // Сонгосон дууг давталттайгаар тоглуулж сонсгоно
  void _previewSong(StorySong s) {
    if (!_canEdit) return;
    _previewPlayer.play(s.url, loop: true);
    setState(() {
      _songTitle = s.title;
      _songArtist = s.artist;
      _songUrl = s.url;
    });
  }

  Future<void> _share() async {
    if (_bytes == null || _busy || _picking) return;
    if (!_session.isCurrent) {
      setState(() => _error =
          'Нэвтрэх хаяг өөрчлөгдсөн байна. Нооргийг өөр хаягаар нийтлэхгүй.');
      return;
    }
    final bytes = _bytes!;
    final video = _isVideo;
    final caption = _text.trim();
    final metadata = <String, dynamic>{
      'user_id': _session.ownerId,
      'media_type': video ? 'video' : 'image',
      'duration': video ? _videoDurationSecs : 5,
      if (_venueId != null) 'venue_id': _venueId,
      if (_venueRef != null) 'venue_ref': _venueRef,
      if (_mentions.isNotEmpty)
        'mentions':
            _mentions.map((m) => m['id'] as String).toList(growable: false),
      if (_songUrl != null) 'music_url': _songUrl,
      if (_songTitle != null) 'music_title': _songTitle,
      if (_songArtist != null) 'music_artist': _songArtist,
    };
    setState(() {
      _drawMode = false;
      _busy = true;
      _error = null;
      _progressLabel = 'Медиа бэлдэж байна…';
    });
    try {
      if (_pendingRow == null) {
        var output = bytes;
        var ext = _videoExt;
        var mime = _videoContentType(ext);
        if (!video) {
          final hasOverlay =
              caption.isNotEmpty || _strokes.isNotEmpty || _filter != 0;
          if (hasOverlay) {
            await WidgetsBinding.instance.endOfFrame;
            await GoogleFonts.pendingFonts()
                .timeout(const Duration(seconds: 10));
            _session.check();
            if (!mounted) return;
            final boundary = _boundaryKey.currentContext?.findRenderObject();
            if (boundary is! RenderRepaintBoundary) {
              throw const PublicationFailure(
                  'Засвартай зургийг бэлдэж чадсангүй. Ноорог хэвээр байна.');
            }
            final image = await boundary
                .toImage(pixelRatio: 2)
                .timeout(const Duration(seconds: 8));
            try {
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              if (data == null) {
                throw const PublicationFailure(
                    'Засвартай зургийг бэлдэж чадсангүй. Дахин оролдоно уу.');
              }
              output = data.buffer.asUint8List();
            } finally {
              image.dispose();
            }
          }
          output = await _publisher.prepareStoryImage(output);
          final type = ContentPublicationService.imageType(output);
          ext = type.ext;
          mime = type.mime;
        }
        _session.check();
        if (!mounted) return;
        setState(() => _progressLabel = 'Медиа илгээж байна…');
        final id = ContentPublicationService.newId();
        final url = await _publisher.uploadStory(_session, output,
            path: '${_session.ownerId}/$id.$ext', contentType: mime);
        _session.check();
        if (!mounted) return;
        _pendingRow = Map.unmodifiable({
          ...metadata,
          'id': id,
          'media_url': url,
          'caption': video && caption.isNotEmpty ? caption : null
        });
      }
      setState(() => _progressLabel = 'Нийтлэлийг баталгаажуулж байна…');
      final status =
          await _publisher.publish(_session, 'stories', _pendingRow!);
      if (!mounted || !_session.isCurrent) return;
      showPublicationFeedback(context, SavedContentKind.story, status);
      _previewPlayer.stop();
      ref.invalidate(storiesProvider);
      ref.invalidate(venueStoryActivityProvider);
      setState(() => _allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _session.isCurrent) {
          context.canPop() ? context.pop() : context.go('/feed');
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is PublicationFailure
            ? error.message
            : 'Нийтэлж чадсангүй. Засварууд хэвээр байна; дахин оролдоно уу.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _videoContentType(String ext) => switch (ext) {
        'webm' => 'video/webm',
        'mov' => 'video/quicktime',
        'm4v' => 'video/x-m4v',
        _ => 'video/mp4',
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowExit || (_bytes == null && !_busy && !_picking),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: AbsorbPointer(
          absorbing: _busy || _picking,
          child: _bytes == null ? _pickerScreen() : _editorScreen()),
    );
  }

  Widget _editorScreen() {
    final hasText = _text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // ── Preview ──
        if (_isVideo)
          _videoPreviewUrl != null
              // Сонгосон видеог шууд урьдчилан харуулна (muted, loop)
              ? Positioned.fill(
                  child: StoryVideoView(url: _videoPreviewUrl!, loop: true))
              : Container(
                  color: Colors.black,
                  child: const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.movie_creation_outlined,
                        color: Colors.white54, size: 64),
                    SizedBox(height: 12),
                    Text('Видео бэлэн',
                        style: TextStyle(color: Colors.white54)),
                  ])))
        else
          // Канвасыг 9:16-д барина — desktop цонхон дээр bake хийсэн зураг
          // хэвтээ гарахаас сэргийлнэ (хажуу талд хар gutters)
          Positioned.fill(
              child: Center(
                  child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: LayoutBuilder(builder: (ctx, cons) {
                        final w = cons.maxWidth, h = cons.maxHeight;
                        final pos = _textPos ?? Offset(w * 0.1, h * 0.42);
                        return Stack(fit: StackFit.expand, children: [
                          RepaintBoundary(
                            key: _boundaryKey,
                            child: Stack(fit: StackFit.expand, children: [
                              Positioned.fill(
                                  child: _filtered(
                                      _filter,
                                      Image.memory(_bytes!,
                                          fit: BoxFit.cover))),
                              // Зурсан зураас
                              if (_strokes.isNotEmpty)
                                Positioned.fill(
                                    child: IgnorePointer(
                                        child: CustomPaint(
                                            painter: _DrawPainter(_strokes)))),
                              if (hasText)
                                Positioned(
                                    left: pos.dx,
                                    top: pos.dy,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanUpdate: (!_canEdit || _drawMode)
                                          ? null
                                          : (d) => setState(() {
                                                final cur = _textPos ??
                                                    Offset(w * 0.1, h * 0.42);
                                                _textPos = cur + d.delta;
                                              }),
                                      onTap: (!_canEdit || _drawMode)
                                          ? null
                                          : _editText,
                                      child: SizedBox(
                                          width: w * 0.8,
                                          child: Text(_text,
                                              textAlign: TextAlign.center,
                                              style: _textStyle(30).copyWith(
                                                  shadows: const [
                                                    Shadow(
                                                        blurRadius: 12,
                                                        color: Colors.black54)
                                                  ]))),
                                    )),
                            ]),
                          ),
                          // Хөгжмийн sticker (чирэгддэг) — bake-д ОРОХГҮЙ:
                          // viewer DB-ийн music_title/artist-аас өөрөө харуулдаг тул
                          // зурагт бас baked байвал давхардана
                          if (_songTitle != null)
                            Positioned(
                                left:
                                    (_songPos ?? Offset(w * 0.16, h * 0.8)).dx,
                                top: (_songPos ?? Offset(w * 0.16, h * 0.8)).dy,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanUpdate: (!_canEdit || _drawMode)
                                      ? null
                                      : (d) => setState(() {
                                            final cur = _songPos ??
                                                Offset(w * 0.16, h * 0.8);
                                            _songPos = cur + d.delta;
                                          }),
                                  onTap: (!_canEdit || _drawMode)
                                      ? null
                                      : _musicSheet,
                                  child: Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 7, 14, 7),
                                    decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(22),
                                        border:
                                            Border.all(color: Colors.white24)),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.music_note_rounded,
                                              color: Colors.white, size: 16),
                                          const SizedBox(width: 6),
                                          ConstrainedBox(
                                              constraints: BoxConstraints(
                                                  maxWidth: w * 0.6),
                                              child: Text(
                                                  '$_songTitle · $_songArtist',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600))),
                                        ]),
                                  ),
                                )),
                          // Зурах горимын gesture overlay (хамгийн дээр)
                          if (_drawMode)
                            Positioned.fill(
                                child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (d) => setState(() {
                                final s = _Stroke(_kTextColors[_drawColor], 5);
                                s.points.add(d.localPosition);
                                _strokes.add(s);
                              }),
                              onPanUpdate: (d) => setState(() {
                                if (_strokes.isNotEmpty) {
                                  _strokes.last.points.add(d.localPosition);
                                }
                              }),
                            )),
                        ]);
                      })))),

        // Caption (видеоны үед — bake хийхгүй тул overlay)
        if (_isVideo && hasText)
          Center(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(_text,
                      textAlign: TextAlign.center,
                      style: _textStyle(28).copyWith(shadows: const [
                        Shadow(blurRadius: 12, color: Colors.black)
                      ])))),

        const IgnorePointer(
            child: DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
              Colors.black45,
              Colors.transparent,
              Colors.transparent,
              Colors.black87
            ],
                        stops: [
              0,
              0.16,
              0.62,
              1
            ])))),

        // Дээд: хаах (шууд URL-ээр орсон бол feed рүү)
        SafeArea(
            child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _circleBtn(Icons.close, _requestClose)))),

        // Баруун toolbar
        SafeArea(
            child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Column(children: [
                    _toolBtn(Icons.text_fields_rounded, _editText),
                    if (hasText && !_isVideo) ...[
                      _toolBtnChild(
                          Text('Aa',
                              style:
                                  _textStyle(15).copyWith(color: Colors.white)),
                          () => setState(() => _font = (_font + 1) % 4)),
                      _toolBtnChild(
                          Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _kTextColors[_color],
                                  border: Border.all(color: Colors.white54))),
                          () => setState(() =>
                              _color = (_color + 1) % _kTextColors.length)),
                    ],
                    _toolBtn(Icons.emoji_emotions_outlined, _pickSticker),
                    if (!_isVideo)
                      _toolBtn(Icons.music_note_rounded, _musicSheet,
                          active: _songTitle != null),
                    _toolBtn(Icons.alternate_email_rounded, _pickMentions),
                    if (!_isVideo)
                      _toolBtn(Icons.auto_awesome_rounded,
                          () => setState(() => _filterBar = !_filterBar),
                          active: _filterBar || _filter != 0),
                    if (!_isVideo)
                      _toolBtn(Icons.brush_rounded,
                          () => setState(() => _drawMode = !_drawMode),
                          active: _drawMode),
                    Tooltip(
                        message: _venueRef == null
                            ? 'Байршил нэмэх'
                            : 'Байршил солих',
                        child: _toolBtn(Icons.location_on_outlined, _pickVenue,
                            active: _venueRef != null)),
                  ]),
                ))),

        // Зурах горимын удирдлага
        if (_drawMode)
          SafeArea(
              child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        // Өнгө сонгох
                        for (var i = 0; i < _kTextColors.length; i++)
                          GestureDetector(
                              onTap: () => setState(() => _drawColor = i),
                              child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _kTextColors[i],
                                      border: Border.all(
                                          color: _drawColor == i
                                              ? Colors.white
                                              : Colors.white24,
                                          width: _drawColor == i ? 3 : 1)))),
                        Container(
                            width: 1,
                            height: 24,
                            color: Colors.white24,
                            margin: const EdgeInsets.symmetric(horizontal: 6)),
                        // Буцаах
                        GestureDetector(
                            onTap: _strokes.isEmpty
                                ? null
                                : () => setState(() => _strokes.removeLast()),
                            child: Icon(Icons.undo_rounded,
                                size: 22,
                                color: _strokes.isEmpty
                                    ? Colors.white30
                                    : Colors.white)),
                        const SizedBox(width: 12),
                        // Болсон
                        GestureDetector(
                            onTap: () => setState(() => _drawMode = false),
                            child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text('Болсон',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)))),
                      ]),
                    ),
                  ))),

        // Доод: chips + share
        SafeArea(
          top: false,
          child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // ── Filter сонгох зурвас (зөөлөн нээгдэж/хаагдана) ──
                    AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: (!_isVideo &&
                                _filterBar &&
                                !_drawMode &&
                                _bytes != null)
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SizedBox(
                                  height: 86,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _kFilters.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (_, i) {
                                      final sel = _filter == i;
                                      return _Pressable(
                                        onTap: () =>
                                            setState(() => _filter = i),
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 52, height: 64,
                                                clipBehavior: Clip.antiAlias,
                                                decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    border: Border.all(
                                                        color: sel
                                                            ? AppColors
                                                                .accentStart
                                                            : Colors.white24,
                                                        width: sel ? 2.5 : 1)),
                                                // cacheWidth — том зургийг thumbnail бүрт бүтэн
                                                // хэмжээгээр нь 9 удаа decode хийхгүй
                                                child: _filtered(
                                                    i,
                                                    Image.memory(_bytes!,
                                                        fit: BoxFit.cover,
                                                        width: 52,
                                                        height: 64,
                                                        cacheWidth: 104)),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(_kFilters[i].name,
                                                  style: TextStyle(
                                                      color: sel
                                                          ? Colors.white
                                                          : Colors.white60,
                                                      fontSize: 11,
                                                      fontWeight: sel
                                                          ? FontWeight.w700
                                                          : FontWeight.w400)),
                                            ]),
                                      );
                                    },
                                  ),
                                ),
                              )
                            : const SizedBox(width: double.infinity)),
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Expanded(
                              child: TextButton.icon(
                                  key: const ValueKey('story-location-picker'),
                                  onPressed: _canEdit ? _pickVenue : null,
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      disabledForegroundColor: Colors.white54,
                                      backgroundColor: Colors.black54,
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10)),
                                  icon: Icon(
                                      _venueRef == null
                                          ? Icons.add_location_alt_outlined
                                          : Icons.location_on_rounded,
                                      size: 20),
                                  label: Text(
                                      _venueName ??
                                          'Байршил нэмэх (сонголтоор)',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis))),
                          if (_venueRef != null)
                            IconButton(
                                tooltip: 'Байршлыг хасах',
                                onPressed: !_canEdit
                                    ? null
                                    : () => setState(() {
                                          _venueId = null;
                                          _venueRef = null;
                                          _venueName = null;
                                        }),
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white)),
                        ])),
                    if (_venueRef != null)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                              'Өнөөдрийн газрын зурагт story-гийн идэвх нэмэгдэнэ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11))),
                    if (_mentions.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: [
                                ..._mentions.map((m) => _selChip(
                                    Icons.alternate_email_rounded,
                                    (m['username'] as String)
                                        .replaceAll('@', ''),
                                    () => setState(() => _mentions.remove(m)))),
                              ])),
                    if (_busy)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_progressLabel,
                              style: AppTextStyles.bodyXs
                                  .copyWith(color: Colors.white))),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_error!,
                              style: AppTextStyles.bodyXs
                                  .copyWith(color: AppColors.error))),
                    _Pressable(
                      onTap: _busy ? null : _share,
                      child: AnimatedOpacity(
                          opacity: _busy ? 0.75 : 1,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                              height: 50,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                  gradient: AppColors.accentGradient,
                                  borderRadius: BorderRadius.circular(16)),
                              alignment: Alignment.center,
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                          Text(
                                              _pendingRow == null
                                                  ? 'Story-д хуваалцах'
                                                  : 'Дахин шалгах',
                                              style: AppTextStyles.btn.copyWith(
                                                  color: Colors.white)),
                                          const SizedBox(width: 8),
                                          const Icon(Icons.send_rounded,
                                              color: Colors.white, size: 18),
                                        ]))),
                    ),
                    const SizedBox(height: 6),
                    Text('24 цагийн дараа харагдахаа болино',
                        style: AppTextStyles.bodyXs
                            .copyWith(color: Colors.white54)),
                  ]))),
        ),
      ]),
    );
  }

  Widget _pickerScreen() => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black, elevation: 0,
          // Үргэлж харанхуй — light горимд ч статус бар цайвар дүрстэй
          systemOverlayStyle: SystemUiOverlayStyle.light,
          leading: IconButton(
              onPressed: _requestClose,
              icon: const Icon(Icons.close, color: Colors.white)),
          title: Text('Шинэ story',
              style: AppTextStyles.labelLg.copyWith(color: Colors.white)),
        ),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome, color: Colors.white38, size: 64),
          const SizedBox(height: 20),
          Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _bigPick(
                    Icons.photo_library_outlined, 'Зургийн сан', _pickGallery),
                _bigPick(Icons.camera_alt_outlined, 'Камер', _openCamera),
                _bigPick(Icons.videocam_outlined, 'Видео', _pickVideo),
              ]),
          const SizedBox(height: 14),
          if (_picking) const CircularProgressIndicator(color: Colors.white),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Зураг 25MB · Видео 50MB / 60 секунд хүртэл',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60))),
        ])),
      );

  Widget _bigPick(IconData icon, String label, VoidCallback onTap) =>
      _Pressable(
          onTap: _canEdit ? onTap : null,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                  color: AppColors.bgSurfaceDark,
                  borderRadius: BorderRadius.circular(14)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(height: 6),
                Text(label,
                    style: AppTextStyles.bodyXs.copyWith(color: Colors.white)),
              ])));

  Widget _circleBtn(IconData icon, VoidCallback onTap) => _Pressable(
      onTap: onTap,
      child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.black38),
          child: Icon(icon, color: Colors.white, size: 22)));

  Widget _toolBtn(IconData icon, VoidCallback onTap, {bool active = false}) =>
      _toolBtnChild(Icon(icon, color: Colors.white, size: 22), onTap,
          active: active);

  Widget _toolBtnChild(Widget child, VoidCallback onTap,
          {bool active = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _Pressable(
              onTap: _canEdit ? onTap : null,
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? AppColors.accentStart : Colors.black38),
                  child: child)));

  Widget _selChip(IconData icon, String label, VoidCallback onClear) =>
      Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          decoration: BoxDecoration(
              color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(width: 2),
            _Pressable(
                onTap: _canEdit ? onClear : null,
                child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close, color: Colors.white60, size: 14))),
          ]));
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
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
            widget.onTap == null ? null : (_) => setState(() => _down = true),
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

enum _PickerMode { venue, user }

class _PickerSheet extends StatefulWidget {
  final _PickerMode mode;
  const _PickerSheet({required this.mode});
  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _failed = false; // сүлжээний алдаа — "олдсонгүй"-ээс ялгаатай
  Timer? _debounce;
  int _reqSeq = 0; // хоцорсон хариу шинэ үр дүнг дарж бичихээс сэргийлнэ

  @override
  void initState() {
    super.initState();
    _search('');
  }

  // Keystroke бүрт биш — 300мс debounce-тэй хайна
  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final myReq = ++_reqSeq;
    setState(() => _loading = true);
    try {
      List<Map<String, dynamic>> results;
      if (widget.mode == _PickerMode.venue) {
        var query =
            SupabaseService.client.from('venues').select('id, name, district');
        if (q.isNotEmpty) query = query.ilike('name', '%$q%');
        final data = await query.limit(30);
        results = (data as List).cast<Map<String, dynamic>>();
      } else {
        final me = SupabaseService.currentUser?.id;
        var query = SupabaseService.client
            .from('profiles')
            .select('id, username, avatar_url');
        if (q.isNotEmpty) query = query.ilike('username', '%$q%');
        final data = await query.limit(30);
        results = (data as List)
            .cast<Map<String, dynamic>>()
            .where((p) => p['id'] != me)
            .toList();
      }
      if (myReq != _reqSeq) return; // хуучин хүсэлт — хэрэгсэхгүй
      _results = results;
      _failed = false;
    } catch (_) {
      if (myReq != _reqSeq) return;
      _results = [];
      _failed = true;
    }
    if (mounted && myReq == _reqSeq) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVenue = widget.mode == _PickerMode.venue;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Text(isVenue ? 'Байршил сонгох' : 'Хүн тэмдэглэх',
            style: AppTextStyles.labelLg),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl, autofocus: true,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
          // Keystroke бүрт биш — 300мс debounce-тэй хайна
          onChanged: _onQueryChanged,
          decoration: InputDecoration(
              hintText: isVenue ? 'Газар хайх...' : '@ хэрэглэгч хайх...',
              prefixIcon: Icon(Icons.search, color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.bgSurface,
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 340,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accentStart, strokeWidth: 2))
              : _results.isEmpty
                  ? Center(
                      child: Text(
                          _failed
                              ? 'Сүлжээний алдаа. Дахин оролдоно уу.'
                              : isVenue
                                  ? 'Газар олдсонгүй'
                                  : 'Хэрэглэгч олдсонгүй',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMd
                              .copyWith(color: AppColors.textSecondary)))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final r = _results[i];
                        if (isVenue) {
                          return ListTile(
                            leading: const Icon(Icons.location_on,
                                color: AppColors.accentStart),
                            title: Text(r['name'] as String? ?? '',
                                style: AppTextStyles.bodyMd
                                    .copyWith(color: AppColors.textPrimary)),
                            subtitle: r['district'] != null
                                ? Text(r['district'] as String,
                                    style: AppTextStyles.bodyXs.copyWith(
                                        color: AppColors.textSecondary))
                                : null,
                            onTap: () => Navigator.pop(context, r),
                          );
                        }
                        final uname = (r['username'] as String? ?? 'User')
                            .replaceAll('@', '');
                        return ListTile(
                          leading: AppAvatar(
                              imageUrl: r['avatar_url'] as String?, size: 40),
                          title: Text('@$uname',
                              style: AppTextStyles.bodyMd
                                  .copyWith(color: AppColors.textPrimary)),
                          onTap: () => Navigator.pop(context, r),
                        );
                      }),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}
