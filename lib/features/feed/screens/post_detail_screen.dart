import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/post.dart';
import '../../../models/comment.dart';
import '../providers/comment_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/saved_provider.dart';
import '../../profile/widgets/block_report_sheet.dart';

/// Сэтгэгдлийн input-д харуулах өөрийн mini профайл (avatar + username)
final _myMiniProfileProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final me = SupabaseService.currentUser?.id;
  if (me == null) return null;
  try {
    return await SupabaseService.client
        .from('profiles')
        .select('username, avatar_url')
        .eq('id', me)
        .maybeSingle();
  } catch (_) {
    return null;
  }
});

class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl  = TextEditingController();
  final _scrollCtrl   = ScrollController();
  final _focusNode    = FocusNode();
  bool  _sending      = false;
  Post? _post;
  bool  _postLoading  = true;
  bool  _postError    = false; // сүлжээний алдаа ≠ пост олдсонгүй
  Comment? _replyTo;

  @override
  void initState() {
    super.initState();
    _fetchPost();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchPost() async {
    if (mounted && (!_postLoading || _postError)) {
      setState(() { _postLoading = true; _postError = false; });
    }
    try {
      final me = SupabaseService.currentUser?.id;
      // Постыг id-аар шууд татна (хуучин get_feed_posts(limit 1)-ийн оронд)
      final raw = await SupabaseService.client
          .from('posts')
          .select('*, profiles!user_id (id, username, avatar_url, is_verified)')
          .eq('id', widget.postId)
          .maybeSingle();
      if (raw == null) {
        if (mounted) setState(() { _post = null; _postLoading = false; });
        return;
      }
      // isLikedByMe — нэг индекстэй query (likes unique(user_id,post_id))
      bool liked = false;
      if (me != null) {
        final l = await SupabaseService.client
            .from('likes')
            .select('post_id')
            .eq('post_id', widget.postId)
            .eq('user_id', me)
            .maybeSingle();
        liked = l != null;
      }
      final map = Map<String, dynamic>.from(raw as Map);
      map['is_liked_by_me'] = liked;
      if (mounted) {
        setState(() { _post = Post.fromJson(map); _postLoading = false; });
      }
    } catch (_) {
      // Сүлжээний алдаа — "олдсонгүй" гэж хуурахгүй, retry харуулна
      if (mounted) setState(() { _postLoading = false; _postError = true; });
    }
  }

  /// Like — фийдэд байгаа эсэхээс үл хамааран DB-д бичигдэнэ
  Future<void> _toggleLike() async {
    final post = _post;
    if (post == null) return;
    final was = post.isLikedByMe;
    HapticFeedback.lightImpact();
    setState(() {
      _post = post.copyWith(
        isLikedByMe: !was,
        likesCount: post.likesCount + (was ? -1 : 1),
      );
    });
    final ok = await ref.read(feedProvider.notifier)
        .toggleLikeById(widget.postId, was);
    if (!ok && mounted) {
      // Rollback + мэдэгдэнэ
      setState(() {
        _post = _post!.copyWith(
          isLikedByMe: was,
          likesCount: _post!.likesCount + (was ? 1 : -1),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Лайк илгээж чадсангүй'),
        backgroundColor: AppColors.error));
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text;
    if (text.trim().isEmpty || _sending) return;

    setState(() => _sending = true);
    // Reply бол эх сэтгэгдэлд (нэг түвшний thread): reply-д хариулбал эхэнд нь
    final parentId = _replyTo == null
        ? null
        : (_replyTo!.parentId ?? _replyTo!.id);
    final err = await CommentService.addComment(
      postId:   widget.postId,
      body:     text,
      parentId: parentId,
    );
    if (!mounted) return;
    setState(() { _sending = false; _replyTo = null; });

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.error));
      return;
    }

    _commentCtrl.clear();
    HapticFeedback.lightImpact();
    // Scroll to bottom after new comment
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startReply(Comment c) {
    setState(() => _replyTo = c);
    _focusNode.requestFocus();
  }

  Future<void> _deleteComment(Comment c) async {
    final err = await CommentService.deleteComment(c.id);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err), backgroundColor: AppColors.error));
    }
  }

  /// Сэтгэгдлийг thread болгон бүлэглэх: эх сэтгэгдэл + доор нь reply-ууд
  Widget _buildCommentSliver(List<Comment> comments, String? me) {
    final tops = comments.where((c) => c.parentId == null).toList();
    final repliesByParent = <String, List<Comment>>{};
    for (final c in comments) {
      if (c.parentId != null) {
        repliesByParent.putIfAbsent(c.parentId!, () => []).add(c);
      }
    }
    // Орфан reply (эх нь устсан) — top болгож харуулна
    for (final c in comments) {
      if (c.parentId != null && !comments.any((t) => t.id == c.parentId)) {
        tops.add(c);
      }
    }
    tops.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Хавтгай жагсаалт: (comment, isReply)
    final flat = <(Comment, bool)>[];
    for (final t in tops) {
      flat.add((t, false));
      final replies = repliesByParent[t.id] ?? [];
      replies.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final r in replies) {
        flat.add((r, true));
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final (comment, isReply) = flat[i];
          return _CommentTile(
            comment:  comment,
            isOwn:    comment.userId == me,
            isReply:  isReply,
            onDelete: () => _deleteComment(comment),
            onReply:  () => _startReply(comment),
          );
        },
        childCount: flat.length,
      ),
    );
  }

  /// Өөрийн пост дээрх засах/устгах sheet (хуучин AppBar action-оос зөөсөн)
  void _openOwnOptions() {
    showPostOptionsSheet(
      context,
      postId: _post!.id,
      authorId: _post!.userId,
      authorUsername: _post!.author?.username?.replaceAll('@', '') ?? '',
      isOwn: true,
      currentCaption: _post!.caption,
      onEditCaption: (text) async {
        await ref.read(feedProvider.notifier)
            .editCaption(_post!.id, text);
        if (mounted) setState(() => _post = _post!.copyWith(caption: text));
      },
      onDelete: () async {
        final ok = await ref.read(feedProvider.notifier)
            .deletePost(_post!.id);
        if (!mounted || !context.mounted) return;
        if (ok) {
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй. Дахин оролдоно уу.'),
            backgroundColor: AppColors.error));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.postId));
    final me = SupabaseService.currentUser?.id;
    final myProfile = ref.watch(_myMiniProfileProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(children: [
        Column(children: [
          Expanded(
            child: CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
                // ── Post media (full-bleed) + sheet контент ──
                SliverToBoxAdapter(
                  child: _postLoading
                      ? const _PostHeaderSkeleton()
                      : _postError
                          ? Padding(
                              padding: const EdgeInsets.only(top: 72),
                              child: _PostErrorBox(onRetry: _fetchPost))
                          : _post == null
                              ? const SizedBox(
                                  height: 260,
                                  child: Center(child: Text('Пост олдсонгүй')))
                              : _PostHeader(
                                  post: _post!,
                                  // Header тоолуур realtime сэтгэгдлийн урсгалаас
                                  commentCount:
                                      commentsAsync.valueOrNull?.length,
                                  onLike: _toggleLike,
                                  onComment: () => _focusNode.requestFocus(),
                                ),
                ),

                // ── Comments header — жижиг том үсэг, tertiary (нэгдсэн хэв маяг) ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Row(children: [
                      Text('СЭТГЭГДЛҮҮД', style: AppTextStyles.sectionLabel),
                      const SizedBox(width: 8),
                      commentsAsync.when(
                        data: (c) => _CountBadge(count: c.length),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ]),
                  ),
                ),

                // ── Comments list ──
                commentsAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator(
                          color: AppColors.accentStart, strokeWidth: 2)),
                    ),
                  ),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Алдаа: $e',
                          style: AppTextStyles.bodyXs.copyWith(
                              color: AppColors.textTertiary)),
                    ),
                  ),
                  data: (comments) => comments.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 32, horizontal: 24),
                            child: Column(children: [
                              const Text('💬',
                                  style: TextStyle(fontSize: 36)),
                              const SizedBox(height: 12),
                              Text('Эхний сэтгэгдлийг үлдээгээрэй',
                                  style: AppTextStyles.bodyMd.copyWith(
                                      color: AppColors.textSecondary)),
                            ]),
                          ),
                        )
                      : _buildCommentSliver(comments, me),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),

          // ── Comment input ──
          _CommentInput(
            controller: _commentCtrl,
            focusNode:  _focusNode,
            sending:    _sending,
            onSend:     _sendComment,
            replyingTo: _replyTo?.author?.username,
            onCancelReply: () => setState(() => _replyTo = null),
            avatarUrl:  myProfile?['avatar_url'] as String?,
            initial: ((myProfile?['username'] as String?)?.trim().isNotEmpty == true
                    ? (myProfile!['username'] as String).trim()[0]
                    : SupabaseService.currentUser?.email?[0] ?? 'U')
                .toUpperCase(),
          ),
        ]),

        // ── Хөвөгч glass удирдлага — медиа дээгүүр давхарлана ──
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            _GlassCircleButton(
              icon: Icons.arrow_back_ios_new,
              onTap: () => context.pop(),
            ),
            const Spacer(),
            // Өөрийн пост (live бичлэг ч мөн адил)-ыг засах/устгах
            if (_post != null && _post!.userId == me)
              _GlassCircleButton(
                icon: Icons.more_horiz,
                onTap: _openOwnOptions,
              ),
          ]),
        )),
      ]),
    );
  }
}

