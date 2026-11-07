import '../../../core/widgets/content_review_notice.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../discovery/services/discovery_service.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/saved_provider.dart';
import '../providers/reels_provider.dart';
import '../providers/feed_provider.dart';
import '../widgets/story_video.dart';
import '../../profile/utils/app_links.dart' show appOrigin;
import '../../profile/widgets/block_report_sheet.dart';

class ReelsScreen extends ConsumerStatefulWidget {
  final String? initialReelId;
  const ReelsScreen({super.key, this.initialReelId});
  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _reels = [];
  bool _loading = true;
  String? _error;
  bool _canCreate = false;
  final Set<String> _liked = {};
  final Set<String> _liking = {};
  final Set<String> _savedIds = {};
  final Set<String> _saving = {};
  final Set<String> _followingIds = {};
  bool _forYou = true; // Танд / Дагадаг таб
  final PageController _pageCtrl = PageController();
  int _page = 0; // идэвхтэй (харагдаж буй) reel — зөвхөн энэ дуутай тоглоно
  bool _covered = false; // дээр нь өөр дэлгэц нээгдсэн үед видео зогсоно
  bool _foreground = true;
  int _loadGeneration = 0;
  int _accountGeneration = 0;
  bool _metadataFailed = false;
  final Set<String> _changedLikes = {};
  // Browser autoplay бодлого — muted эхэлж, эхний товшилтоор дуу нээгдэнэ
  final ValueNotifier<bool> _muted = ValueNotifier<bool>(true);

  String get _myId => SupabaseService.currentUser?.id ?? '';

