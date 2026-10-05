import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../models/story.dart';
import '../../../models/user_profile.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/providers/stories_provider.dart';
import '../../feed/screens/story_viewer_screen.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/image_uploader.dart';
import '../../../core/utils/image_compress.dart';
import '../../../core/utils/web_media_picker.dart';
import '../widgets/invite_sheet.dart';
import '../widgets/profile_header.dart';
import '../utils/app_links.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int _tab = 0; // 0 = Posts, 1 = Saved, 2 = Reels
  // pull-to-refresh-д grid-ийг re-key хийлгүй (spinner-гүй) чимээгүй шинэчлэх
  final _gridKey = GlobalKey<_PostsGridState>();
  bool _coverBusy = false;

  @override
  void initState() {
    super.initState();
    // Таб руу орох бүрт ПОСТ/дагагчийн тоог шинэчилнэ (өөр газар пост
    // нийтэлсэн/устгасан бол cache-лэгдсэн тоо хуучирсан байдаг).
    // Cache байгаа үед л — анхны ачааллыг хоёр дахин татахгүй.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(currentProfileProvider).hasValue) {
        ref.invalidate(currentProfileProvider);
      }
    });
  }

  // Профайл засах/үүсгэх — тусгай route (/auth/setup биш: router бүртгэлтэй
  // хэрэглэгчийг /feed руу буцаадаг байсан). Буцахад профайлыг дахин уншина.
  Future<void> _openEditProfile() async {
    await context.push(AppRoutes.editProfile);
    if (mounted) ref.invalidate(currentProfileProvider);
  }

  // Grid дээр пост устсан/шинэчлэгдсэн үед — ПОСТ тоо + feed-ийг зэрэгцүүлнэ
  void _onGridChanged([String? deletedId]) {
    ref.invalidate(currentProfileProvider);
    if (deletedId != null) {
      ref.read(feedProvider.notifier).removeLocal(deletedId);
    }
  }

  // Pull-to-refresh — алдаа гарвал console-д uncaught error биш snackbar
  Future<void> _onRefresh() async {
    ref.invalidate(storiesProvider);
    try {
      await Future.wait<void>([
        ref.refresh(currentProfileProvider.future),
        _gridKey.currentState?._refreshInPlace(notify: false) ??
            Future<void>.value(),
      ]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Шинэчилж чадсангүй'),
            backgroundColor: AppColors.error));
      }
    }
  }

  // Cover зураг солих — сонгоод шахаж upload хийгээд profiles.cover_url шинэчилнэ
  Future<void> _changeCover(String uid) async {
    if (_coverBusy) return;
    final bytes = await pickImageBytes();
    if (bytes == null || !mounted) return;
    setState(() => _coverBusy = true);
    try {
      final out = await compressToJpeg(bytes, maxDim: 1600);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = await ImageUploader.uploadBytes(
          bytes: out, bucket: 'avatars', path: '$uid/cover_$ts.jpg');
      if (url == null) throw Exception('upload failed');
      await SupabaseService.client
          .from('profiles')
          .update({'cover_url': url}).eq('id', uid);
      if (mounted) ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Нүүр зураг хадгалж чадсангүй'),
            backgroundColor: AppColors.error));
      }
    }
    if (mounted) setState(() => _coverBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final cached = profileAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: profileAsync.when(
        // Арын шинэчлэл алдаа өгвөл (ижил хэрэглэгчийн) cache-тэй профайлыг
        // үлдээнэ — бүтэн дэлгэцийн "Алдаа гарлаа" зөвхөн өгөгдөлгүй үед
        skipError:
            cached != null && cached.id == SupabaseService.currentUser?.id,
        loading: () =>
            const Center(child: OwlLoading(message: 'Профайлыг ачаалж байна')),
        error: (e, _) => Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: OwlLoading(
              state: OwlLoadingState.error,
              message: 'Профайлыг ачаалж чадсангүй',
              onRetry: () => ref.invalidate(currentProfileProvider)),
        )),
        data: (profile) {
          if (profile == null) {
            // Нэвтрээгүй (session дууссан/шууд холбоос) бол нэвтрэх рүү,
            // нэвтэрсэн ч profiles мөр байхгүй бол профайл үүсгэх form руу
            final loggedIn = SupabaseService.currentUser != null;
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SculptedIcon(Icons.person_outline_rounded,
                    color: AppColors.textTertiary, size: 48),
                const SizedBox(height: 16),
                Text(loggedIn ? 'Профайл олдсонгүй' : 'Нэвтрээгүй байна',
                    style: AppTextStyles.h2),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: loggedIn
                      ? _openEditProfile
                      : () => context.go(AppRoutes.authLanding),
                  child: Text(loggedIn ? 'Профайл үүсгэх' : 'Нэвтрэх'),
                ),
              ]),
            );
          }

          // Өөрийн идэвхтэй story (байвал avatar дээр ринг харагдана)
          final myRing = ref.watch(storiesProvider).maybeWhen<StoryRing?>(
                data: (rings) {
                  for (final r in rings) {
                    if (r.userId == profile.id) return r;
                  }
                  return null;
                },
                orElse: () => null,
              );

          return RefreshIndicator(
            color: AppColors.accentStart,
            backgroundColor: AppColors.bgElevated,
            onRefresh: _onRefresh,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                ...ScrollConfiguration.of(context).dragDevices,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              }),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                      child: ProfileHeader(
                    profile: profile,
                    avatar: _ProfileStoryAvatar(
                        avatarUrl: profile.avatarUrl,
                        initial: profile.initial,
                        ring: myRing),
                    coverBusy: _coverBusy,
                    onEdit: _openEditProfile,
                    onShare: () => _shareProfile(context, profile),
                    onEditCover: () => _changeCover(profile.id),
                    onSettings: () => context.push(AppRoutes.settings),
                    onActions: () => _showActions(profile),
                    onFollowers: () => _openFollows(profile.id, 'followers'),
                    onFollowing: () => _openFollows(profile.id, 'following'),
                  )),
                  SliverToBoxAdapter(
                      child: ProfileContentTabs(
                          selected: _tab,
                          onChanged: (tab) => setState(() => _tab = tab))),
                  SliverPadding(
                      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                      sliver: _PostsGrid(
                          key: _gridKey,
                          userId: profile.id,
                          savedOnly: _tab == 1,
                          reelsOnly: _tab == 2,
                          version: ref.watch(postsVersionProvider),
                          onChanged: _onGridChanged)),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.x4)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Профайл холбоосыг clipboard-д хуулах (одоо байгаа handler)
  Future<void> _shareProfile(BuildContext context, dynamic profile) async {
    HapticFeedback.lightImpact();
    // Жинхэнэ deploy origin-оос холбоос үүсгэнэ (өмнөх nightowl.ub үхмэл байсан)
    final link = profileLink(profile.id as String);
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Профайл холбоос хуулагдлаа 🔗 $link')));
    }
  }

  Future<void> _openFollows(String userId, String tab) async {
    await context.push('/follows/$userId?tab=$tab');
    if (mounted) ref.invalidate(currentProfileProvider);
  }

  Future<void> _showActions(UserProfile profile) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    leading: const SculptedIcon(Icons.ios_share),
                    title: const Text('Профайл хуваалцах'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _shareProfile(context, profile);
                    }),
                ListTile(
                    leading: const SculptedIcon(Icons.person_add_outlined),
                    title: const Text('Найзаа урих'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      showInviteSheet(context);
                    }),
                ListTile(
                    leading: const SculptedIcon(Icons.chat_bubble_outline),
                    title: const Text('Мессежүүд'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.push(AppRoutes.dmList);
                    }),
                ListTile(
                    leading: const SculptedIcon(Icons.bookmark_border),
                    title: const Text('Хадгалсан постууд'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.push(AppRoutes.saved);
                    }),
                ListTile(
                    leading: const SculptedIcon(Icons.storefront_outlined),
                    title: const Text('Бизнес самбар'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      context.push(AppRoutes.business);
                    }),
                if (profile.isAdmin)
                  ListTile(
                      leading: const SculptedIcon(Icons.shield_outlined),
                      title: const Text('Админ панел'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        context.push(AppRoutes.adminPanel);
                      }),
              ]))),
    );
  }
}