// ─── Дарахад жижигрэх + hover cursor (веб мэдрэмж) ───
class _Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const _Press({required this.child, this.onTap, this.scale = 0.92});

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null
        ? SystemMouseCursors.basic : SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null : (_) => setState(() => _down = true),
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

// ─── Хөвөгч glass дугуй товч (back / more) ────────────────────────────────────
class _GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => _Press(
    scale: 0.9,
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: AppColors.hairline2),
        boxShadow: AppColors.shadowCard,
      ),
      child: Icon(icon, size: 17, color: Colors.white),
    ),
  );
}

// ─── Пост ачаалах skeleton ────────────────────────────────────────────────────
class _PostHeaderSkeleton extends StatelessWidget {
  const _PostHeaderSkeleton();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.5, end: 1.0),
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
    builder: (_, o, child) => Opacity(opacity: o, child: child),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Full-bleed медиа placeholder + доод талд sheet булан
      Stack(children: [
        Container(height: 340, width: double.infinity,
            color: AppColors.bgSurface),
        const Positioned(left: 0, right: 0, bottom: 0, child: _SheetCap()),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(children: [
          Container(width: 44, height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.bgSurface, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Container(width: 120, height: 12,
              decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(6))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Container(width: 160, height: 12,
            decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(6))),
      ),
    ]),
  );
}