  List<Map<String, dynamic>> get _visible => _reels;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkOwner();
    _loadSaves();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageCtrl.dispose();
    _muted.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void didUpdateWidget(covariant ReelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialReelId != widget.initialReelId) {
      _forYou = true;
      _loading = true;
      _load();
    }
  }

  Future<void> _checkOwner() async {
    if (mounted) setState(() => _canCreate = _myId.isNotEmpty);
  }

  Future<void> _loadSaves() async {
    final account = _myId;
    try {
      final ids = await ref.read(savedPostIdsProvider.future);
      if (mounted &&
          account == _myId &&
          ref.read(sessionUserIdProvider) == account) {
        setState(() => _savedIds
          ..clear()
          ..addAll(ids));
      }
    } catch (_) {}
  }

  Future<void> _load({bool openNewest = false}) async {
    final generation = ++_loadGeneration;
    _liking.clear();
    if (openNewest) _forYou = true;
    final forYou = _forYou;
    final account = _myId;
    final session = SupabaseService.client.auth.currentSession;
    try {
      final provider = forYou ? reelsProvider : followingReelsProvider;
      final reels =
          (await ref.read(provider.future).timeout(const Duration(seconds: 15)))
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
      if (!mounted || generation != _loadGeneration) return;
      final selectedId = openNewest || !forYou ? null : widget.initialReelId;
      if (selectedId != null && !reels.any((r) => r['id'] == selectedId)) {
        final selected =
            await ReelsRepository(SupabaseService.client).find(selectedId);
        if (selected == null) {
          if (mounted && generation == _loadGeneration) {
            setState(() {
              _loading = false;
              _error = 'Энэ бичлэг устгагдсан эсвэл харах боломжгүй байна.';
            });
          }
          return;
        }
        reels.insert(0, selected);
      }
      if (!mounted || generation != _loadGeneration) return;
      final selectedIndex = reels.indexWhere((r) => r['id'] == selectedId);
      setState(() {
        _reels = reels;
        _page = selectedIndex < 0 ? 0 : selectedIndex;
        _loading = false;
        _error = null;
        _metadataFailed = false;
        _changedLikes.clear();
      });
      unawaited(_hydrateMetadata(generation, account, session));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _loadGeneration && _pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(_page);
        }
      });
    } catch (error) {
      // Сүлжээний алдааг "контент алга" гэж худал харуулахгүй
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _error = discoveryError(error);
        });
      }
    }
  }

  Future<void> _hydrateMetadata(
      int generation, String account, Object? session) async {
    if (account.isEmpty) return;
    bool current() =>
        mounted &&
        generation == _loadGeneration &&
        account == _myId &&
        ref.read(sessionUserIdProvider) == account &&
        identical(session, SupabaseService.client.auth.currentSession);
    Future<void> hydrate(bool likes) async {
      try {
        final rows = likes
            ? await SupabaseService.client
                .from('likes')
                .select('post_id')
                .eq('user_id', account)
                .inFilter(
                    'post_id', _reels.map((r) => r['id'] as String).toList())
                .timeout(const Duration(seconds: 10))
            : await SupabaseService.client
                .from('follows')
                .select('following_id')
                .eq('follower_id', account)
                .timeout(const Duration(seconds: 10));
        if (!current()) return;
        setState(() {
          if (likes) {
            final changed = {
              for (final id in _changedLikes) id: _liked.contains(id)
            };
            _liked
              ..clear()
              ..addAll(rows.map((r) => r['post_id'] as String));
            for (final entry in changed.entries) {
              entry.value ? _liked.add(entry.key) : _liked.remove(entry.key);
            }
          } else {
            _followingIds
              ..clear()
              ..addAll(rows.map((r) => r['following_id'] as String));
          }
        });
      } catch (_) {
        if (current()) setState(() => _metadataFailed = true);
      }
    }

    await Future.wait([hydrate(false), if (_reels.isNotEmpty) hydrate(true)]);
  }

  void _retryMetadata() {
    setState(() => _metadataFailed = false);
    unawaited(_hydrateMetadata(
        _loadGeneration, _myId, SupabaseService.client.auth.currentSession));
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    ref.invalidate(_forYou ? reelsProvider : followingReelsProvider);
    _load();
  }

  void _switchTab(bool forYou) {
    if (_forYou == forYou) return;
    setState(() {
      _forYou = forYou;
      _page = 0;
      _loading = true;
      _error = null;
    });
    // Recheck accepted follows before the server applies its video limit.
    if (!forYou) ref.invalidate(followingReelsProvider);
    _load();
  }

  // Дээр нь дэлгэц нээхдээ идэвхтэй видеог зогсооно (дуу нь цааш явахгүй)
  Future<void> _pushCovered(String route) async {
    final socialVersion = ref.read(socialVersionProvider);
    setState(() => _covered = true);
    try {
      await context.push(route);
      if (mounted && route == '/reels/create') {
        ref.invalidate(reelsProvider);
        ref.invalidate(followingReelsProvider);
        await _load(openNewest: true);
      } else if (mounted && socialVersion != ref.read(socialVersionProvider)) {
        setState(() {
          _loading = true;
          _error = null;
        });
        ref.invalidate(reelsProvider);
        ref.invalidate(followingReelsProvider);
        await _load();
      }
    } finally {
      if (mounted) setState(() => _covered = false);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final user = _myId;
    final session = SupabaseService.client.auth.currentSession;
    final accountGeneration = _accountGeneration;
    final generation = _loadGeneration;
    bool current() =>
        mounted &&
        accountGeneration == _accountGeneration &&
        generation == _loadGeneration &&
        user == _myId &&
        ref.read(sessionUserIdProvider) == user &&
        identical(session, SupabaseService.client.auth.currentSession);
    if (user.isEmpty || !current() || !_liking.add(id)) return;
    _changedLikes.add(id);
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
        await SupabaseService.client
            .from('likes')
            .delete()
            .eq('user_id', user)
            .eq('post_id', id);
      } else {
        await SupabaseService.client
            .from('likes')
            .insert({'user_id': user, 'post_id': id});
      }
      if (current()) {
        for (final provider in [feedProvider, followingFeedProvider]) {
          if (ref.exists(provider)) {
            ref
                .read(provider.notifier)
                .syncLikeState(id, !wasLiked, reel['likes_count'] as int? ?? 0);
          }
        }
      }
    } catch (_) {
      // Алдаа гарвал optimistic төлөвийг буцаана
      if (current()) {
        setState(() {
          if (wasLiked) {
            _liked.add(id);
            reel['likes_count'] = (reel['likes_count'] as int? ?? 0) + 1;
          } else {
            _liked.remove(id);
            reel['likes_count'] = (reel['likes_count'] as int? ?? 1) - 1;
          }
        });
      }
    } finally {
      if (current()) _liking.remove(id);
    }
  }

  Future<void> _toggleSave(String id) async {
    final account = _myId;
    if (account.isEmpty ||
        ref.read(sessionUserIdProvider) != account ||
        !_saving.add(id)) {
      return;
    }
    var wrote = false;
    try {
      if (ref.read(savedPostIdsProvider).hasError) {
        ref.invalidate(savedPostIdsProvider);
      }
      final saves = await ref.read(savedPostIdsProvider.future);
      if (!mounted ||
          account != _myId ||
          ref.read(sessionUserIdProvider) != account) {
        return;
      }
      final was = saves.contains(id);
      setState(() {
        was ? _savedIds.remove(id) : _savedIds.add(id);
      });
      final error = await SavedService.toggle(id, was);
      if (!mounted ||
          account != _myId ||
          ref.read(sessionUserIdProvider) != account) {
        return;
      }
      if (error != null) {
        setState(() {
          was ? _savedIds.add(id) : _savedIds.remove(id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: AppColors.error));
        return;
      }
      wrote = true;
      ref.invalidate(savedPostIdsProvider);
      final refreshed = await ref.read(savedPostIdsProvider.future);
      if (!mounted ||
          account != _myId ||
          ref.read(sessionUserIdProvider) != account) {
        return;
      }
      setState(() {
        refreshed.contains(id) ? _savedIds.add(id) : _savedIds.remove(id);
      });
      if (!was && refreshed.contains(id)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Хадгаллаа'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1)));
      }
    } catch (_) {
      if (mounted &&
          account == _myId &&
          ref.read(sessionUserIdProvider) == account) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(wrote ? savedPostRefreshError : savedPostReadError),
            backgroundColor: AppColors.error));
      }
    } finally {
      _saving.remove(id);
    }
  }

  Future<void> _follow(String userId) async {
    if (_myId.isEmpty || userId == _myId || _followingIds.contains(userId)) {
      return;
    }
    setState(() => _followingIds.add(userId));
    try {
      final result = await DiscoveryService().follow(userId, true);
      if (mounted && result != 'following') {
        setState(() => _followingIds.remove(userId));
      }
      ref.read(socialVersionProvider.notifier).state++;
    } catch (_) {
      if (mounted) {
        setState(() => _followingIds.remove(userId));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Дагаж чадсангүй'),
            backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _shareReel(Map<String, dynamic> reel) async {
    final link = '${appOrigin()}/#/post/${reel['id']}';
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Линк хуулагдлаа'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2)));
    }
  }

  // Sheet/диалог нь энгийн UI гадаргуу — theme-ийг дагана
  // (зөвхөн reels канвас өөрөө үргэлж харанхуй, *Dark const-ууд)
  Future<void> _moreSheet(Map<String, dynamic> reel) async {
    setState(() => _covered = true);
    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.bgElevated,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (s) => _themedNavBar(
            s,
            // The theme's drag handle (showDragHandle) is the grabber.
            SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading:
                      Icon(Icons.link_rounded, color: AppColors.textSecondary),
                  title: Text('Линк хуулах',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.textPrimary)),
                  onTap: () {
                    Navigator.pop(s);
                    _shareReel(reel);
                  }),
              ListTile(
                  leading:
                      const Icon(Icons.flag_outlined, color: AppColors.error),
                  title: Text('Мэдэгдэх',
                      style: AppTextStyles.bodyMd
                          .copyWith(color: AppColors.error)),
                  onTap: () {
                    Navigator.pop(s, 'report');
                  }),
              const SizedBox(height: 8),
            ]))),
      );
      if (action == 'report' && mounted) {
        await showReportSheet(context,
            targetType: 'post', targetId: reel['id'] as String);
      }
    } finally {
      if (mounted) setState(() => _covered = false);
    }
  }

  // Sheet theme-ийг дагадаг тул доод системийн дүрс ч дагана (reels region-ийг дарна)
  Widget _themedNavBar(BuildContext c, Widget child) {
    if (kIsWeb) return child;
    final dark = Theme.of(c).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
                systemNavigationBarContrastEnforced: false),
        child: child);
  }

  Future<void> _deleteReel(Map<String, dynamic> reel) async {
    final id = reel['id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Бичлэг устгах уу?', style: AppTextStyles.h3),
        content: Text('Энэ live/reel бичлэгийг бүрмөсөн устгана.',
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
    if (ok != true || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final deleted = await SupabaseService.client
          .from('posts')
          .delete()
          .eq('id', id)
          .eq('user_id', _myId)
          .select('id');
      if (!deleted.any((row) => row['id'] == id)) {
        throw StateError('The video was not deleted');
      }
      // A create-return refresh may still hold a snapshot containing this ID.
      // Its late response must not replace the confirmed local deletion.
      _loadGeneration++;
      container.invalidate(reelsProvider);
      container.invalidate(followingReelsProvider);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _reels.removeWhere((r) => r['id'] == id);
          _page = _visible.isEmpty ? 0 : _page.clamp(0, _visible.length - 1);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageCtrl.hasClients && _visible.isNotEmpty) {
            _pageCtrl.jumpToPage(_page);
          }
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Бичлэг устгагдлаа')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Устгаж чадсангүй'),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(savedPostIdsProvider, (_, next) {
      if (next.isLoading ||
          next.hasError ||
          !next.hasValue ||
          ref.read(sessionUserIdProvider) != _myId) {
        return;
      }
      setState(() {
        final pending = {for (final id in _saving) id: _savedIds.contains(id)};
        _savedIds
          ..clear()
          ..addAll(next.value!);
        for (final entry in pending.entries) {
          entry.value ? _savedIds.add(entry.key) : _savedIds.remove(entry.key);
        }
      });
    });
    ref.listen(sessionUserIdProvider, (_, __) {
      setState(() {
        _reels = [];
        _accountGeneration++;
        _liked.clear();
        _liking.clear();
        _saving.clear();
        _changedLikes.clear();
        _metadataFailed = false;
        _savedIds.clear();
        _followingIds.clear();
        _loading = true;
        _error = null;
        _canCreate = _myId.isNotEmpty;
      });
      _load();
      _loadSaves();
    });
    final visible = _visible;
    final canPlay = _foreground &&
        !_covered &&
        TickerMode.of(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final showState = !_loading && (_error != null || visible.isEmpty);
    final page = Scaffold(
      backgroundColor: Colors.black,
      body: showState
          ? Column(children: [
              _topControls(),
              Expanded(child: _error != null ? _errorView() : _empty(context)),
            ])
          : Stack(children: [
              if (_loading)
                const _ReelsSkeleton()
              else
                PageView.builder(
                  controller: _pageCtrl,
                  scrollDirection: Axis.vertical,
                  itemCount: visible.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final reel = visible[i];
                    final id = reel['id'] as String;
                    final uid = reel['user_id'] as String;
                    return _ReelPage(
                      key: ValueKey('reel-$id'),
                      reel: reel,
                      active: i == _page && canPlay,
                      muted: _muted,
                      liked: _liked.contains(id),
                      saved: _savedIds.contains(id),
                      following: uid == _myId || _followingIds.contains(uid),
                      isOwn: uid == _myId,
                      onLike: () => _toggleLike(reel),
                      onSave: () => _toggleSave(id),
                      onShare: () => _shareReel(reel),
                      onMore: () => _moreSheet(reel),
                      onFollow: () => _follow(uid),
                      onDelete: () => _deleteReel(reel),
                      onNavigate: _pushCovered,
                    );
                  },
                ),
              _topControls(),
            ]),
    );
    if (kIsWeb) return page;
    // Үргэлж харанхуй канвас — light горимд ч системийн дүрс цайвар
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false),
        child: page);
  }

  // The controls participate in layout on state screens; on video they overlay
  // the canvas. Their height may grow freely with accessibility text size.
  Widget _topControls() => SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact =
              constraints.maxWidth < (_metadataFailed ? 440 : 340) ||
                  MediaQuery.textScalerOf(context).scale(15) > 18;
          final leading = context.canPop()
              ? _GlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Буцах',
                  onTap: () => context.pop())
              : _canCreate
                  ? _GlassIconButton(
                      icon: Icons.add_box_outlined,
                      label: 'Бичлэг нэмэх',
                      onTap: () => _pushCovered('/reels/create'))
                  : const SizedBox(width: 44, height: 44);
          final tabs = _SegmentedTabs(forYou: _forYou, onChanged: _switchTab);
          final actions = [
            if (_metadataFailed)
              _GlassIconButton(
                icon: Icons.sync_problem,
                label: 'Үйлдлүүдийг дахин ачаалах',
                onTap: _retryMetadata,
              ),
            ValueListenableBuilder<bool>(
                valueListenable: _muted,
                builder: (_, muted, __) => _GlassIconButton(
                    icon: muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    label: muted ? 'Дуу асаах' : 'Дуу хаах',
                    onTap: () => _muted.value = !muted)),
            const SizedBox(width: 8),
            _GlassIconButton(
                icon: Icons.search,
                label: 'Хайх',
                onTap: () => _pushCovered('/search')),
          ];
          if (compact) {
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [leading, const Spacer(), ...actions]),
              const SizedBox(height: 4),
              tabs,
            ]);
          }
          return Row(children: [leading, Expanded(child: tabs), ...actions]);
        }),
      ));

  Widget _stateContent(List<Widget> children) => SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, constraints) {
          const padding = EdgeInsets.fromLTRB(24, 24, 24, 32);
          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - padding.vertical)
                      .clamp(0, double.infinity)),
              child: Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min, children: children)),
            ),
          );
        }),
      );

  Widget _errorView() => _stateContent([
        const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 64),
        const SizedBox(height: 16),
        Text('Ачаалж чадсангүй',
            textAlign: TextAlign.center,
            style: AppTextStyles.h2.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text(_error ?? '',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(color: Colors.white70)),
        const SizedBox(height: 20),
        GradientButton(
            label: 'Дахин оролдох',
            fullWidth: false,
            borderRadius: AppRadii.pill,
            onPressed: _retry),
      ]);

  Widget _empty(BuildContext context) {
    final followingEmpty = !_forYou;
    return _stateContent([
      Icon(
          followingEmpty
              ? Icons.person_search_outlined
              : Icons.explore_outlined,
          color: Colors.white38,
          size: 72),
      const SizedBox(height: 16),
      Text('Контент алга байна',
          textAlign: TextAlign.center,
          style: AppTextStyles.h2.copyWith(color: Colors.white)),
      const SizedBox(height: 8),
      Text(
          followingEmpty
              ? 'Дагасан хүмүүс бичлэг оруулаагүй байна'
              : _canCreate
                  ? 'Эхний бичлэгээ хуваалцаарай!'
                  : 'Нэвтэрч бичлэгээ хуваалцаарай',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMd.copyWith(color: Colors.white70)),
      if (_canCreate && !followingEmpty) ...[
        const SizedBox(height: 20),
        GradientButton(
            label: 'Бичлэг нэмэх',
            fullWidth: false,
            borderRadius: AppRadii.pill,
            onPressed: () => _pushCovered('/reels/create')),
      ],
      const SizedBox(height: 14),
      TextButton(
          onPressed: _retry,
          style: TextButton.styleFrom(
              foregroundColor: AppColors.neonCyanDark,
              minimumSize: const Size(0, 48)),
          child: const Text('Дахин ачаалах')),
    ]);
  }
}