// ─── Posts grid (cursor pagination / infinite scroll) ───
class _PostsGrid extends StatefulWidget {
  final String userId;
  final bool reelsOnly;
  final bool savedOnly;

  /// postsVersionProvider — өөрчлөгдөхөд grid чимээгүй шинэчлэгдэнэ
  final int version;

  /// Пост устсан/шинэчлэгдсэн үед (ПОСТ тоо, feed-ийг зэрэгцүүлэх).
  /// Устгасан бол [deletedId] дамжина.
  final void Function([String? deletedId])? onChanged;
  const _PostsGrid({
    super.key,
    required this.userId,
    this.reelsOnly = false,
    this.savedOnly = false,
    this.version = 0,
    this.onChanged,
  });

  @override
  State<_PostsGrid> createState() => _PostsGridState();
}

class _PostsGridState extends State<_PostsGrid> {
  static const _pageSize = 30;
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _hasMore = true;
  bool _error = false; // татах алдаа — жагсаалт дуусснаас ялгаж retry үзүүлнэ
  DateTime? _cursor;
  int _loadedCount = 0;
  int _request = 0;
  // Ачаалал явж байхад ирсэн шинэчлэх хүсэлт — дууссаны дараа ажиллана
  bool _refreshQueued = false;
  bool _queuedNotify = false;
  // Web: tile дээр хулгана байхад браузерын context menu-г түр хаана
  // (баруун товчоор устгах dialog-той давхцахгүй)
  bool _browserMenuOff = false;

