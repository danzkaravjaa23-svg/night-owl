import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
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
      if (ids.isEmpty) { if (mounted) setState(() { _posts = []; _loading = false; }); return; }
      final posts = await SupabaseService.client.from('posts')
          .select('id, media_url, likes_count').inFilter('id', ids);
      final pmap = { for (final p in (posts as List).cast<Map<String, dynamic>>())
        p['id'] as String: p };
      // Хадгалсан дарааллаар
      _posts = ids.map((id) => pmap[id]).whereType<Map<String, dynamic>>().toList();
      if (mounted) setState(() => _loading = false);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase, elevation: 0,
        leading: IconButton(onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text('Хадгалсан', style: AppTextStyles.h2),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.accentStart, strokeWidth: 2))
        : _posts.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bookmark_border_rounded, size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              Text('Хадгалсан пост алга', style: AppTextStyles.h2),
              const SizedBox(height: 6),
              Text('Постын 🔖 товч дарж хадгална',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
            ]))
          : GridView.builder(
              padding: const EdgeInsets.all(1.5),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 1.5, mainAxisSpacing: 1.5),
              itemCount: _posts.length,
              itemBuilder: (_, i) {
                final p = _posts[i];
                final url = p['media_url'] as String?;
                final isVideo = isVideoUrl(url);
                return GestureDetector(
                  onTap: () => context.push('/post/${p['id']}'),
                  child: Stack(fit: StackFit.expand, children: [
                    if (url != null && !isVideo)
                      CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.bgSurface),
                        errorWidget: (_, __, ___) => Container(color: AppColors.bgSurface,
                          child: const Icon(Icons.image_not_supported_outlined,
                            color: AppColors.textTertiary)))
                    else if (isVideo && url != null)
                      // Видеоны эхний кадрыг cover болгож харуулна (+ play icon)
                      NetworkVideo(url: url, posterOnly: true)
                    else
                      Container(color: AppColors.bgSurface),
                  ]),
                );
              },
            ),
    );
  }
}