// ─── Пост татахад алдаа гарсан (олдсонгүйгээс тусдаа) ─────────────────────────
class _PostErrorBox extends StatelessWidget {
  final VoidCallback onRetry;
  const _PostErrorBox({required this.onRetry});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 240,
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_outlined,
            color: AppColors.textTertiary, size: 40),
        const SizedBox(height: 12),
        Text('Алдаа гарлаа', style: AppTextStyles.labelLg),
        const SizedBox(height: 6),
        Text('Пост ачаалж чадсангүй',
            style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textTertiary)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.hairline),
            foregroundColor: AppColors.accentStart),
          child: const Text('Дахин оролдох'),
        ),
      ]),
    ),
  );
}

// ─── Sheet-ийн дээд булан — медиаг 28px давхарлан бүрхэж "хуудас" мэдрэмж өгнө ─
class _SheetCap extends StatelessWidget {
  const _SheetCap();

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    decoration: const BoxDecoration(
      color: AppColors.bgBase,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Center(
      child: Container(width: 44, height: 4,
          decoration: BoxDecoration(
            color: AppColors.hairline2,
            borderRadius: BorderRadius.circular(2))),
    ),
  );
}

// ─── Post header (media + actions + caption) ──────────────────────────────────
class _PostHeader extends ConsumerStatefulWidget {
  final Post post;
  final int? commentCount; // realtime тоолуур (null бол snapshot-оос)
  final VoidCallback onLike;
  final VoidCallback onComment;
  const _PostHeader({
    required this.post,
    this.commentCount,
    required this.onLike,
    required this.onComment,
  });