  static bool _isVid(String? url) => isVideoUrl(url);

  void _setBrowserMenu(bool enabled) {
    if (!kIsWeb || _browserMenuOff == !enabled) return;
    _browserMenuOff = !enabled;
    enabled
        ? BrowserContextMenu.enableContextMenu()
        : BrowserContextMenu.disableContextMenu();
  }

  @override
  void didUpdateWidget(covariant _PostsGrid old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId || old.savedOnly != widget.savedOnly) {
      // A new account or source cannot receive results from an older request.
      _request++;
      _posts.clear();
      _cursor = null;
      _hasMore = true;
      _loadedCount = 0;
      _loading = false;
      _error = false;
      _refreshQueued = false;
      _queuedNotify = false;
      _loadMore();
    } else if (old.version != widget.version) {
      _refreshInPlace();
    }
  }

  @override
  void dispose() {
    _request++;
    _setBrowserMenu(true);
    super.dispose();
  }

  // Профайлын постыг (live/reel/зураг) шууд устгах (удаан дарах / баруун товч)
  Future<void> _confirmDeleteTile(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Устгах уу?', style: AppTextStyles.h3),
        content: Text('Энэ пост/бичлэгийг бүрмөсөн устгана.',
            style:
                AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: Text('Болих',
                  style: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text('Устгах',
                  style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    try {
      // .select() — 0 мөр устсан (өөр tab-д аль хэдийн устгасан) эсэхийг ялгана
      final rows = (await SupabaseService.client
              .from('posts')
              .delete()
              .eq('id', id)
              .eq('user_id', me)
              .select('id, media_url, media_urls') as List)
          .cast<Map<String, dynamic>>();
      _removeMedia(rows);
      if (mounted) {
        setState(() => _posts.removeWhere((p) => p['id'] == id));
        widget.onChanged?.call(id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                rows.isEmpty ? 'Пост аль хэдийн устсан байна' : 'Устгагдлаа')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй'),
            backgroundColor: AppColors.error));
      }
    }
  }

  // Устгасан постын файлыг Storage API-аар цэвэрлэнэ (best-effort — алдааг
  // үл тоомсорлоно; posts бакетын биш URL (live replay г.м.) алгасна)
  Future<void> _removeMedia(List<Map<String, dynamic>> rows) async {
    const marker = '/object/public/posts/';
    final paths = <String>{};
    for (final r in rows) {
      final urls = (r['media_urls'] as List?)?.whereType<String>().toList() ??
          [if (r['media_url'] is String) r['media_url'] as String];
      for (final u in urls) {
        final i = u.indexOf(marker);
        if (i < 0) continue;
        final p = Uri.decodeComponent(
            u.substring(i + marker.length).split('?').first);
        if (p.isNotEmpty) paths.add(p);
      }
    }
    if (paths.isEmpty) return;
    try {
      await SupabaseService.client.storage.from('posts').remove(paths.toList());
    } catch (_) {/* файл үлдсэн ч пост устсан — хэрэглэгчид нөлөөгүй */}
  }

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    _error = false;
    final request = ++_request;
    final userId = widget.userId;
    final savedOnly = widget.savedOnly;
    try {
      final page = await _fetchPage(
          userId: userId,
          savedOnly: savedOnly,
          cursor: _cursor,
          limit: _pageSize);
      if (!_isCurrentRequest(request, userId, savedOnly)) return;
      _cursor = page.cursor;
      _hasMore = page.hasMore;
      _loadedCount += page.count;
      _posts.addAll(page.rows);
    } catch (_) {
      // Түр зуурын алдааг "жагсаалт дууссан" мэт бүү харагдуул — retry үзүүлнэ
      if (_isCurrentRequest(request, userId, savedOnly)) _error = true;
    } finally {
      if (_isCurrentRequest(request, userId, savedOnly)) {
        _loading = false;
        setState(() {});
        _runQueuedRefresh();
      }
    }
  }

  bool _isCurrentRequest(int request, String userId, bool savedOnly) =>
      mounted &&
      request == _request &&
      userId == widget.userId &&
      savedOnly == widget.savedOnly &&
      SupabaseService.currentUser?.id == userId;

  Future<
          ({
            List<Map<String, dynamic>> rows,
            DateTime? cursor,
            bool hasMore,
            int count
          })>
      _fetchPage(
          {required String userId,
          required bool savedOnly,
          required int limit,
          DateTime? cursor}) async {
    const columns = 'id, user_id, media_url, likes_count, created_at';
    if (!savedOnly) {
      var query = SupabaseService.client
          .from('posts')
          .select(columns)
          .eq('user_id', userId);
      if (cursor != null) {
        query = query.lt('created_at', cursor.toIso8601String());
      }
      final data =
          await query.order('created_at', ascending: false).limit(limit);
      final rows = (data as List).cast<Map<String, dynamic>>();
      return (
        rows: rows,
        cursor: rows.isEmpty
            ? null
            : DateTime.tryParse(rows.last['created_at'] as String? ?? ''),
        hasMore: rows.length == limit,
        count: rows.length
      );
    }
    var query = SupabaseService.client
        .from('saved_posts')
        .select('post_id, created_at')
        .eq('user_id', userId);
    if (cursor != null) {
      query = query.lt('created_at', cursor.toIso8601String());
    }
    final data = await query.order('created_at', ascending: false).limit(limit);
    final saves = (data as List).cast<Map<String, dynamic>>();
    final ids = saves
        .map((save) => save['post_id'])
        .whereType<String>()
        .toSet()
        .toList();
    final posts = ids.isEmpty
        ? <Map<String, dynamic>>[]
        : ((await SupabaseService.client
                .from('posts')
                .select(columns)
                .inFilter('id', ids)) as List)
            .cast<Map<String, dynamic>>();
    final byId = {for (final post in posts) post['id']: post};
    return (
      rows:
          ids.map((id) => byId[id]).whereType<Map<String, dynamic>>().toList(),
      cursor: saves.isEmpty
          ? null
          : DateTime.tryParse(saves.last['created_at'] as String? ?? ''),
      hasMore: saves.length == limit,
      count: saves.length
    );
  }

  void _runQueuedRefresh() {
    if (!_refreshQueued || !mounted) return;
    final notify = _queuedNotify;
    _refreshQueued = false;
    _queuedNotify = false;
    _refreshInPlace(notify: notify);
  }

  // Grid-ийг чимээгүй шинэчлэх (blank flash-гүй) — пост нийтлэх/устгах
  // (postsVersionProvider) болон pull-to-refresh. Хуучин мөрүүд харагдсаар
  // байгаад шинэ мөрүүд ирэхэд солигдоно. Ачаалсан тоогоо хадгалж татна —
  // 30-аар тасалж гулгалтын байрлалыг үсрүүлэхгүй.
  // [notify] — ПОСТ тоог дахин уншуулах (pull-to-refresh өөрөө уншдаг тул false).
  Future<void> _refreshInPlace({bool notify = true}) async {
    if (_loading) {
      _refreshQueued = true;
      _queuedNotify = _queuedNotify || notify;
      return;
    }
    _loading = true;
    _error = false;
    final request = ++_request;
    final userId = widget.userId;
    final savedOnly = widget.savedOnly;
    final limit = _loadedCount > _pageSize ? _loadedCount : _pageSize;
    try {
      final page =
          await _fetchPage(userId: userId, savedOnly: savedOnly, limit: limit);
      if (!_isCurrentRequest(request, userId, savedOnly)) return;
      _posts
        ..clear()
        ..addAll(page.rows);
      _cursor = page.cursor;
      _hasMore = page.hasMore;
      _loadedCount = page.count;
      if (notify && mounted) widget.onChanged?.call();
    } catch (_) {
      // Шинэчлэл бүтэлгүйтвэл хуучин мөрүүдийг хэвээр үлдээнэ (blank хийхгүй)
      if (_isCurrentRequest(request, userId, savedOnly)) _error = true;
    } finally {
      if (_isCurrentRequest(request, userId, savedOnly)) {
        _loading = false;
        setState(() {});
        _runQueuedRefresh();
      }
    }
  }

  // Detail-аас буцахад — зөвхөн тэр нэг мөрийг шинэчилнэ (устсан бол хасна).
  // Жагсаалтыг тасалдаггүй тул гулгалтын байрлал хадгалагдана.
  Future<void> _refreshOne(String id) async {
    if (widget.savedOnly) {
      await _refreshInPlace(notify: false);
      return;
    }
    final request = _request;
    final userId = widget.userId;
    try {
      final row = await SupabaseService.client
          .from('posts')
          .select('id, user_id, media_url, likes_count, created_at')
          .eq('id', id)
          .maybeSingle();
      if (!_isCurrentRequest(request, userId, false)) return;
      final i = _posts.indexWhere((p) => p['id'] == id);
      if (i < 0) return;
      setState(() {
        if (row == null) {
          _posts.removeAt(i);
        } else {
          _posts[i] = row;
        }
      });
      if (row == null) widget.onChanged?.call(id);
    } catch (_) {/* сүлжээний алдаа — хуучин tile хэвээр */}
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.reelsOnly
        ? _posts.where((p) => _isVid(p['media_url'] as String?)).toList()
        : _posts;

    // Эхний хуудас алдаа өгсөн бөгөөд хоосон бол — retry (хоосон төлөвтэй андуурахгүй)
    if (shown.isEmpty && _error && !_loading) {
      return SliverToBoxAdapter(child: _retryBlock());
    }

    // Хоосон (бүгд ачаалагдсан, алдаагүй) — artistic neon empty state
    if (shown.isEmpty && !_hasMore && !_loading && !_error) {
      return SliverToBoxAdapter(
        child: ProfileEmptyContent(
          kind: widget.savedOnly
              ? ProfileContentKind.saved
              : widget.reelsOnly
                  ? ProfileContentKind.videos
                  : ProfileContentKind.posts,
          onCreate: () => context.push(AppRoutes.createPost),
          onBrowse: () => context.go(AppRoutes.feed),
        ),
      );
    }

    return SliverMainAxisGroup(slivers: [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => _tile(shown[i]),
          childCount: shown.length,
        ),
      ),
      // Footer — алдаа/дуусаагүй байдлаас хамаарна
      SliverToBoxAdapter(
        child: _error
            ? _retryBlock()
            : _hasMore
                ? Builder(builder: (_) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _loadMore());
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: OwlLoading(
                              size: 40, message: 'Нийтлэлүүдийг ачаалж байна')),
                    );
                  })
                : const SizedBox(height: 24),
      ),
    ]);
  }

  // Татах алдааны retry блок — footer болон эхний хуудсанд ашиглана
  Widget _retryBlock() => Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
          child: OwlLoading(
              state: OwlLoadingState.error,
              size: 44,
              message: 'Нийтлэлүүдийг ачаалж чадсангүй',
              onRetry: () {
                _error = false;
                _loadMore();
              })));

  Widget _tile(Map<String, dynamic> post) {
    final mediaUrl = post['media_url'] as String?;
    final likes = post['likes_count'] as int? ?? 0;
    final isVideo = _isVid(mediaUrl);

    final id = post['id'] as String;
    final canDelete = !widget.savedOnly || post['user_id'] == widget.userId;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (canDelete) _setBrowserMenu(false);
      },
      onExit: (_) => _setBrowserMenu(true),
      child: GestureDetector(
        onTap: () async {
          await context.push('/post/$id');
          // Detail-аас буцахад зөвхөн энэ tile-ийг шинэчилнэ
          // (устгал/засварыг тусгана, гулгалт хадгалагдана)
          if (mounted) _refreshOne(id);
        },
        onLongPress: canDelete ? () => _confirmDeleteTile(id) : null,
        // Desktop web — баруун товчоор устгах
        onSecondaryTap: canDelete ? () => _confirmDeleteTile(id) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(fit: StackFit.expand, children: [
            if (mediaUrl != null && !isVideo)
              CachedNetworkImage(
                imageUrl: mediaUrl,
                fit: BoxFit.cover,
                memCacheWidth: 400, // grid thumbnail — жижиг decode, хурдан
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => Container(color: AppColors.bgSurface),
                errorWidget: (_, __, ___) => Container(
                    color: AppColors.bgSurface,
                    child: Center(
                        child: SculptedIcon(Icons.image_not_supported_outlined,
                            color: AppColors.textTertiary))),
              )
            else if (isVideo)
              // Видеоны эхний кадрыг cover болгож харуулна (icon-гүй — grid өөрөө
              // videocam badge нэмдэг; posterOnly нь pointerEvents=none тул дарагдана).
              NetworkVideo(
                  url: mediaUrl!, posterOnly: true, showPosterIcon: false)
            else
              Container(
                  color: AppColors.bgSurface,
                  child: Center(
                      child: SculptedIcon(Icons.image_outlined,
                          color: AppColors.textTertiary))),

            // Видео дээрх badge — медиа дээр тул горимоос үл хамааран харанхуй
            if (isVideo)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.bgBaseDark.withValues(alpha: 0.5),
                    border: Border.all(color: AppColors.hairline2Dark),
                  ),
                  child: const Center(
                      child: SculptedIcon(Icons.videocam_rounded,
                          color: Colors.white, size: 14, onDark: true)),
                ),
              ),

            if (likes > 0)
              Positioned(
                bottom: 6,
                left: 6,
                child: Row(children: [
                  const SculptedIcon(Icons.favorite,
                      color: Colors.white, size: 12, onDark: true),
                  const SizedBox(width: 3),
                  Text('$likes',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54)
                          ])),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

