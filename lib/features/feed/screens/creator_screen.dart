import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/router/app_router.dart' show AppRoutes;
import '../../auth/providers/auth_provider.dart' show currentProfileProvider;
import '../../profile/services/block_report_service.dart';
import '../../profile/widgets/block_report_sheet.dart';
import '../providers/feed_provider.dart';

class CreatorScreen extends ConsumerStatefulWidget {
  final String creatorId;
  const CreatorScreen({super.key, required this.creatorId});
  @override ConsumerState<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends ConsumerState<CreatorScreen> {
  static const _pageSize = 30;
  static const _cols = 'id, media_url, media_type, likes_count, created_at';
  // Reels таб — сервер талд шүүнэ. Live replay нь media_type='image' тул
  // өргөтгөлөөр ч шалгана (профайлын isVideoUrl-тай ижил дүрэм)
  static const _videoFilter = 'media_type.eq.video,'
      'media_url.ilike.%.mp4,media_url.ilike.%.webm,'
      'media_url.ilike.%.mov,media_url.ilike.%.m4v';

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _error = false;     // профайл татаж чадсангүй — retry харуулна
  int _loadGen = 0;        // давхар _load-ийн хуучин хариуг хаяна
  bool _isFollowing = false;
  bool _followLoading = false;
  bool _isBlocked = false;
  bool _unblocking = false;
  int _tab = 0; // 0 = Posts, 1 = Reels (профайлтай ижил icon таб)

  // Таб тус бүр өөрийн cursor хуудаслалттай (Reels нь анх нээхэд л татагдана)
  final _postsPager = _Pager();
  final _reelsPager = _Pager(reelsOnly: true);

  bool get _isMe => SupabaseService.currentUser?.id == widget.creatorId;

  bool _isVid(Map<String, dynamic> p) => p['media_type'] == 'video' ||
      isVideoUrl((p['media_url'] as String?)?.split('?').first);

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Буцах — shared линк / refresh-ээр орсон бол pop хийх юм байхгүй
  void _goBack() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_isMe ? AppRoutes.profile : AppRoutes.feed);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : null));
  }

  /// Профайл + дагалт + блок + постын эхний хуудас.
  /// [silent] — дахин ачааллахад алдааны toast гаргахгүй (буцаж ирэх үед).
  Future<void> _load({bool silent = false}) async {
    final gen = ++_loadGen;
    final me = SupabaseService.currentUser?.id;
    // Постын эхний хуудас профайлтай зэрэг татагдана — өөрийн retry-тэй
    final pages = Future.wait([
      _reloadPager(_postsPager),
      if (_reelsPager.touched) _reloadPager(_reelsPager),
    ]);
    try {
      final results = await Future.wait(<Future<dynamic>>[
        SupabaseService.client.from('profiles').select()
            .eq('id', widget.creatorId).maybeSingle(),
        if (me != null && me != widget.creatorId)
          SupabaseService.client.from('follows')
              .select('follower_id').eq('follower_id', me)
              .eq('following_id', widget.creatorId).maybeSingle()
        else
          Future<dynamic>.value(null),
        if (me != null && me != widget.creatorId)
          BlockReportService.isBlocked(widget.creatorId)
        else
          Future<dynamic>.value(false),
      ]);
      await pages;
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _profile     = results[0] as Map<String, dynamic>?;
        _isFollowing = results[1] != null;
        _isBlocked   = results[2] == true;
        _loading     = false;
        _error       = false;
      });
    } catch (_) {
      await pages; // _reloadPager өөрөө алдаагаа барьдаг
      if (!mounted || gen != _loadGen) return;
      if (_profile != null) {
        // Шинэчлэл бүтэлгүйтвэл байгаа өгөгдлөө хэвээр үлдээнэ
        setState(() => _loading = false);
        if (!silent) _toast('Шинэчилж чадсангүй');
      } else {
        // Хуурамч "User 0/0/0" биш — алдаа + "Дахин оролдох"
        setState(() { _loading = false; _error = true; });
      }
    }
  }

  /// Зөвхөн тоонуудыг серверээс дахин унших (дагах/жагсаалтаас буцах үед)
  Future<void> _refreshCounts() async {
    try {
      final row = await SupabaseService.client.from('profiles')
          .select('followers_count, following_count, posts_count')
          .eq('id', widget.creatorId).maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _profile = {...?_profile, ...row});
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchPage(
      _Pager pg, String? before) async {
    var q = SupabaseService.client.from('posts').select(_cols)
        .eq('user_id', widget.creatorId);
    if (pg.reelsOnly) q = q.or(_videoFilter);
    if (before != null) q = q.lt('created_at', before);
    final data = await q.order('created_at', ascending: false)
        .limit(_pageSize);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Эхний хуудсыг дахин татна — хуучин мөрүүд шинэ нь ирэх хүртэл харагдана
  Future<void> _reloadPager(_Pager pg) async {
    final gen = ++pg.gen;
    pg.touched = true;
    pg.loading = true;
    pg.error = false;
    try {
      final rows = await _fetchPage(pg, null);
      if (gen != pg.gen) return;
      pg.items
        ..clear()
        ..addAll(rows);
      pg.cursor = rows.isNotEmpty ? rows.last['created_at'] as String? : null;
      pg.hasMore = rows.length == _pageSize;
    } catch (_) {
      // Мөр байхгүй үед л алдаа (retry) — байвал хуучнаа хэвээр үлдээнэ
      if (gen == pg.gen && pg.items.isEmpty) pg.error = true;
    } finally {
      if (gen == pg.gen) {
        pg.loading = false;
        if (mounted) setState(() {});
      }
    }
  }

  /// Дараагийн хуудас (cursor = сүүлийн мөрийн created_at)
  Future<void> _loadMore(_Pager pg) async {
    if (pg.loading || !pg.hasMore || pg.error) return;
    final gen = pg.gen;
    pg.touched = true;
    pg.loading = true;
    try {
      final rows = await _fetchPage(pg, pg.cursor);
      if (gen != pg.gen) return;
      if (rows.isNotEmpty) pg.cursor = rows.last['created_at'] as String?;
      pg.hasMore = rows.length == _pageSize;
      pg.items.addAll(rows);
    } catch (_) {
      // Түр алдааг "дууссан" мэт харуулахгүй — footer-т retry
      if (gen == pg.gen) pg.error = true;
    } finally {
      if (gen == pg.gen) {
        pg.loading = false;
        if (mounted) setState(() {});
      }
    }
  }

  /// Post detail-аас буцахад — тухайн tile-г л шинэчилнэ (устгасан бол
  /// хасна, like тоо). Grid-ийг page1 болгож богиносгохгүй тул гулгалт хадгалагдана.
  Future<void> _syncTile(String id) async {
    try {
      final row = await SupabaseService.client.from('posts')
          .select('id, likes_count').eq('id', id).maybeSingle();
      if (!mounted) return;
      setState(() {
        for (final pg in [_postsPager, _reelsPager]) {
          if (row == null) {
            pg.items.removeWhere((p) => '${p['id']}' == id);
          } else {
            for (var i = 0; i < pg.items.length; i++) {
              if ('${pg.items[i]['id']}' == id) {
                pg.items[i] = {
                  ...pg.items[i], 'likes_count': row['likes_count']};
              }
            }
          }
        }
      });
      if (row == null) {
        ref.read(feedProvider.notifier).removeLocal(id);
        _refreshCounts();
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) {
      // Shared линкээр нэвтрээгүй орсон — чимээгүй биш, нэвтрэхийг санал болгоно
      _toast('Дагахын тулд нэвтэрнэ үү');
      context.push(AppRoutes.authLanding);
      return;
    }
    if (_followLoading) return;
    final was = _isFollowing;
    setState(() => _followLoading = true);
    try {
      if (was) {
        await SupabaseService.client.from('follows').delete()
            .eq('follower_id', me).eq('following_id', widget.creatorId);
      } else {
        await SupabaseService.client.from('follows')
            .insert({'follower_id': me, 'following_id': widget.creatorId});
      }
      if (!mounted) return;
      // Шууд ±1 харуулаад, серверийн яг тоогоор солино (trigger аль хэдийн ажилласан)
      final c = (_profile?['followers_count'] as num?)?.toInt() ?? 0;
      setState(() {
        _isFollowing = !was;
        _profile = {
          ...?_profile,
          'followers_count': was ? math.max(0, c - 1) : c + 1,
        };
      });
      ref.invalidate(currentProfileProvider); // миний "ДАГАЖ БУЙ" тоо
      await _refreshCounts();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.code == '23505') {
        // Аль хэдийн дагасан (эхний шалгалт алдаа өгсөн байж болно) — төлөвөө засна
        setState(() => _isFollowing = true);
        await _refreshCounts();
      } else {
        _toast(was ? 'Дагахаа болиулж чадсангүй' : 'Дагаж чадсангүй',
            error: true);
      }
    } catch (_) {
      _toast(was ? 'Дагахаа болиулж чадсангүй' : 'Дагаж чадсангүй',
          error: true);
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<void> _unblock() async {
    if (_unblocking) return;
    setState(() => _unblocking = true);
    final err = await BlockReportService.unblock(widget.creatorId);
    if (!mounted) return;
    setState(() {
      _unblocking = false;
      if (err == null) _isBlocked = false;
    });
    if (err == null) {
      ref.invalidate(blockedIdsProvider);
      _toast('Блок цуцлагдлаа');
    } else {
      _toast('Блок цуцалж чадсангүй', error: true);
    }
  }

  // Блоклосны дараа — feed-ээс түүний бүх постыг шууд арилгаад буцна
  void _onBlocked() {
    if (!mounted) return;
    ref.read(feedProvider.notifier).removeAuthor(widget.creatorId);
    ref.invalidate(blockedIdsProvider);
    setState(() => _isBlocked = true);
    _goBack();
  }

  /// Ачаалж буй / алдааны төлөв — буцах товч үргэлж харагдана
  Widget _shell(Widget body) => Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Stack(children: [
          Positioned.fill(child: body),
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _GlassRoundBtn(
                    icon: Icons.arrow_back_ios_new, onTap: _goBack),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _shell(const Center(
          child: CircularProgressIndicator(color: AppColors.accentStart)));
    }
    if (_error || _profile == null) {
      // Сүлжээний алдаа эсвэл устсан/байхгүй хэрэглэгч (хуучин shared линк)
      return _shell(Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: _error ? Icons.cloud_off_outlined : Icons.person_off_outlined,
            title: _error ? 'Ачаалж чадсангүй' : 'Хэрэглэгч олдсонгүй',
            subtitle: _error
                ? 'Интернэт холболтоо шалгаад дахин оролдоно уу'
                : 'Энэ хэрэглэгч устсан эсвэл холбоос буруу байна',
            action: _error
                ? GradientButton(
                    label: 'Дахин оролдох',
                    size: GradientButtonSize.md,
                    fullWidth: false,
                    borderRadius: 999,
                    onPressed: () {
                      setState(() { _loading = true; _error = false; });
                      _load();
                    })
                : null,
          ),
        ),
      ));
    }

    final username  = _profile?['username'] as String? ?? 'User';
    final handle    = username.replaceAll('@', '');
    final bio       = _profile?['bio'] as String?;
    final avatarUrl = _profile?['avatar_url'] as String?;
    final coverUrl  = _profile?['cover_url'] as String?;
    final initial   = handle.isNotEmpty ? handle[0].toUpperCase() : '?';
    final followers = (_profile?['followers_count'] as num?)?.toInt() ?? 0;
    final following = (_profile?['following_count'] as num?)?.toInt() ?? 0;
    // posts_count (trigger-ээр шинэчлэгддэг) — ачаалсан хуудсаас бага байж болохгүй
    final postsCount = math.max(
        (_profile?['posts_count'] as num?)?.toInt() ?? 0,
        _postsPager.items.length);
    final isMe = _isMe;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: RefreshIndicator(
          onRefresh: () => _load(),
          color: AppColors.accentStart,
          child: CustomScrollView(
            // Агуулга богино үед ч pull-to-refresh ажиллана
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Hero: бүтэн өргөн cover + голд давхарласан avatar (профайлтай ижил) ──
              SliverToBoxAdapter(
                child: Column(children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      _CreatorCover(url: coverUrl),
                      // Дээд бар — буцах + options, cover дээгүүр glass товч
                      Positioned(
                        top: 0, left: 0, right: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                            child: Row(children: [
                              _GlassRoundBtn(
                                icon: Icons.arrow_back_ios_new,
                                onTap: _goBack,
                              ),
                              const Spacer(),
                              if (isMe)
                                _GlassRoundBtn(
                                  icon: Icons.settings_outlined,
                                  onTap: () =>
                                      context.push(AppRoutes.settings),
                                )
                              else
                                _GlassRoundBtn(
                                  icon: Icons.more_horiz,
                                  onTap: () => showUserOptionsSheet(
                                    context,
                                    userId: widget.creatorId,
                                    username: handle,
                                    onBlocked: _onBlocked,
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ),
                      // Avatar 96 — cover-ийг -48 давхарлан голд, неон glow
                      Positioned(
                        bottom: -48,
                        child: Container(
                          width: 96, height: 96,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.bgBase,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.neonCyan
                                    .withValues(alpha: 0.30),
                                blurRadius: 24, spreadRadius: -2),
                              BoxShadow(
                                color: AppColors.magenta
                                    .withValues(alpha: 0.22),
                                blurRadius: 28, spreadRadius: -4),
                            ],
                          ),
                          child: AppAvatar(
                              imageUrl: avatarUrl,
                              initial: initial,
                              size: 88,
                              showRing: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                      // ── Нэр (голд, h2) + @handle eyebrow ──
                      Text(handle,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.h2),
                      const SizedBox(height: 4),
                      Text('@$handle',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelSm.copyWith(
                              color: AppColors.neonCyan,
                              letterSpacing: 1.2)),

                      // ── Bio (голд, 2 мөр) ──
                      if (bio != null && bio.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(bio,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.45)),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // ── Stats — нэг glass card, hairline хуваагчтай (профайлтай ижил) ──
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.hairline),
                          boxShadow: AppColors.shadowCard,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Row(children: [
                          Expanded(
                              child:
                                  _Stat(label: 'ПОСТ', value: postsCount)),
                          Container(
                              width: 1, height: 36, color: AppColors.hairline),
                          Expanded(
                              child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              // Жагсаалтаас буцахад тоог серверээс дахин уншина
                              onTap: () async {
                                await context.push(
                                    '/follows/${widget.creatorId}?tab=followers');
                                if (mounted) _refreshCounts();
                              },
                              child: _Stat(
                                  label: 'ДАГАГЧ',
                                  value: followers,
                                  gradient: true)),
                          )),
                          Container(
                              width: 1, height: 36, color: AppColors.hairline),
                          Expanded(
                              child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                await context.push(
                                    '/follows/${widget.creatorId}?tab=following');
                                if (mounted) _refreshCounts();
                              },
                              child:
                                  _Stat(label: 'ДАГАЖ БУЙ', value: following)),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 16),

                      // ── Action мөр — бүтэн өргөн pill товчнууд ──
                      if (isMe)
                        GradientButton(
                          label: 'Профайл засах',
                          height: 48,
                          borderRadius: 999,
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white, size: 16),
                          // /auth/setup биш — router бүртгэлтэйг feed рүү
                          // шиддэг. Буцахад шинэ bio/avatar-ыг чимээгүй ачаална.
                          onPressed: () async {
                            await context.push(AppRoutes.editProfile);
                            if (mounted) _load(silent: true);
                          },
                        )
                      else if (_isBlocked)
                        _BlockedNotice(busy: _unblocking, onUnblock: _unblock)
                      else
                        Row(children: [
                          // Дагах / Дагасан — gradient ↔ glass pill
                          Expanded(
                            child: _FollowBtn(
                                isFollowing: _isFollowing,
                                loading: _followLoading,
                                onTap: _toggleFollow),
                          ),
                          const SizedBox(width: 12),
                          // Мессеж — glass pill
                          Expanded(
                            child: _GlassPillBtn(
                              label: 'Мессеж',
                              icon: Icons.send_outlined,
                              onTap: () =>
                                  context.push('/dm/${widget.creatorId}'),
                            ),
                          ),
                        ]),
                      const SizedBox(height: 28),

                      // ── Icon-only таб (grid / reels) — профайлтай ижил underline ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _IconTab(
                              icon: Icons.grid_on,
                              selected: _tab == 0,
                              onTap: () => setState(() => _tab = 0)),
                          const SizedBox(width: 40),
                          _IconTab(
                              icon: Icons.play_arrow_rounded,
                              selected: _tab == 1,
                              onTap: () => setState(() => _tab = 1)),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ]),
              ),

              // ── Posts grid — нягт 2px завсартай, cursor хуудаслалттай ──
              ..._gridSlivers(isMe),
            ]),
      ),
    );
  }

  List<Widget> _gridSlivers(bool isMe) {
    final pg = _tab == 1 ? _reelsPager : _postsPager;
    final shown = pg.items;

    // Эхний хуудас алдаа өгсөн — хоосон төлөвтэй андуурахгүй, retry
    if (shown.isEmpty && pg.error && !pg.loading) {
      return [SliverToBoxAdapter(child: _retryBlock(pg))];
    }

    // Бүгд ачаалагдсан ч хоосон — өөрийнх бол хуваалцах CTA
    if (shown.isEmpty && !pg.hasMore && !pg.loading) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            illustration: _tab == 1
                ? 'assets/images/illustrations/empty_creator.svg'
                : 'assets/images/illustrations/empty_profile.svg',
            title: _tab == 1
                ? 'Бичлэг алга байна'
                : 'Пост алга байна',
            action: isMe
                ? GradientButton(
                    label: _tab == 1 ? 'Бичлэг хуваалцах' : 'Пост хуваалцах',
                    size: GradientButtonSize.md,
                    fullWidth: false,
                    borderRadius: 999,
                    onPressed: () async {
                      await context.push(_tab == 1
                          ? AppRoutes.createReel
                          : AppRoutes.createPost);
                      if (mounted) _load(silent: true);
                    })
                : null,
          )),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _tile(shown[i]),
            // Builder нь shown[i]-г уншдаг тул тоо нь ч shown-оос
            childCount: shown.length),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
        )),
      // Footer — SliverList дотор тул дэлгэцэнд ойртоход л build хийгдэнэ,
      // дараагийн хуудас гүйлгэж хүрэхэд татагдана (бүгдийг нэг дор биш)
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, __) => _footer(pg),
          childCount: 1)),
    ];
  }

  Widget _footer(_Pager pg) {
    if (pg.error) return _retryBlock(pg);
    if (!pg.hasMore) return const SizedBox(height: 24);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore(pg);
    });
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator(
          color: AppColors.accentStart, strokeWidth: 2)),
    );
  }

  // Татах алдааны retry — footer болон эхний хуудсанд
  Widget _retryBlock(_Pager pg) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_outlined,
            color: AppColors.textTertiary, size: 36),
        const SizedBox(height: 10),
        Text('Ачаалж чадсангүй',
            style: AppTextStyles.bodySm.copyWith(
                color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        GradientButton(
          label: 'Дахин оролдох',
          size: GradientButtonSize.md,
          fullWidth: false,
          borderRadius: 999,
          onPressed: () {
            setState(() => pg.error = false);
            pg.items.isEmpty ? _reloadPager(pg) : _loadMore(pg);
          },
        ),
      ]),
    ),
  );

  Widget _tile(Map<String, dynamic> p) {
    final id = '${p['id']}';
    final url = p['media_url'] as String?;
    final likes = (p['likes_count'] as num?)?.toInt() ?? 0;
    final isVid = url != null && _isVid(p);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () async {
        await context.push('/post/$id');
        // Буцахад устгасан/like өөрчлөгдсөн эсэхийг тусгана
        if (mounted) _syncTile(id);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(fit: StackFit.expand, children: [
          if (isVid)
            // Видеоны эхний кадрыг cover болгож харуулна
            // (профайлын grid-тэй ижил — posterOnly дарагдана)
            NetworkVideo(url: url,
                posterOnly: true, showPosterIcon: false)
          else if (url != null)
            CachedNetworkImage(
              imageUrl: url, fit: BoxFit.cover,
              memCacheWidth: 400,
              fadeInDuration:
                  const Duration(milliseconds: 150),
              placeholder: (_, __) =>
                  Container(color: AppColors.bgSurface),
              errorWidget: (_, __, ___) =>
                  Container(color: AppColors.bgSurface))
          else
            Container(color: AppColors.bgSurface),
          // Видео badge — баруун дээд (профайлтай ижил)
          // Медиа дээр тул горимоос үл хамааран харанхуй
          if (isVid)
            Positioned(
              top: 6, right: 6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.bgBaseDark
                      .withValues(alpha: 0.5),
                  border: Border.all(
                      color: AppColors.hairline2Dark),
                ),
                child: const Icon(Icons.videocam_rounded,
                    color: AppColors.neonCyanDark, size: 14),
              ),
            ),
          // Like тоо — 0 бол харуулахгүй (профайлтай ижил)
          if (likes > 0)
            Positioned(bottom: 6, left: 6,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.favorite,
                  color: Colors.white, size: 13),
                const SizedBox(width: 3),
                Text(_fmt(likes),
                  style: const TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 4,
                      color: Colors.black)])),
              ])),
        ]),
      ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n/1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Нэг табын cursor хуудаслалтын төлөв (Постууд / Reels тус тусдаа)
