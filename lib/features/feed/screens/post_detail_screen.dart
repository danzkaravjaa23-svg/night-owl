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
import '../../profile/widgets/block_report_sheet.dart';

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
      if (mounted) setState(() => _postLoading = false);
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
            onDelete: () => CommentService.deleteComment(comment.id),
            onReply:  () => _startReply(comment),
          );
        },
        childCount: flat.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsProvider(widget.postId));
    final me = SupabaseService.currentUser?.id;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text('Пост', style: AppTextStyles.h2),
        centerTitle: true,
        actions: [
          // Өөрийн пост (live бичлэг ч мөн адил)-ыг засах/устгах
          if (_post != null && _post!.userId == me)
            IconButton(
              icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
              onPressed: () => showPostOptionsSheet(
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
                  if (!mounted) return;
                  if (ok) {
                    context.pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Устгаж чадсангүй. Дахин оролдоно уу.'),
                      backgroundColor: AppColors.error));
                  }
                },
              ),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              // ── Post media + info ──
              SliverToBoxAdapter(
                child: _postLoading
                    ? const SizedBox(
                        height: 340,
                        child: Center(child: CircularProgressIndicator(
                            color: AppColors.accentStart, strokeWidth: 2)))
                    : _post == null
                        ? const SizedBox(
                            height: 200,
                            child: Center(child: Text('Пост олдсонгүй')))
                        : _PostHeader(
                            post: _post!,
                            onLike: () {
                              ref.read(feedProvider.notifier)
                                  .toggleLike(_post!.id);
                              setState(() {
                                _post = _post!.copyWith(
                                  isLikedByMe: !_post!.isLikedByMe,
                                  likesCount: _post!.likesCount +
                                      (_post!.isLikedByMe ? -1 : 1),
                                );
                              });
                            },
                          ),
              ),

              // ── Comments header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(children: [
                    Text('Сэтгэгдлүүд', style: AppTextStyles.labelMd),
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
        ),
      ]),
    );
  }
}

// ─── Post header (media + actions + caption) ──────────────────────────────────
class _PostHeader extends StatelessWidget {
  final Post post;
  final VoidCallback onLike;
  const _PostHeader({required this.post, required this.onLike});

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Author
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          GestureDetector(
            onTap: () => context.push('/creator/${post.userId}'),
            child: AppAvatar(
              imageUrl: author?.avatarUrl,
              initial:  author?.initial ?? '?',
              size: 40, showRing: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(author?.username ?? '—', style: AppTextStyles.labelMd),
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
          )),
          Text(post.timeAgo,
              style: AppTextStyles.bodyXs.copyWith(
                  color: AppColors.textTertiary)),
        ]),
      ),

      // Media — олон зураг бол carousel, видео бол тоглуулна, эс бол зураг
      if (post.mediaUrls.length > 1)
        _DetailCarousel(urls: post.mediaUrls)
      else if (post.mediaUrl != null)
        isVideoUrl(post.mediaUrl)
          ? NetworkVideo(url: post.mediaUrl!)
          : CachedNetworkImage(
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
            ),

      // Actions
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(children: [
          GestureDetector(
            onTap: onLike,
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
          const SizedBox(width: 18),
          Row(children: [
            const Icon(Icons.chat_bubble_outline,
                color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 6),
            Text(post.formattedComments,
                style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.textSecondary)),
          ]),
        ]),
      ),

      // Caption
      if (post.caption?.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: RichText(
            text: TextSpan(style: AppTextStyles.bodyMd, children: [
              TextSpan(
                text: '${author?.username ?? ''} ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: post.caption),
            ]),
          ),
        ),

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
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.isReply ? 48 : 16, 10, 16, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => context.push('/creator/${comment.userId}'),
          child: AppAvatar(
            imageUrl: author?.avatarUrl,
            initial:  author?.initial ?? '?',
            size: widget.isReply ? 26 : 32,
          ),
        ),
        const SizedBox(width: 10),
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
              GestureDetector(
                onTap: widget.onReply,
                child: Text('Хариулах',
                    style: AppTextStyles.bodyXs.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              if (widget.isOwn) ...[
                const SizedBox(width: 16),
                GestureDetector(
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
        GestureDetector(
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    this.replyingTo,
    required this.onCancelReply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 8,
        top: replyingTo != null ? 0 : 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Reply banner
      if (replyingTo != null)
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 8, bottom: 6),
          child: Row(children: [
            Icon(Icons.reply, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: Text('@$replyingTo-д хариулж байна',
                style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textSecondary))),
            GestureDetector(
              onTap: onCancelReply,
              child: const Icon(Icons.close,
                  size: 16, color: AppColors.textTertiary)),
          ]),
        ),
      Row(children: [
        AppAvatar(
          imageUrl: null,
          initial: SupabaseService.currentUser?.email?[0].toUpperCase() ?? 'U',
          size: 32,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(24),
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
        GestureDetector(
          onTap: sending ? null : onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38, height: 38,
            decoration: BoxDecoration(
              gradient: sending ? null : AppColors.accentGradient,
              color: sending ? AppColors.bgSurface : null,
              shape: BoxShape.circle,
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
      height: 380,
      child: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final url = widget.urls[i];
            if (isVideoUrl(url)) return NetworkVideo(url: url, height: 380);
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
        Positioned(top: 12, right: 12, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Text('${_page + 1}/${widget.urls.length}',
            style: const TextStyle(color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.w600)),
        )),
        Positioned(bottom: 12, left: 0, right: 0, child: Row(
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