// Дарахад жижигрэх + hover курсор — веб мэдрэмж
class _Pressable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool? toggled;
  const _Pressable(
      {required this.child, this.onTap, this.semanticLabel, this.toggled});

  @override
  Widget build(BuildContext context) => Semantics(
      container: true,
      label: semanticLabel,
      toggled: toggled,
      child: TextButton(
        onPressed: onTap,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          overlayColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused)
                  ? Colors.white30
                  : Colors.white12),
        ),
        child: ExcludeSemantics(excluding: semanticLabel != null, child: child),
      ));
}

/// Дугуй шилэн товч (хайлт / нэмэх) — neon hairline glass
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GlassIconButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: AppColors.bgElevatedDark.withValues(alpha: 0.72),
          side: const BorderSide(color: AppColors.hairline2Dark),
        ),
        icon: Icon(icon, color: Colors.white, size: 20),
      );
}

/// Text tabs retain their underline and wrap at accessibility text sizes.
class _SegmentedTabs extends StatelessWidget {
  final bool forYou;
  final ValueChanged<bool> onChanged;
  const _SegmentedTabs({required this.forYou, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab(context, 'Дагадаг', !forYou, () => onChanged(false)),
          const SizedBox(width: 8),
          _tab(context, 'Танд', forYou, () => onChanged(true)),
        ],
      );