  @override
  ConsumerState<_PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends ConsumerState<_PostHeader> {
  bool? _savedOverride;

  bool get _saved => _savedOverride ??
      (ref.watch(savedPostIdsProvider).valueOrNull
              ?.contains(widget.post.id) ?? false);

  Future<void> _toggleSave() async {
    final was = _savedOverride ??
        (ref.read(savedPostIdsProvider).valueOrNull
                ?.contains(widget.post.id) ?? false);
    setState(() => _savedOverride = !was);
    HapticFeedback.lightImpact();
    final err = await SavedService.toggle(widget.post.id, was);
    if (!mounted) return;
    if (err != null) {
      setState(() => _savedOverride = was);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err), backgroundColor: AppColors.error));
      return;
    }
    ref.invalidate(savedPostIdsProvider);
    try { await ref.read(savedPostIdsProvider.future); } catch (_) {}
    if (mounted) setState(() => _savedOverride = null);
  }

  Future<void> _share() async {
    final link = '${Uri.base.origin}/post/${widget.post.id}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Холбоос хуулагдлаа 🔗'),
          duration: Duration(seconds: 2)));
    }
  }

  String _fmt(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  /// Full-bleed медиа (carousel / видео / зураг)
  Widget _media(Post post) {
    if (post.mediaUrls.length > 1) {
      return _DetailCarousel(urls: post.mediaUrls);
    }
    if (isVideoUrl(post.mediaUrl?.split('?').first)) {
      return NetworkVideo(url: post.mediaUrl!);
    }
    return CachedNetworkImage(
      imageUrl: post.mediaUrl!,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
          height: 360, color: AppColors.bgSurface),
      errorWidget: (_, __, ___) => Container(
        height: 300, color: AppColors.bgSurface,
        child: const Center(child: Text('📸',
            style: TextStyle(fontSize: 48))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final author = post.author;
    final hasMedia = post.mediaUrls.length > 1 || post.mediaUrl != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Media full-bleed + sheet булангийн давхарга ──
      if (hasMedia)
        Stack(children: [
          _media(post),
          // Дээд scrim — хөвөгч glass товчнууд цайвар медиа дээр ч тод харагдана
          Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(
            child: Container(height: 96,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent]))))),
          const Positioned(left: 0, right: 0, bottom: 0, child: _SheetCap()),
        ])
      else
        // Медиагүй пост — хөвөгч back товчны зай
        const SizedBox(height: 64),

      // ── Author row (sheet доторх эхний мөр) ──
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
        child: Row(children: [
          _Press(
            scale: 0.94,
            onTap: () => context.push('/creator/${post.userId}'),
            child: AppAvatar(
              imageUrl: author?.avatarUrl,
              initial:  author?.initial ?? '?',
              size: 44, showRing: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/creator/${post.userId}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(author?.username ?? '—', style: AppTextStyles.labelLg),
                    if (author?.isVerified == true) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified,
                          color: AppColors.accentStart, size: 14),
                    ],
                  ]),
                  if (post.venueName != null)
                    Row(children: [
                      const Icon(Icons.location_on,
                          size: 10, color: AppColors.accentStart),
                      const SizedBox(width: 2),
                      Text(post.venueName!,
                          style: AppTextStyles.bodyXs
                              .copyWith(color: AppColors.textSecondary)),
                    ]),
                ],
              ),
            ),
          )),
          // Хугацаа — micro pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline)),
            child: Text(post.timeAgo,
                style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textTertiary))),
        ]),
      ),

      // ── Action glass bar — like / comment / share / save ──
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline),
          boxShadow: AppColors.shadowCard,
        ),
        child: Row(children: [
          _Press(
            scale: 0.85,
            onTap: widget.onLike,
            child: Row(children: [
              Icon(
                post.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                color: post.isLikedByMe
                    ? AppColors.accentStart
                    : AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 6),
              Text(post.formattedLikes,
                  style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(width: 20),
          _Press(
            scale: 0.88,
            onTap: widget.onComment,
            child: Row(children: [
              const Icon(Icons.chat_bubble_outline,
                  color: AppColors.textSecondary, size: 22),
              const SizedBox(width: 6),
              Text(_fmt(widget.commentCount ?? post.commentsCount),
                  style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.textSecondary)),
            ]),
          ),
          const Spacer(),
          _Press(
            scale: 0.85,
            onTap: _share,
            child: const Icon(Icons.send_outlined,
                color: AppColors.textSecondary, size: 22),
          ),
          const SizedBox(width: 18),
          _Press(
            scale: 0.85,
            onTap: _toggleSave,
            child: Icon(_saved ? Icons.bookmark : Icons.bookmark_border,
                color: _saved
                    ? AppColors.accentStart : AppColors.textSecondary,
                size: 22),
          ),
        ]),
      ),

      // Caption
      if (post.caption?.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: RichText(
            text: TextSpan(style: AppTextStyles.bodyMd, children: [
              TextSpan(
                text: '${author?.username ?? ''} ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: post.caption),
            ]),
          ),
        )
      else
        const SizedBox(height: 14),

      const Divider(color: AppColors.hairline, height: 1),
    ]);
  }
}