class _Pager {
  final bool reelsOnly;
  _Pager({this.reelsOnly = false});

  final List<Map<String, dynamic>> items = [];
  String? cursor;        // сүүлийн мөрийн created_at
  bool hasMore = true;
  bool loading = false;
  bool error = false;
  bool touched = false;  // нэг ч удаа татаж эхэлсэн эсэх (Reels lazy)
  int gen = 0;           // reload хийхэд хуучин хүсэлтийн хариуг хаяна
}

/// Блоклосон хэрэглэгчийн профайл дээр — Дагах/Мессежийн оронд
class _BlockedNotice extends StatelessWidget {
  final bool busy;
  final VoidCallback onUnblock;
  const _BlockedNotice({required this.busy, required this.onUnblock});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.block, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Та энэ хэрэглэгчийг блоклосон',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textSecondary)),
            ),
          ]),
          const SizedBox(height: 12),
          GradientButton(
            label: 'Блокоо цуцлах',
            size: GradientButtonSize.md,
            fullWidth: false,
            borderRadius: 999,
            busy: busy,
            onPressed: onUnblock,
          ),
        ]),
      );
}

/// Creator cover — бүтэн өргөн 160, доошоо bgBase руу уусна,
/// cover байхгүй бол неон gradient wash fallback.
class _CreatorCover extends StatelessWidget {
  final String? url;
  const _CreatorCover({required this.url});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        if (url != null && url!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            memCacheWidth: 900,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => Container(color: AppColors.bgSurface),
            errorWidget: (_, __, ___) => _fallback())
        else
          _fallback(),
        // Доод fade — void bg руу бүрэн уусаж avatar ялгарна
        // (дунд цэг = bgBase 40% — харанхуйд хуучин 0x66050505-тай ижил)
        DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              AppColors.bgBase.withValues(alpha: 0.4),
              AppColors.bgBase,
            ],
            stops: const [0.4, 0.75, 1.0]))),
      ]),
    );
  }

  // Неон wash — magenta дээрээс void bg руу уусна (хуучин header-ийн өнгө)
  Widget _fallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomCenter,
            colors: [
              AppColors.magenta.withValues(alpha: 0.22),
              AppColors.accentPurple.withValues(alpha: 0.10),
              AppColors.bgBase,
            ],
            stops: const [0.0, 0.45, 1.0])),
      );
}