  Widget _tab(BuildContext context, String label, bool active,
          VoidCallback onTap) =>
      Flexible(
          child: MergeSemantics(
              child: Semantics(
        selected: active,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              foregroundColor: Colors.white),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedDefaultTextStyle(
              duration: AppMotion.duration(
                  context, const Duration(milliseconds: 180)),
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.1,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 6)
                  ]),
              child: Text(label, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: AppMotion.duration(
                  context, const Duration(milliseconds: 180)),
              curve: Curves.easeOut,
              width: active ? 22 : 0,
              height: 3,
              decoration: BoxDecoration(
                  gradient: active ? AppColors.accentGradient : null,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ]),
        ),
      )));
}

class _ReelPage extends StatefulWidget {
  final Map<String, dynamic> reel;
  final bool active;
  final ValueNotifier<bool> muted;
  final bool liked;
  final bool saved;
  final bool following;
  final bool isOwn;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final VoidCallback onFollow;
  final VoidCallback? onDelete;
  final Future<void> Function(String route) onNavigate;
  const _ReelPage({
    super.key,
    required this.reel,
    this.active = true,
    required this.muted,
    required this.liked,
    required this.saved,
    required this.following,
    required this.onLike,
    required this.onSave,
    required this.onShare,
    required this.onMore,
    required this.onFollow,
    required this.onNavigate,
    this.isOwn = false,
    this.onDelete,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage>
    with SingleTickerProviderStateMixin {
  // Spinning music disc
  late final AnimationController _spin;
  // Видеоны бодит тоглуулах явц (0..1) — доод progress bar
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  // Товшилтоор түр зогсоох
  final ValueNotifier<bool> _paused = ValueNotifier<bool>(false);
  IconData? _flashIcon;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    _paused.addListener(_syncSpin);
  }

  void _syncSpin() {
    if (widget.active &&
        !_paused.value &&
        TickerMode.of(context) &&
        !AppMotion.reduced(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    // Дахин идэвхжихэд pause төлөвийг цэвэрлэнэ
    if (widget.active && !old.active) _paused.value = false;
    _syncSpin();
  }

  @override
  void dispose() {
    _paused.removeListener(_syncSpin);
    _spin.dispose();
    _progress.dispose();
    _paused.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  // Товшилт: эхлээд дуу нээнэ, дараа нь pause/play toggle
  void _tapVideo() {
    if (widget.muted.value) {
      widget.muted.value = false;
      _flash(Icons.volume_up_rounded);
    } else {
      _paused.value = !_paused.value;
      _flash(_paused.value ? Icons.pause_rounded : Icons.play_arrow_rounded);
    }
  }

  void _flash(IconData ic) {
    _flashTimer?.cancel();
    setState(() => _flashIcon = ic);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flashIcon = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final liked = widget.liked;
    final prof = reel['profiles'] as Map?;
    final username =
        (prof?['username'] as String? ?? 'User').replaceAll('@', '');
    final avatarUrl = prof?['avatar_url'] as String?;
    final caption = reel['caption'] as String? ?? '';
    final likes = reel['likes_count'] as int? ?? 0;
    final comments = reel['comments_count'] as int? ?? 0;
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final userId = reel['user_id'];
    // Доод зай: MainShell `extendBody: false` тул док body-ийн доор байрлаж,
    // shell дотор body-ийн padding.bottom = 0 (док нь home indicator-ийг
    // өөрөө агуулна). Shell-ээс гадуур нээгдвэл зөвхөн системийн доод зай
    // үлдэнэ. Аль ч тохиолдолд dockClearance дахин нэмэх шаардлагагүй.
    final dock = MediaQuery.of(context).padding.bottom;

    return Stack(fit: StackFit.expand, children: [
      // Видео (autoplay loop) — идэвхтэй reel л тоглоно, явцыг _progress руу
      GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tapVideo,
          child: StoryVideoView(
              url: reel['media_url'] as String,
              // Өндрийг MediaQuery-ээс таамаглахгүй — Stack(fit: expand) хуудасны
              // БОДИТ өндрийг өгнө. Таамаглал нь PageView-ийн жинхэнэ өндрөөс
              // зөрөхөд доод талд хар зурвас үлдээж байсан.
              height: null,
              loop: true,
              active: widget.active,
              paused: _paused,
              muted: widget.muted,
              progress: _progress)),

      // Дээд + доод скрим — олон зогсоолтой зөөлөн шилжилт (уншигдах байдал)
      const IgnorePointer(
          child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [
            Color(0x99000000),
            Color(0x33000000),
            Colors.transparent
          ],
                      stops: [
            0.0,
            0.5,
            1.0
          ])))),
      const IgnorePointer(
          child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [
            Color(0xE6000000),
            Color(0x66000000),
            Colors.transparent
          ],
                      stops: [
            0.0,
            0.55,
            1.0
          ])))),

      // Товшилтын feedback icon (дуу/pause)
      IgnorePointer(
          child: Center(
              child: AnimatedOpacity(
        opacity: _flashIcon != null ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle),
            child: Icon(_flashIcon ?? Icons.play_arrow_rounded,
                color: Colors.white, size: 40)),
      ))),

      // ── Баруун үйлдлийн рейл — TikTok маягийн босоо стек ──
      // Bounded below the top controls (search / mute row) and scaled down on
      // short screens or large text instead of running under them.
      Positioned(
          right: 10,
          top: MediaQuery.paddingOf(context).top + 92,
          bottom: dock + 14,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomCenter,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            // (1) Зохиогчийн avatar 44 — градиент ring + "+" badge → /creator/:id
            _Pressable(
              semanticLabel: '@$username профайл',
              onTap: () => widget.onNavigate('/creator/$userId'),
              child: SizedBox(
                width: 48,
                height: 54,
                child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.accentGradient,
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.neonCyanDark
                                    .withValues(alpha: 0.2),
                                blurRadius: 10),
                          ],
                        ),
                        child: AppAvatar(
                            imageUrl: avatarUrl,
                            initial: initial,
                            size: 40,
                            onDark: true),
                      ),
                      // "+" badge — дагаагүй үед л (дарахад шууд дагана)
                      if (!widget.following)
                        Positioned(
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.accentGradient,
                                border:
                                    Border.all(color: Colors.black, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                      color: AppColors.magenta
                                          .withValues(alpha: 0.7),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3)),
                                ],
                              ),
                              child: const Icon(Icons.add,
                                  color: Colors.white, size: 12),
                            ),
                          ),
                        ),
                    ]),
              ),
            ),
            const SizedBox(height: 18),

            // (2) LIKE 30 + шахсан тоолуур — magenta glow when liked
            _RailButton(
              icon: liked ? Icons.favorite : Icons.favorite_border,
              iconColor: liked ? AppColors.like : Colors.white,
              glow: liked ? AppColors.like : null,
              label: _fmtCount(likes),
              semanticLabel: 'Таалагдах, $likes',
              toggled: liked,
              onTap: widget.onLike,
            ),
            const SizedBox(height: 18),

            // (3) COMMENT 30 → /post/:id (reel-ийн дуу зогсоно)
            _RailButton(
              icon: Icons.mode_comment_outlined,
              label: _fmtCount(comments),
              semanticLabel: 'Сэтгэгдэл, $comments',
              onTap: () => widget.onNavigate('/post/${reel['id']}'),
            ),
            const SizedBox(height: 18),

            // (4) SHARE 30 — линк хуулна
            _RailButton(
              icon: Icons.send_outlined,
              label: 'Хуваалцах',
              onTap: widget.onShare,
            ),
            const SizedBox(height: 18),

            // (5) BOOKMARK — saved_posts руу хадгална
            _RailButton(
              icon: widget.saved ? Icons.bookmark : Icons.bookmark_border,
              iconColor: widget.saved ? AppColors.saved : Colors.white,
              glow: widget.saved ? AppColors.saved : null,
              label: 'Хадгалах',
              semanticLabel: widget.saved ? 'Хадгалснаас хасах' : 'Хадгалах',
              toggled: widget.saved,
              onTap: widget.onSave,
            ),
            const SizedBox(height: 18),

            // (6) MORE — линк хуулах / мэдэгдэх
            _RailButton(
                icon: Icons.more_horiz,
                semanticLabel: 'Бусад үйлдэл',
                size: 26,
                onTap: widget.onMore),

            // Өөрийн бичлэг (live/reel) бол устгах
            if (widget.isOwn) ...[
              const SizedBox(height: 18),
              _RailButton(
                icon: Icons.delete_outline,
                semanticLabel: 'Бичлэг устгах',
                iconColor: AppColors.error,
                size: 26,
                onTap: widget.onDelete,
              ),
            ],
            const SizedBox(height: 18),

            // Доод: эргэлддэг музикийн диск (creator avatar дотор)
            RotationTransition(
              turns: _spin,
              child: Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.bgSurfaceDark, AppColors.bgBaseDark]),
                  border: Border.all(color: AppColors.hairline2Dark),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 16),
                    BoxShadow(
                        color: AppColors.neonCyanDark.withValues(alpha: 0.2),
                        blurRadius: 14),
                  ],
                ),
                child: AppAvatar(
                    imageUrl: avatarUrl,
                    initial: initial,
                    size: 34,
                    onDark: true),
              ),
            ),
          ])))),

      // ── Доод зүүн: зохиогч + дагах pill + тайлбар + аудио мөр ──
      Positioned(
          left: 14,
          right: 84,
          bottom: dock + 16,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                  child: _Pressable(
                onTap: () => widget.onNavigate('/creator/$userId'),
                child: Text('@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.16,
                        shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
              )),
              const SizedBox(width: 10),
              // "Дагах" pill — primary градиент CTA → жинхэнэ follow (follows table)
              if (!widget.isOwn)
                widget.following
                    ? Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: AppColors.bgElevatedDark
                                .withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.hairline2Dark)),
                        child: Text('Дагасан',
                            style: AppTextStyles.labelMd.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700)))
                    : _Pressable(
                        onTap: widget.onFollow,
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: AppColors.accentGradient,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow:
                                AppColors.glowShadow(AppColors.accentStart),
                          ),
                          child: Text('Дагах',
                              style: AppTextStyles.labelMd.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
            ]),
            if (userId == SupabaseService.currentUser?.id)
              ContentReviewNotice(
                  status: reel['moderation_status'] as String? ?? 'approved',
                  onDark: true),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.5,
                      shadows: [Shadow(color: Colors.black, blurRadius: 5)])),
            ],
            if (reel['venue_ref'] is String) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => widget.onNavigate(
                    '/place/${Uri.encodeComponent(reel['venue_ref'] as String)}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.place_outlined,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        (reel['venue_catalog'] as Map?)?['name'] as String? ??
                            'Газрын дэлгэрэнгүй',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Аудио мөр — TikTok шиг note icon + гүйдэг (marquee) текст
            Row(children: [
              Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.16),
                      border: Border.all(color: Colors.white24)),
                  alignment: Alignment.center,
                  child: const Icon(Icons.music_note,
                      color: Colors.white, size: 13)),
              const SizedBox(width: 8),
              Flexible(
                  child: SizedBox(
                      height: 16,
                      child: _MusicMarquee(text: '@$username · эх дуу'))),
            ]),
          ])),

      // ── Доод нимгэн прогресс шугам — үзүүр рүүгээ тодрох glow tip ──
      Positioned(
          left: 0,
          right: 0,
          bottom: dock,
          child: IgnorePointer(
              child: Container(
            height: 2,
            color: Colors.white.withValues(alpha: 0.14),
            child: ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, p, __) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: p <= 0 ? 0.001 : p.clamp(0.0, 1.0),
                child: Container(
                    decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0x8022E7FF), AppColors.neonCyanDark]),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.neonCyanDark.withValues(alpha: 0.7),
                        blurRadius: 8),
                  ],
                )),
              ),
            ),
          ))),
    ]);
  }
}