// ─── Comment tile ─────────────────────────────────────────────────────────────
class _CommentTile extends StatefulWidget {
  final Comment comment;
  final bool isOwn;
  final bool isReply;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  const _CommentTile({
    required this.comment,
    required this.isOwn,
    this.isReply = false,
    required this.onDelete,
    required this.onReply,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  late bool _liked;
  late int _likes;

  @override
  void initState() {
    super.initState();
    _liked = widget.comment.isLikedByMe;
    _likes = widget.comment.likesCount;
  }

  @override
  void didUpdateWidget(_CommentTile old) {
    super.didUpdateWidget(old);
    // Stream шинэчлэгдвэл серверийн утгаар дахин тааруулна
    if (old.comment.likesCount != widget.comment.likesCount ||
        old.comment.isLikedByMe != widget.comment.isLikedByMe) {
      _liked = widget.comment.isLikedByMe;
      _likes = widget.comment.likesCount;
    }
  }

  Future<void> _toggleLike() async {
    final was = _liked;
    setState(() { _liked = !was; _likes += was ? -1 : 1; });
    final err = await CommentService.toggleLike(widget.comment.id, was);
    if (err != null && mounted) {
      setState(() { _liked = was; _likes += was ? 1 : -1; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final author = comment.author;
    // Мөрийн хэмнэл: avatar 34 (reply 28), зай 12
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.isReply ? 54 : 20, 10, 20, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Press(
          scale: 0.94,
          onTap: () => context.push('/creator/${comment.userId}'),
          child: AppAvatar(
            imageUrl: author?.avatarUrl,
            initial:  author?.initial ?? '?',
            size: widget.isReply ? 28 : 34,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(author?.username ?? '—',
                  style: AppTextStyles.labelSm),
              const SizedBox(width: 6),
              Text(comment.timeAgo,
                  style: AppTextStyles.bodyXs.copyWith(
                      color: AppColors.textTertiary)),
            ]),
            const SizedBox(height: 3),
            Text(comment.body,
                style: AppTextStyles.bodyMd.copyWith(height: 1.4)),
            const SizedBox(height: 4),
            Row(children: [
              _Press(
                scale: 0.95,
                onTap: widget.onReply,
                child: Text('Хариулах',
                    style: AppTextStyles.bodyXs.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              if (widget.isOwn) ...[
                const SizedBox(width: 16),
                _Press(
                  scale: 0.95,
                  onTap: () => _confirmDelete(context),
                  child: Text('Устгах',
                      style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.textTertiary)),
                ),
              ],
            ]),
          ]),
        ),
        // Like
        _Press(
          scale: 0.8,
          onTap: _toggleLike,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Column(children: [
              Icon(_liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? AppColors.accentStart : AppColors.textTertiary,
                  size: 16),
              if (_likes > 0) ...[
                const SizedBox(height: 2),
                Text('$_likes',
                    style: AppTextStyles.bodyXs.copyWith(
                        color: AppColors.textTertiary)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  void _confirmDelete(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Сэтгэгдэл устгах уу?',
                style: AppTextStyles.labelLg),
            const SizedBox(height: 8),
            Text('"${widget.comment.body.length > 60 ? '${widget.comment.body.substring(0, 60)}…' : widget.comment.body}"',
                style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.hairline)),
                  child: const Text('Болих'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); widget.onDelete(); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error),
                  child: const Text('Устгах'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─── Comment input bar ────────────────────────────────────────────────────────
class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final String? replyingTo;
  final VoidCallback onCancelReply;
  final String? avatarUrl;
  final String initial;
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    this.replyingTo,
    required this.onCancelReply,
    this.avatarUrl,
    this.initial = 'U',
  });

  @override
  Widget build(BuildContext context) {
    // Шилэн input bar — translucent дэвсгэр + дээшээ зөөлөн сүүдэр
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 8,
        top: replyingTo != null ? 0 : 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.92),
        border: const Border(top: BorderSide(color: AppColors.hairline)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18, spreadRadius: -4,
            offset: const Offset(0, -6)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Reply banner
      if (replyingTo != null)
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8, bottom: 6),
          child: Row(children: [
            const Icon(Icons.reply, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text('@$replyingTo-д хариулж байна',
                style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textSecondary))),
            _Press(
              onTap: onCancelReply,
              child: const Icon(Icons.close,
                  size: 16, color: AppColors.textTertiary)),
          ]),
        ),
      Row(children: [
        AppAvatar(
          imageUrl: avatarUrl,
          initial: initial,
          size: 32,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgSurface.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline),
            ),
            child: TextField(
              controller: controller,
              focusNode:  focusNode,
              maxLines:   4, minLines: 1,
              maxLength:  500,
              style: AppTextStyles.bodyMd,
              decoration: InputDecoration(
                hintText:     'Сэтгэгдэл бичих…',
                hintStyle:    AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textTertiary),
                border:       InputBorder.none,
                counterText:  '',
                isDense:      true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Press(
          scale: 0.88,
          onTap: sending ? null : onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38, height: 38,
            // Primary CTA — неон glow сүүдэр
            decoration: BoxDecoration(
              gradient: sending ? null : AppColors.accentGradient,
              color: sending ? AppColors.bgSurface : null,
              shape: BoxShape.circle,
              boxShadow: sending ? null : [
                BoxShadow(
                  color: AppColors.accentStart.withValues(alpha: 0.35),
                  blurRadius: 18, spreadRadius: -2),
              ],
            ),
            child: sending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        color: AppColors.accentStart, strokeWidth: 2))
                : const Icon(Icons.send_rounded,
                    color: Colors.white, size: 18),
          ),
        ),
      ]),
      ]),
    );
  }
}