enum ProfileContentKind { posts, saved, videos }

class ProfileEmptyContent extends StatelessWidget {
  final ProfileContentKind kind;
  final VoidCallback onCreate;
  final VoidCallback onBrowse;
  const ProfileEmptyContent(
      {super.key,
      required this.kind,
      required this.onCreate,
      required this.onBrowse});

  @override
  Widget build(BuildContext context) => EmptyState(
      illustration: kind == ProfileContentKind.videos
          ? 'assets/images/illustrations/empty_creator.svg'
          : 'assets/images/illustrations/empty_profile.svg',
      title: switch (kind) {
        ProfileContentKind.posts => 'Эхний нийтлэлээ нэмээрэй',
        ProfileContentKind.saved => 'Хадгалсан нийтлэл алга',
        ProfileContentKind.videos => 'Бичлэг хараахан алга',
      },
      subtitle: switch (kind) {
        ProfileContentKind.posts =>
          'Таны хуваалцсан зураг, бичлэг энд харагдана.',
        ProfileContentKind.saved =>
          'Дуртай постын хадгалах товчийг дараарай. Хадгалсан нийтлэлүүд энд цугларна.',
        ProfileContentKind.videos =>
          'Постоор хуваалцсан бичлэгүүд тань энэ хэсэгт харагдана.',
      },
      action: GradientButton(
          label: kind == ProfileContentKind.saved
              ? 'Постууд үзэх'
              : 'Нийтлэл нэмэх',
          fullWidth: false,
          onPressed: kind == ProfileContentKind.saved ? onBrowse : onCreate));
}

