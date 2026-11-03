import 'dart:async';
import '../../discovery/services/discovery_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/premium_surface.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';
// Хайлтын талбар нь DM-тэй нэг л хувилбар байхаар хуваалцсан widget
import '../../dm/widgets/search_field.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerId = ref.watch(sessionUserIdProvider);
    return _AccountSearch(key: ValueKey(ownerId), ownerId: ownerId);
  }
}

class _AccountSearch extends StatefulWidget {
  final String? ownerId;
  const _AccountSearch({super.key, required this.ownerId});
  @override
  State<_AccountSearch> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_AccountSearch> {
  bool get _active =>
      mounted && SupabaseService.currentUser?.id == widget.ownerId;
  int _searchVersion = 0;
  bool _exploreInFlight = false;
  final _ctrl = TextEditingController();
  // Query results start at the top, independent of the scrolled recovery state.
  final _resultsScroll = ScrollController(keepScrollOffset: false);
  String _q = '';
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _explore = [];
  bool _loading = false;
  bool _searchError = false;
  bool _exploreLoading = true;
  bool _exploreError = false;
  Timer? _debounce;

  // Тренд chip-үүд — статик түгээмэл хайлтын үгс (талбарыг л бөглөнө)
  static const _trends = [
    'Караоке',
    'Клуб',
    'Lounge',
    'Live хөгжим',
    'Pub',
    'Коктейль',
    'DJ',
  ];

  String get _myId => widget.ownerId ?? '';

  @override
  void initState() {
    super.initState();
    _loadExplore();
  }

  Future<void> _loadExplore() async {
    if (!_active || _exploreInFlight) return;
    _exploreInFlight = true;
    setState(() {
      _exploreLoading = _explore.isEmpty;
      _exploreError = false;
    });
    try {
      final data = await SupabaseService.client
          .from('posts')
          .select('id, media_url, likes_count')
          .order('created_at', ascending: false)
          .limit(30);
      if (_active) {
        setState(() {
          _explore = (data as List).cast<Map<String, dynamic>>();
          _exploreLoading = false;
        });
      }
    } catch (_) {
      // Чимээгүй алга болгохгүй — алдааны төлөв + дахин оролдох товч
      if (!_active) return;
      setState(() {
        _exploreLoading = false;
        _exploreError = _explore.isEmpty;
      });
    } finally {
      _exploreInFlight = false;
    }
  }

  // Товчлуур дарах бүрт query явуулахгүй — 300мс хүлээж debounce хийнэ
  void _search(String q) {
    if (!_active) return;
    final version = ++_searchVersion;
    setState(() {
      _q = q;
      _users = [];
      _venues = [];
    });
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _users = [];
        _venues = [];
        _loading = false;
        _searchError = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _searchError = false;
    });
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _runSearch(q, version));
  }

  // Тренд chip — талбарын текстийг л бөглөж, хэвийн хайлтын урсгалыг ажиллуулна
  void _applyTrend(String t) {
    _ctrl.text = t;
    _ctrl.selection = TextSelection.collapsed(offset: t.length);
    _search(t);
  }

  Future<void> _runSearch(String q, int version) async {
    if (!_active || version != _searchVersion) return;
    // PostgREST .or() filter-т таслал/хаалт орвол syntax эвдэрнэ — цэвэрлэнэ
    final cleaned = q.trim().replaceAll(RegExp(r'[,()%*\\]'), ' ').trim();
    final safe = cleaned.replaceAll('_', r'\_');
    if (cleaned.replaceAll('_', '').trim().isEmpty) {
      setState(() {
        _loading = false;
        _searchError = false;
      });
      return;
    }
    try {
      final u = await SupabaseService.client
          .from('profiles')
          .select('id, username, full_name, avatar_url, is_verified')
          .or('username.ilike.%$safe%,full_name.ilike.%$safe%')
          .eq('is_banned', false)
          .limit(20);
      if (!_active || version != _searchVersion) return;
      final v = await DiscoveryService().catalog(query: safe);
      // Race guard — хариу ирэхэд query өөрчлөгдсөн бол хуучин үр дүнг хаяна
      if (!_active || version != _searchVersion) return;
      setState(() {
        _users = (u as List)
            .cast<Map<String, dynamic>>()
            .where((p) => p['id'] != _myId)
            .toList();
        _venues = v.map((row) => {...row, 'id': row['ref']}).toList();
        _loading = false;
        _searchError = false;
      });
    } catch (_) {
      if (!_active || version != _searchVersion) return;
      setState(() {
        _loading = false;
        _searchError = true;
      });
    }
  }

  // Лайкийн тоог товчилно: 1200 → 1.2k
  String _fmtLikes(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _q.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
          child: Column(children: [
        // ── Header — glass back + том "Хайх" гарчиг ──
        NightOwlAtmosphere(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Row(children: [
            // Буцах — апп даяар нэг л хэлбэр (GlassIconButton)
            GlassIconButton(
                icon: Icons.chevron_left_rounded,
                iconSize: 24,
                tooltip: 'Буцах',
                // Deep link-ээр шууд орж ирсэн үед pop хийх юмгүй — feed рүү
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/feed');
                  }
                }),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Хайх', style: AppTextStyles.h1),
                  if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
                    const SizedBox(height: 3),
                    Text('Хүн, газар, шинэ мэдрэмж',
                        style: AppTextStyles.bodySm),
                  ],
                ])),
            const SizedBox(width: 8),
            const ThemeToggleButton(),
          ]),
        )),

        // ── Search — апп даяарх нэгдсэн шилэн pill талбар (48) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: SearchField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _search,
              hint: 'Хүн, газар хайх...'),
        ),

        Expanded(
            child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          child: searching
              ? KeyedSubtree(key: const ValueKey('results'), child: _results())
              : KeyedSubtree(
                  key: const ValueKey('discover'), child: _discover()),
        )),
      ])),
    );
  }

  // Trends and content share one scroll surface, including with the keyboard open.
  Widget _discover() => CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionLabel('Санал болгох хайлт'),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in _trends)
                  _Pressable(
                      onTap: () => _applyTrend(t),
                      borderRadius: 999,
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                              color:
                                  AppColors.bgElevated.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.hairline)),
                          // Галын icon — тренд мэдрэмж
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.north_east_rounded,
                                size: 16, color: AppColors.neonCyan),
                            const SizedBox(width: 6),
                            Flexible(
                                child: Text(t,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.labelMd.copyWith(
                                        color: AppColors.textSecondary))),
                          ]))),
              ])),
          const SizedBox(height: 10),
          _sectionLabel('Шинэ нийтлэлүүд'),
          _exploreGrid(),
        ]))
      ]);

  Widget _results() {
    // A new query owns its rows; old results cannot be tapped while loading.
    if (_loading && _users.isEmpty && _venues.isEmpty) {
      return const Center(child: OwlLoading(message: 'Илэрц хайж байна'));
    }
    if (_searchError) {
      return SingleChildScrollView(
          key: const PageStorageKey('search-error'),
          child: EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Хайж чадсангүй',
              subtitle: 'Холболтоо шалгаад дахин оролдоно уу.',
              action: GradientButton(
                  label: 'Дахин оролдох',
                  size: GradientButtonSize.md,
                  fullWidth: false,
                  onPressed: () => _search(_ctrl.text))));
    }
    if (_users.isEmpty && _venues.isEmpty) {
      // Хоосон төлөв — апп даяарх нэгдсэн EmptyState (icon хувилбар)
      return SingleChildScrollView(
          child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Илэрц олдсонгүй',
              subtitle: 'Нэрээ шалгах эсвэл илүү богино үгээр хайж үзээрэй.',
              action: TextButton.icon(
                onPressed: () {
                  _ctrl.clear();
                  _search('');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Хайлтыг цэвэрлэх'),
              )));
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: _loading ? 0.55 : 1,
      child: ListView(controller: _resultsScroll, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
            child: Text('${_users.length + _venues.length} илэрц',
                style: AppTextStyles.bodySm)),
        if (_users.isNotEmpty) ...[
          _sectionLabel('Хүмүүс'),
          for (final u in _users) _userTile(u),
        ],
        if (_venues.isNotEmpty) ...[
          _sectionLabel('Газрууд'),
          for (final v in _venues) _venueTile(v),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  // Хэсгийн гарчиг — uppercase sectionLabel + сунгасан hairline (нэгдсэн хэв)
  Widget _sectionLabel(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(children: [
        Expanded(child: Text(t, style: AppTextStyles.h3)),
        const SizedBox(width: 12),
        Container(
            width: 26,
            height: 3,
            decoration: BoxDecoration(
                color: AppColors.neonCyan.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(2))),
      ]));

  // Мөрүүд — DM жагсаалтын мөртэй ижил хэмнэлтэй (20/12, avatar 46)
  Widget _userTile(Map<String, dynamic> u) {
    final uname = (u['username'] as String? ?? 'User').replaceAll('@', '');
    return InkWell(
      onTap: () => context.push('/creator/${u['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          AppAvatar(
              imageUrl: u['avatar_url'] as String?,
              initial: uname.isNotEmpty ? uname[0].toUpperCase() : '?',
              size: 50),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Row(children: [
                  Flexible(
                      child: Text('@$uname',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelLg.copyWith(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700))),
                  if (u['is_verified'] == true) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.verified, color: AppColors.neonCyan, size: 14),
                  ],
                ]),
                if ((u['full_name'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(u['full_name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ])),
          Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
        ]),
      ),
    );
  }

  Widget _venueTile(Map<String, dynamic> v) => InkWell(
        onTap: () =>
            context.push('/place/${Uri.encodeComponent(v['id'] as String)}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            // Газрын icon — зөөлөн amber glass дугуй
            Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.accentStart.withValues(alpha: 0.10),
                    border: Border.all(color: AppColors.hairline2)),
                child: Center(
                    child: Icon(Icons.location_on_outlined,
                        color: AppColors.neonCyan, size: 23))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(v['name'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelLg.copyWith(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  if ((v['district'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(v['district'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ])),
            Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
          ]),
        ),
      );

  Widget _exploreGrid() {
    if (_exploreLoading && _explore.isEmpty) {
      // Skeleton grid — bare spinner-ээс илүү зөөлөн
      return _SkeletonGrid();
    }
    if (_exploreError) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off_rounded, size: 44, color: AppColors.textTertiary),
        const SizedBox(height: 10),
        Text('Алдаа гарлаа — дахин оролдоно уу',
            textAlign: TextAlign.center,
            style:
                AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        // Нэгдсэн primary CTA — GradientButton (md)
        GradientButton(
            label: 'Дахин оролдох',
            size: GradientButtonSize.md,
            fullWidth: false,
            onPressed: _loadExplore),
      ]));
    }
    if (_explore.isEmpty) {
      // Хоосон төлөв — апп даяарх нэгдсэн EmptyState (icon хувилбар)
      return const EmptyState(
          icon: Icons.photo_library_outlined,
          title: 'Пост алга байна',
          subtitle: 'Одоохондоо нээж үзэх контент алга.');
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: _explore.length,
      itemBuilder: (_, i) {
        final p = _explore[i];
        final url = p['media_url'] as String?;
        final isVideo = isVideoUrl(url);
        final likes = p['likes_count'] as int? ?? 0;
        return _Pressable(
          onTap: () => context.push('/post/${p['id']}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              if (url != null && !isVideo)
                AuthorizedImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 400, // grid thumbnail — жижиг decode, хурдан
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (_, __) =>
                        Container(color: AppColors.bgSurface),
                    errorWidget: (_, __, ___) => Container(
                        color: AppColors.bgSurface,
                        child: Icon(Icons.image_not_supported_outlined,
                            color: AppColors.textTertiary)))
              else if (isVideo && url != null)
                // Видеоны эхний кадрыг cover болгож харуулна (+ play icon)
                NetworkVideo(url: url, posterOnly: true)
              else
                Container(color: AppColors.bgSurface),
              // Доод scrim + лайкийн тоолуур (татсан likes_count-оо ашиглана)
              if (likes > 0)
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                        child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                  Colors.transparent,
                                  Colors.black54
                                ])),
                            child: Row(children: [
                              const Icon(Icons.favorite,
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(_fmtLikes(likes),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ])))),
            ]),
          ),
        );
      },
    );
  }
}

// ─── Дарахад агшдаг + web дээр hover cursor-той tappable wrapper ───
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  const _Pressable({
    required this.child,
    required this.onTap,
    this.borderRadius = 14,
  });
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _down = value),
            onFocusChange: (value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: AnimatedScale(
                scale: _down ? .98 : 1,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                // Paint above chip surfaces and media, which can cover ink.
                child: Container(
                  foregroundDecoration: _focused
                      ? BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(widget.borderRadius),
                          border:
                              Border.all(color: AppColors.neonCyan, width: 2),
                        )
                      : null,
                  child: widget.child,
                )),
          ),
        ),
      );
}

// ─── Explore grid-ийн skeleton ───
class _SkeletonGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomScrollView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child:
                      OwlLoading(size: 40, message: 'Постуудыг ачаалж байна'))),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: 12,
              itemBuilder: (_, __) => Container(
                  decoration: BoxDecoration(
                      color: AppColors.isDarkMode
                          ? AppColors.bgElevated
                          : AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(14))),
            ),
          ),
        ],
      );
}
