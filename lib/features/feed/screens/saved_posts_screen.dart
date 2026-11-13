import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';
import '../../../core/widgets/authorized_media.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';

class SavedPostsScreen extends ConsumerStatefulWidget {
  const SavedPostsScreen({super.key});
  @override
  ConsumerState<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends ConsumerState<SavedPostsScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _error = false; // алдаа ≠ хоосон — тусад нь харуулна
  (String?, int)? _scope;
  int _request = 0;

  // Masonry өндрийн хэв — индексээр ээлжилж баганын хэмнэл үүсгэнэ
  static const _heights = [230.0, 300.0, 250.0, 200.0];

  @override
  void initState() {
    super.initState();
    _load(notify: false);
  }

  bool _isCurrent(int request) =>
      mounted &&
      request == _request &&
      _scope ==
          (ref.read(sessionUserIdProvider), ref.read(socialVersionProvider));

  Future<void> _load({bool notify = true}) async {
    if (!mounted) return;
    final scope =
        (ref.read(sessionUserIdProvider), ref.read(socialVersionProvider));
    final changed = _scope != scope;
    _scope = scope;
    final request = ++_request;
    void reset() {
      if (changed) {
        _posts = [];
        _loading = scope.$1 != null;
      }
      _error = false;
    }

    if (notify) {
      setState(reset);
    } else {
      reset();
    }
    try {
      final me = scope.$1;
      if (me == null) return;
      final saves = await SupabaseService.client
          .from('saved_posts')
          .select('post_id, created_at')
          .eq('user_id', me)
          .order('created_at', ascending: false)
          .limit(100);
      if (!_isCurrent(request)) return;
      final ids = (saves as List).map((e) => e['post_id'] as String).toList();
      if (ids.isEmpty) {
        setState(() {
          _posts = [];
          _loading = false;
          _error = false;
        });
        return;
      }
      final posts = await SupabaseService.client
          .from('posts')
          .select('id, media_url')
          .inFilter('id', ids);
      if (!_isCurrent(request)) return;
      final pmap = {
        for (final p in (posts as List).cast<Map<String, dynamic>>())
          p['id'] as String: p
      };
      // Хадгалсан дарааллаар
      _posts =
          ids.map((id) => pmap[id]).whereType<Map<String, dynamic>>().toList();
      setState(() {
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (_isCurrent(request)) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope =
        (ref.watch(sessionUserIdProvider), ref.watch(socialVersionProvider));
    if (scope != _scope) _load(notify: false);
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header — AppHeader.title: буцах + гарчиг + постын тоо (DS-06).
        // Pop хийх хуудасгүй (deep link) үед профайл руу буцна.
        AppHeader.title(
          title: 'Хадгалсан',
          subtitle: !_loading && !_error && _posts.isNotEmpty
              ? '${_posts.length} пост'
              : null,
          fallbackLocation: AppRoutes.profile,
        ),

        Expanded(
          child: _loading
              ? const _SkeletonMasonry()
              : _error
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off_outlined,
                          size: 48, color: AppColors.textTertiary),
                      const SizedBox(height: 12),
                      Text('Алдаа гарлаа', style: AppTextStyles.h2),
                      const SizedBox(height: 6),
                      Text('Хадгалсан постуудыг ачаалж чадсангүй',
                          style: AppTextStyles.bodyMd
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 18),
                      // Алдааны төлвийн primary CTA — мэдэгдэл, хайлтын
                      // дэлгэцтэй ижил GradientButton (md) (DS-03)
                      GradientButton(
                        label: 'Дахин оролдох',
                        size: GradientButtonSize.md,
                        fullWidth: false,
                        onPressed: () {
                          setState(() => _loading = true);
                          _load();
                        },
                      ),
                    ]))
                  : RefreshIndicator(
                      color: AppColors.accentText,
                      backgroundColor: AppColors.bgElevated,
                      onRefresh: _load,
                      child: _posts.isEmpty
                          // Нэгдсэн хоосон төлөв (medallion + h3 + дэд текст) —
                          // pull-to-refresh ажиллахын тулд scroll дотор
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                    height: MediaQuery.of(context).size.height *
                                        0.14),
                                const EmptyState(
                                  icon: AppIcons.save,
                                  title: 'Хадгалсан пост алга',
                                  subtitleWidget: _SaveHint(),
                                ),
                              ],
                            )
                          : _masonry(),
                    ),
        ),
      ])),
    );
  }

  /// Masonry маягийн 2 багана — Pinterest/IG collections мэдрэмж.
  /// Индексийг тэгш/сондгойгоор хоёр баганад хувааж дараалал хадгална.
  Widget _masonry() {
    final left = <int>[];
    final right = <int>[];
    for (var i = 0; i < _posts.length; i++) {
      (i.isEven ? left : right).add(i);
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: [for (final i in left) _tile(i)])),
          const SizedBox(width: 14),
          Expanded(child: Column(children: [for (final i in right) _tile(i)])),
        ]),
      ],
    );
  }

  Widget _tile(int i) {
    final p = _posts[i];
    final url = p['media_url'] as String?;
    final isVideo = isVideoUrl(url?.split('?').first);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            // Detail-с буцахад unsave өөрчлөлт шинэчлэгдэнэ
            await context.push('/post/${p['id']}');
            if (mounted) _load();
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: _heights[i % _heights.length],
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (url != null && !isVideo)
                  AuthorizedImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      memCacheWidth: 500,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) =>
                          Container(color: AppColors.bgSurface),
                      errorWidget: (_, __, ___) => Container(
                          color: AppColors.bgSurface,
                          child: Icon(AppIcons.imageBroken,
                              color: AppColors.textTertiary)))
                else if (isVideo && url != null)
                  // Видеоны эхний кадрыг cover болгож харуулна (+ play icon)
                  NetworkVideo(url: url, posterOnly: true)
                else
                  Container(color: AppColors.bgSurface),
                // Видео badge — баруун дээд
                if (isVideo)
                  const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.play_circle_fill,
                          size: 20, color: Colors.white70)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Хоосон төлвийн тайлбар: "Постын [хадгалах icon] товч дарж хадгална" ───
// Emoji-гийн оронд постын хадгалах товчны жинхэнэ icon (DS-09); EmptyState-ийн
// дэд текстийн хэвтэй ижил. Дэлгэц уншигч icon-ыг "хадгалах" гэж уншина.
class _SaveHint extends StatelessWidget {
  const _SaveHint();

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Постын '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(AppIcons.save,
                size: 18,
                color: AppColors.textSecondary,
                semanticLabel: 'хадгалах'),
          ),
          const TextSpan(text: ' товч дарж хадгална'),
        ]),
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMd
            .copyWith(color: AppColors.textSecondary, height: 1.5),
      );
}

// ─── Ачаалах skeleton — masonry хэвтэй ижил хэмнэл ───
class _SkeletonMasonry extends StatelessWidget {
  const _SkeletonMasonry();

  Widget _box(double h) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
          height: h,
          decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(16))));

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: AppColors.bgElevated,
        highlightColor: AppColors.bgSurface,
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(children: [
                _box(230),
                _box(250),
                _box(230),
              ])),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(children: [
                _box(300),
                _box(200),
                _box(300),
              ])),
            ]),
          ],
        ),
      );
}