/// Glass round button — cover дээгүүрх navigation товч
class _GlassRoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassRoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgBase.withValues(alpha: 0.55),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 19),
          ),
        ),
      );
}

// ─── Icon-only таб — сонгогдсон үед cyan underline glow bar 24×3 ───
// (профайлын дэлгэцтэй ижил харагдац — creator mirror)
class _IconTab extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _IconTab(
      {required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 24,
                  color:
                      selected ? AppColors.neonCyan : AppColors.textTertiary),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 24,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color:
                      selected ? AppColors.neonCyan : Colors.transparent,
                  boxShadow: selected
                      ? AppColors.glowShadow(AppColors.neonCyan)
                      : null,
                ),
              ),
            ]),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final bool gradient;
  const _Stat({required this.label, required this.value, this.gradient = false});
  @override
  Widget build(BuildContext context) {
    final numStyle = AppTextStyles.displaySm.copyWith(fontSize: 22, height: 1);
    final numWidget = gradient
        ? ShaderMask(
            shaderCallback: (r) => AppColors.accentGradient.createShader(r),
            child: Text(_fmt(value),
                style: numStyle.copyWith(color: Colors.white)),
          )
        : Text(_fmt(value), style: numStyle);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      numWidget,
      const SizedBox(height: 6),
      Text(label,
          style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textTertiary,
              fontSize: 10,
              letterSpacing: 1.2)),
    ]);
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n/1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n/1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Glass pill товч — бүтэн өргөн (Мессеж)
class _GlassPillBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _GlassPillBtn(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: AppColors.textPrimary),
              const SizedBox(width: 7),
              Text(label,
                  style: AppTextStyles.btn
                      .copyWith(color: AppColors.textPrimary)),
            ]),
          ),
        ),
      );
}

/// Дагах / Дагасан — бүтэн өргөн pill (gradient ↔ glass)
class _FollowBtn extends StatelessWidget {
  final bool isFollowing;
  final bool loading;
  final VoidCallback onTap;
  const _FollowBtn({
    required this.isFollowing,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filled = !isFollowing; // Дагах = gradient, Дагасан = glass
    return MouseRegion(
      cursor: loading ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? AppColors.accentGradient : null,
          color: filled ? null : AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: filled ? null : Border.all(color: AppColors.hairline2),
          // Primary үед неон glow
          boxShadow: filled
              ? AppColors.glowShadow(AppColors.accentStart)
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading)
            // Glass (Дагасан) төлөвт цагаан spinner цайвар дэвсгэр дээр алга болно
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2,
                  color: filled ? Colors.white : AppColors.textPrimary))
          else ...[
            Icon(isFollowing ? Icons.check : Icons.person_add_alt_1,
              size: 16, color: filled ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 7),
            Text(isFollowing ? 'Дагасан' : 'Дагах',
                style: AppTextStyles.btn.copyWith(
                    color: filled ? Colors.white : AppColors.textPrimary)),
          ],
        ]),
      )));
  }
}