/// Рейлийн нэг товч — TikTok хэмжээс (30) + neon drop-shadow + label + feedback
class _RailButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? glow;
  final String? label;
  final String? semanticLabel;
  final bool? toggled;
  final double size;
  final VoidCallback? onTap;
  const _RailButton({
    required this.icon,
    this.iconColor = Colors.white,
    this.glow,
    this.label,
    this.semanticLabel,
    this.toggled,
    this.size = 30,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      toggled: toggled,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: glow != null
              ? BoxDecoration(shape: BoxShape.circle, boxShadow: [
                  BoxShadow(
                      color: glow!.withValues(alpha: 0.85), blurRadius: 14),
                ])
              : null,
          child: Icon(icon, color: iconColor, size: size, shadows: const [
            Shadow(color: Colors.black54, blurRadius: 6),
          ]),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label!,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
        ],
      ]),
    );
  }
}

/// Тоолуурыг 1.2K / 3.4M хэлбэрт шахна (рейлийн label)
String _fmtCount(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v >= 10 ? v.round() : v.toStringAsFixed(1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v >= 10 ? v.round() : v.toStringAsFixed(1)}K';
  }
  return '$n';
}

/// Аудио мөрийн marquee — багтахгүй бол зүүн тийш тасралтгүй гүйнэ,
/// багтвал энгийн текстээр үлдэнэ (хоёр талдаа зөөлөн fade)
class _MusicMarquee extends StatefulWidget {
  final String text;
  const _MusicMarquee({required this.text});
  @override
  State<_MusicMarquee> createState() => _MusicMarqueeState();
}

