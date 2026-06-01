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
      final userId = SupabaseService.currentUser?.id;
      if (userId != null) {
        // Use RPC for isLikedByMe
        final data = await SupabaseService.client.rpc('get_feed_posts', params: {
          'p_user_id': userId,
          'p_limit':   1,
          'p_offset':  0,
        });
        final rows = (data as List).cast<Map<String, dynamic>>();
        final match = rows.where((r) => r['id'] == widget.postId).firstOrNull;
        if (match != null && mounted) {
          setState(() { _post = Post.fromJson(match); _postLoading = false; });
          return;
        }
      }
      // Fallback
      final raw = await SupabaseService.client
          .from('posts')
          .select('*, profiles!user_id (id, username, avatar_url, is_verified)')
          .eq('id', widget.postId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _post = raw != null ? Post.fromJson(raw as Map<String, dynamic>) : null;
          _postLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _postLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text;
    if (text.trim().isEmpty || _sending) return;

    setState(() => _sending = true);
    final err = await CommentService.addComment(
      postId: widget.postId,
      body:   text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

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
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _CommentTile(
                            comment: comments[i],
                            isOwn:   comments[i].userId == me,
                            onDelete: () => CommentService.deleteComment(
                                comments[i].id),
                          ),
                          childCount: comments.length,
                        ),
                      ),
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

      // Media — видео бол тоглуулна, эс бол зураг
      if (post.mediaUrl != null)
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
class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool isOwn;
  final VoidCallback onDelete;
  const _CommentTile({
    required this.comment,
    required this.isOwn,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => context.push('/creator/${comment.userId}'),
          child: AppAvatar(
            imageUrl: author?.avatarUrl,
            initial:  author?.initial ?? '?',
            size: 32,
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
          ]),
        ),
        if (isOwn)
          GestureDetector(
            onTap: () => _confirmDelete(context),
            child: const Padding(
              padding: EdgeInsets.only(left: 8, top: 2),
              child: Icon(Icons.delete_outline,
                  color: AppColors.textTertiary, size: 16),
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
            Text('"${comment.body.length > 60 ? '${comment.body.substring(0, 60)}…' : comment.body}"',
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
                  onPressed: () { Navigator.pop(ctx); onDelete(); },
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
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 8,
        top: 10, bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(children: [
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
      color: AppColors.accentStart.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('$count',
        style: AppTextStyles.bodyXs.copyWith(
            color: AppColors.accentStart, fontWeight: FontWeight.w700)),
  );
}