// ─── Count badge ──────────────────────────────────────────────────────────────
class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.accentStart.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('$count',
        style: AppTextStyles.bodyXs.copyWith(
            color: AppColors.accentStart, fontWeight: FontWeight.w700)),
  );
}

// ─── Олон зурагтай пост carousel (detail) ───
class _DetailCarousel extends StatefulWidget {
  final List<String> urls;
  const _DetailCarousel({required this.urls});
  @override
  State<_DetailCarousel> createState() => _DetailCarouselState();
}

class _DetailCarouselState extends State<_DetailCarousel> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final url = widget.urls[i];
            if (isVideoUrl(url.split('?').first)) {
              return NetworkVideo(url: url, height: 400);
            }
            return CachedNetworkImage(
              imageUrl: url,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppColors.bgSurface),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.bgSurface,
                child: const Center(
                    child: Text('📸', style: TextStyle(fontSize: 48))),
              ),
            );
          },
        ),
        // Тоолуур — хөвөгч back товчтой давхцахгүй байрлалд
        Positioned(top: 64, right: 16, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Text('${_page + 1}/${widget.urls.length}',
            style: const TextStyle(color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w600)),
        )),
        // Цэгүүд — sheet булангийн дээгүүр харагдана
        Positioned(bottom: 40, left: 0, right: 0, child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.urls.length; i++)
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? Colors.white : Colors.white38),
              ),
          ],
        )),
      ]),
    );
  }
}