class _MusicMarqueeState extends State<_MusicMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))
        ..repeat();

  static const double _gap = 36;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: Colors.white.withValues(alpha: 0.92),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        shadows: const [Shadow(color: Colors.black, blurRadius: 4)]);
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: TextDirection.ltr)
        ..layout();
      final textW = painter.width;
      // Багтаж байвал хөдөлгөөнгүй
      if (textW <= box.maxWidth) {
        return Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style));
      }
      final total = textW + _gap;
      return ClipRect(
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ], stops: [
            0.0,
            0.06,
            0.94,
            1.0
          ]).createShader(r),
          blendMode: BlendMode.dstIn,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Transform.translate(
              offset: Offset(-_c.value * total, 0),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.text, maxLines: 1, style: style),
                  const SizedBox(width: _gap),
                  Text(widget.text, maxLines: 1, style: style),
                  const SizedBox(width: _gap),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Ачаалах үеийн бүтэн дэлгэцийн skeleton (spinner-ийн оронд)
class _ReelsSkeleton extends StatefulWidget {
  const _ReelsSkeleton();
  @override
  State<_ReelsSkeleton> createState() => _ReelsSkeletonState();
}

class _ReelsSkeletonState extends State<_ReelsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _box(double w, double h, {BoxShape shape = BoxShape.rectangle}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: Colors.white10,
            shape: shape,
            borderRadius:
                shape == BoxShape.circle ? null : BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) =>
            Opacity(opacity: 0.45 + _c.value * 0.4, child: child),
        child: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                Color(0xFF14101f),
                Color(0xFF1e1630),
                Color(0xFF14101f)
              ]))),
          // Баруун рейлийн placeholder
          Positioned(
              right: 14,
              bottom: MediaQuery.of(context).padding.bottom + 14,
              child: Column(children: [
                for (var i = 0; i < 4; i++) ...[
                  _box(34, 34, shape: BoxShape.circle),
                  const SizedBox(height: 26),
                ],
              ])),
          // Доод зүүн: текстийн мөрүүд
          Positioned(
              left: 14,
              bottom: MediaQuery.of(context).padding.bottom + 16,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(120, 14),
                    const SizedBox(height: 10),
                    _box(220, 10),
                    const SizedBox(height: 8),
                    _box(160, 10),
                  ])),
        ]),
      );
}
