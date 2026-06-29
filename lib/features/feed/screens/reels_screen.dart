import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});
  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  List<Map<String, dynamic>> _reels = [];
  bool _loading = true;
  bool _canCreate = false; // зөвхөн venue эзэн оруулна
  final Set<String> _liked = {};

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _checkOwner();
  }

  Future<void> _checkOwner() async {
    if (_myId.isEmpty) return;
    try {
      final r = await SupabaseService.client.from('venues')
          .select('id').eq('owner_id', _myId).limit(1).maybeSingle();
      if (mounted) setState(() => _canCreate = r != null);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final data = await SupabaseService.client
          .from('posts')
          .select('id, user_id, caption, media_url, likes_count, comments_count, '
              'profiles!user_id (username, avatar_url)')
          .order('created_at', ascending: false)
          .limit(50);
      final all = (data as List).cast<Map<String, dynamic>>();
      final reels = all.where((p) => isVideoUrl(p['media_url'] as String?)).toList();

      // Аль reel-уудыг лайкласныг шалгах
      if (_myId.isNotEmpty && reels.isNotEmpty) {
        final ids = reels.map((r) => r['id'] as String).toList();
        final likes = await SupabaseService.client
            .from('likes').select('post_id').eq('user_id', _myId).inFilter('post_id', ids);
        for (final l in (likes as List)) { _liked.add(l['post_id'] as String); }
      }
      if (mounted) setState(() { _reels = reels; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final user = _myId;
    if (user.isEmpty) return;
    final wasLiked = _liked.contains(id);
    setState(() {
      if (wasLiked) {
        _liked.remove(id);
        reel['likes_count'] = (reel['likes_count'] as int? ?? 1) - 1;
      } else {
        _liked.add(id);
        reel['likes_count'] = (reel['likes_count'] as int? ?? 0) + 1;
      }
    });
    try {
      if (wasLiked) {
        await SupabaseService.client.from('likes').delete()
            .eq('user_id', user).eq('post_id', id);
      } else {
        await SupabaseService.client.from('likes').insert({'user_id': user, 'post_id': id});
      }
    } catch (_) {}
  }

  Future<void> _deleteReel(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Бичлэг устгах уу?', style: AppTextStyles.h3),
        content: Text('Энэ live/reel бичлэгийг бүрмөсөн устгана.',
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: Text('Болих', style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(d, true),
              child: Text('Устгах', style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('posts')
          .delete().eq('id', id).eq('user_id', _myId);
      if (mounted) {
        setState(() => _reels.removeWhere((r) => r['id'] == id));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Бичлэг устгагдлаа')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.accentStart, strokeWidth: 2))
        : _reels.isEmpty
          ? _empty(context)
          : Stack(children: [
              PageView.builder(
                scrollDirection: Axis.vertical,
                itemCount: _reels.length,
                itemBuilder: (_, i) => _ReelPage(
                  reel: _reels[i],
                  height: h,
                  liked: _liked.contains(_reels[i]['id']),
                  onLike: () => _toggleLike(_reels[i]),
                  isOwn: _reels[i]['user_id'] == _myId,
                  onDelete: () => _deleteReel(_reels[i]),
                ),
              ),
              // Дээд гарчиг + нэмэх (зөвхөн venue эзэн)
              SafeArea(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Text('Discovery', style: AppTextStyles.h2.copyWith(color: Colors.white)),
                  const Spacer(),
                  if (_canCreate)
                    GestureDetector(
                      onTap: () => context.push('/reels/create'),
                      child: const Icon(Icons.add_box_outlined, color: Colors.white, size: 28)),
                ]))),
            ]),
    );
  }

  Widget _empty(BuildContext context) => SafeArea(child: Stack(children: [
    Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.explore_outlined, color: Colors.white38, size: 72),
      const SizedBox(height: 16),
      Text('Контент алга байна', style: AppTextStyles.h2.copyWith(color: Colors.white)),
      const SizedBox(height: 8),
      Text(_canCreate
          ? 'Эхний бичлэгээ хуваалцаарай!'
          : 'Venue эзэд богино видео нийтэлдэг',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMd.copyWith(color: Colors.white54)),
      if (_canCreate) ...[
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => context.push('/reels/create'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
            child: Text('Бичлэг нэмэх', style: AppTextStyles.btn.copyWith(color: Colors.white)))),
      ],
    ])),
    Align(alignment: Alignment.topLeft, child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Discovery', style: AppTextStyles.h2.copyWith(color: Colors.white)))),
  ]));
}

class _ReelPage extends StatelessWidget {
  final Map<String, dynamic> reel;
  final double height;
  final bool liked;
  final VoidCallback onLike;
  final bool isOwn;
  final VoidCallback? onDelete;
  const _ReelPage({
    required this.reel, required this.height,
    required this.liked, required this.onLike,
    this.isOwn = false, this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final prof = reel['profiles'] as Map?;
    final username = (prof?['username'] as String? ?? 'User').replaceAll('@', '');
    final avatarUrl = prof?['avatar_url'] as String?;
    final caption = reel['caption'] as String? ?? '';
    final likes = reel['likes_count'] as int? ?? 0;
    final comments = reel['comments_count'] as int? ?? 0;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Stack(fit: StackFit.expand, children: [
      // Видео (autoplay loop)
      NetworkVideo(url: reel['media_url'] as String, autoplay: true, height: height),

      // Доод градиент
      const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.center,
          colors: [Colors.black87, Colors.transparent])))),

      // Баруун үйлдлүүд
      Positioned(right: 10, bottom: 100, child: Column(children: [
        GestureDetector(onTap: onLike, child: Column(children: [
          Icon(liked ? Icons.favorite : Icons.favorite_border,
            color: liked ? const Color(0xFFFF3B5C) : Colors.white, size: 34),
          const SizedBox(height: 4),
          Text('$likes', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ])),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => context.push('/post/${reel['id']}'),
          child: Column(children: [
            const Icon(Icons.mode_comment_outlined, color: Colors.white, size: 31),
            const SizedBox(height: 4),
            Text('$comments', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ])),
        const SizedBox(height: 20),
        const Icon(Icons.send_outlined, color: Colors.white, size: 30),
        // Өөрийн бичлэг (live/reel) бол устгах
        if (isOwn) ...[
          const SizedBox(height: 20),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.delete_outline, color: Colors.white, size: 30)),
        ],
      ])),

      // Доод зүүн: зохиогч + тайлбар
      Positioned(left: 14, right: 80, bottom: 90, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => context.push('/creator/${reel['user_id']}'),
            child: Row(children: [
              AppAvatar(imageUrl: avatarUrl, initial: initial, size: 36),
              const SizedBox(width: 8),
              Text('@$username', style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ])),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ])),
    ]);
  }
}
