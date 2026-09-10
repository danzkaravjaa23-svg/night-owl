import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';

class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});
  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _error = false; // алдаа ≠ хоосон — тусад нь харуулна

  // Masonry өндрийн хэв — индексээр ээлжилж баганын хэмнэл үүсгэнэ
  static const _heights = [230.0, 300.0, 250.0, 200.0];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final me = SupabaseService.currentUser?.id;
      if (me == null) { setState(() => _loading = false); return; }
      final saves = await SupabaseService.client.from('saved_posts')
          .select('post_id, created_at').eq('user_id', me)
          .order('created_at', ascending: false).limit(100);
      final ids = (saves as List).map((e) => e['post_id'] as String).toList();
      if (ids.isEmpty) {
        if (mounted) setState(() { _posts = []; _loading = false; _error = false; });
        return;
      }
      final posts = await SupabaseService.client.from('posts')
          .select('id, media_url').inFilter('id', ids);
      final pmap = { for (final p in (posts as List).cast<Map<String, dynamic>>())
        p['id'] as String: p };
      // Хадгалсан дарааллаар
      _posts = ids.map((id) => pmap[id]).whereType<Map<String, dynamic>>().toList();
      if (mounted) setState(() { _loading = false; _error = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header — glass back + h1 гарчиг + тоо micro ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.pop(),
                  child: Container(width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bgElevated.withValues(alpha: 0.72),
                      border: Border.all(color: AppColors.hairline)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        size: 16, color: AppColors.textPrimary)))),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Хадгалсан', style: AppTextStyles.h1),
                if (!_loading && !_error && _posts.isNotEmpty)
                  Text('${_posts.length} пост',
                      style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.textTertiary)),
              ]),
            ]),
          ),

          Expanded(child: _loading
            ? const _SkeletonMasonry()
            : _error
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textTertiary),
                  const SizedBox(height: 12),
                  Text('Алдаа гарлаа', style: AppTextStyles.h2),
                  const SizedBox(height: 6),
                  Text('Хадгалсан постуудыг ачаалж чадсангүй',
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: () { setState(() => _loading = true); _load(); },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.hairline),
                      foregroundColor: AppColors.accentStart),
                    child: const Text('Дахин оролдох'),
                  ),
                ]))
              : RefreshIndicator(
                  color: AppColors.accentStart,
                  backgroundColor: AppColors.bgElevated,
                  onRefresh: _load,
                  child: _posts.isEmpty
                    // Нэгдсэн хоосон төлөв (medallion + h3 + дэд текст) —
                    // pull-to-refresh ажиллахын тулд scroll дотор
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                              height: MediaQuery.of(context).size.height * 0.14),
                          const EmptyState(
                            icon: Icons.bookmark_border_rounded,
                            title: 'Хадгалсан пост алга',
                            subtitle: 'Постын 🔖 товч дарж хадгална',
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
    final left = <int>[]; final right = <int>[];
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
                  CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                    memCacheWidth: 500,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, __) => Container(color: AppColors.bgSurface),
                    errorWidget: (_, __, ___) => Container(color: AppColors.bgSurface,
                      child: const Icon(Icons.image_not_supported_outlined,
                        color: AppColors.textTertiary)))
                else if (isVideo && url != null)
                  // Видеоны эхний кадрыг cover болгож харуулна (+ play icon)
                  NetworkVideo(url: url, posterOnly: true)
                else
                  Container(color: AppColors.bgSurface),
                // Видео badge — баруун дээд
                if (isVideo)
                  const Positioned(top: 8, right: 8,
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

// ─── Ачаалах skeleton — masonry хэвтэй ижил хэмнэл ───
class _SkeletonMasonry extends StatelessWidget {
  const _SkeletonMasonry();

  Widget _box(double h) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(height: h,
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
          Expanded(child: Column(children: [
            _box(230), _box(250), _box(230),
          ])),
          const SizedBox(width: 14),
          Expanded(child: Column(children: [
            _box(300), _box(200), _box(300),
          ])),
        ]),
      ],
    ),
  );
}