/// Compact profile avatar with a thin violet ring; actual stories remain tappable.
class _ProfileStoryAvatar extends ConsumerWidget {
  final String? avatarUrl;
  final String initial;
  final StoryRing? ring;
  const _ProfileStoryAvatar({
    required this.avatarUrl,
    required this.initial,
    required this.ring,
  });

  // Өөрийн story-г үзэх — root navigator дээр (доод док/FAB viewer-ийг
  // дарахгүй), хаагдмагц үзсэн төлөвийг сэргээхийн тулд stories-г дахин уншина
  Future<void> _openViewer(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => StoryViewerScreen(rings: [ring!]),
        transitionsBuilder: (_, a, __, c) =>
            FadeTransition(opacity: a, child: c)));
    if (context.mounted) ref.invalidate(storiesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasStory = ring != null;
    return SizedBox(
        width: 96,
        height: 96,
        child: Stack(children: [
          Semantics(
              button: true,
              label: hasStory ? 'Өөрийн story үзэх' : 'Story нэмэх',
              child: GestureDetector(
                  onTap: hasStory
                      ? () => _openViewer(context, ref)
                      : () => context.push(AppRoutes.createStory),
                  child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                          width: 96,
                          height: 96,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.bgBase,
                              border: Border.all(
                                  width: 2,
                                  color: hasStory
                                      ? AppColors.silver
                                      : AppColors.accentStart)),
                          child: AppAvatar(
                              imageUrl: avatarUrl,
                              initial: initial,
                              size: 88))))),
          Positioned(
              right: 0,
              bottom: 0,
              child: IconButton(
                  tooltip: 'Story нэмэх',
                  onPressed: () => context.push(AppRoutes.createStory),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Container(
                      width: 27,
                      height: 27,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentStart,
                          border:
                              Border.all(color: AppColors.bgBase, width: 2)),
                      child: const Center(
                          child: SculptedIcon(Icons.add,
                              color: Colors.white, size: 17, onDark: true))))),
        ]));
  }
}
