import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/services/supabase_service.dart';
// Хайлтын талбар нь DM-тэй нэг л хувилбар байхаар хуваалцсан widget
import '../../dm/widgets/search_field.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
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
    'Караоке', 'Клуб', 'Lounge', 'Live хөгжим', 'Pub', 'Коктейль', 'DJ',
  ];

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _loadExplore();
  }

  Future<void> _loadExplore() async {
    if (mounted) setState(() { _exploreLoading = _explore.isEmpty; _exploreError = false; });
    try {
      final data = await SupabaseService.client.from('posts')
          .select('id, media_url, likes_count')
          .order('created_at', ascending: false).limit(30);
      if (mounted) {
        setState(() {
          _explore = (data as List).cast<Map<String, dynamic>>();
          _exploreLoading = false;
        });
      }
    } catch (_) {
      // Чимээгүй алга болгохгүй — алдааны төлөв + дахин оролдох товч
      if (mounted) setState(() { _exploreLoading = false; _exploreError = _explore.isEmpty; });
    }
  }

  // Товчлуур дарах бүрт query явуулахгүй — 300мс хүлээж debounce хийнэ
  void _search(String q) {
    setState(() { _q = q; });
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _users = []; _venues = []; _loading = false; _searchError = false; });
      return;
    }
    setState(() { _loading = true; _searchError = false; });
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  // Тренд chip — талбарын текстийг л бөглөж, хэвийн хайлтын урсгалыг ажиллуулна
  void _applyTrend(String t) {
    _ctrl.text = t;
    _ctrl.selection = TextSelection.collapsed(offset: t.length);
    _search(t);
  }

  Future<void> _runSearch(String q) async {
    // PostgREST .or() filter-т таслал/хаалт орвол syntax эвдэрнэ — цэвэрлэнэ
    final safe = q.trim().replaceAll(RegExp(r'[,()]'), ' ');
    try {
      final u = await SupabaseService.client.from('profiles')
          .select('id, username, full_name, avatar_url, is_verified')
          .or('username.ilike.%$safe%,full_name.ilike.%$safe%')
          .eq('is_banned', false).limit(20);
      final v = await SupabaseService.client.from('venues')
          .select('id, name, district, venue_type')
          .ilike('name', '%$safe%').limit(20);
      // Race guard — хариу ирэхэд query өөрчлөгдсөн бол хуучин үр дүнг хаяна
      if (!mounted || q.trim() != _ctrl.text.trim()) return;
      setState(() {
        _users = (u as List).cast<Map<String, dynamic>>().where((p) => p['id'] != _myId).toList();
        _venues = (v as List).cast<Map<String, dynamic>>();
        _loading = false;
        _searchError = false;
      });
    } catch (_) {
      if (!mounted || q.trim() != _ctrl.text.trim()) return;
      setState(() { _loading = false; _searchError = true; });
    }
  }

  // Лайкийн тоог товчилно: 1200 → 1.2k
  String _fmtLikes(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  void dispose() { _debounce?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final searching = _q.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(child: Column(children: [
        // ── Header — glass back + том "Хайх" гарчиг ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(children: [
            // Буцах — апп даяар нэг л хэлбэр (GlassIconButton)
            GlassIconButton(
              icon: Icons.chevron_left_rounded, iconSize: 24,
              tooltip: 'Буцах',
              // Deep link-ээр шууд орж ирсэн үед pop хийх юмгүй — feed рүү
              onTap: () {
                if (context.canPop()) { context.pop(); } else { context.go('/feed'); }
              }),
            const SizedBox(width: 10),
            Text('Хайх', style: AppTextStyles.h1),
          ]),
        ),

        // ── Search — апп даяарх нэгдсэн шилэн pill талбар (48) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: SearchField(
            controller: _ctrl,
            autofocus: true,
            onChanged: _search,
            hint: 'Хүн, газар хайх...'),
        ),

        Expanded(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          child: searching
            ? KeyedSubtree(key: const ValueKey('results'), child: _results())
            : KeyedSubtree(key: const ValueKey('discover'), child: _discover()),
        )),
      ])),
    );
  }

  // ── Хайлтын өмнөх төлөв: ТРЕНД chip-үүд + explore grid ──
  Widget _discover() => Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionLabel('ТРЕНД'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in _trends)
            _Pressable(
              onTap: () => _applyTrend(t),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.hairline)),
                // Галын icon — тренд мэдрэмж
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.whatshot_rounded,
                      size: 14, color: AppColors.amber),
                  const SizedBox(width: 6),
                  Text(t, style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.textSecondary)),
                ]))),
        ])),
      const SizedBox(height: 10),
      _sectionLabel('НЭЭЖ ҮЗЭХ'),
      Expanded(child: _exploreGrid()),
    ]);

  Widget _results() {
    // Хуучин үр дүн байхад spinner-ээр бүрхэхгүй — бүдэгрүүлж үлдээнэ
    if (_loading && _users.isEmpty && _venues.isEmpty) {
      return const Center(child: CircularProgressIndicator(
      color: AppColors.accentStart, strokeWidth: 2));
    }
    if (_searchError) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, size: 44, color: AppColors.textTertiary),
        const SizedBox(height: 10),
        Text('Алдаа гарлаа — дахин оролдоно уу',
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        // Нэгдсэн primary CTA — GradientButton (md)
        GradientButton(
          label: 'Дахин оролдох',
          size: GradientButtonSize.md,
          fullWidth: false,
          onPressed: () {
            setState(() { _loading = true; _searchError = false; });
            _runSearch(_ctrl.text.trim());
          }),
      ]));
    }
    if (_users.isEmpty && _venues.isEmpty) {
      // Хоосон төлөв — апп даяарх нэгдсэн EmptyState (icon хувилбар)
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Илэрц олдсонгүй',
        subtitle: 'Өөр түлхүүр үгээр хайж үзээрэй.');
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: _loading ? 0.55 : 1,
      child: ListView(children: [
        if (_users.isNotEmpty) ...[
          _sectionLabel('ХҮМҮҮС'),
          for (final u in _users) _userTile(u),
        ],
        if (_venues.isNotEmpty) ...[
          _sectionLabel('ГАЗРУУД'),
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
      Text(t, style: AppTextStyles.sectionLabel),
      const SizedBox(width: 12),
      const Expanded(child: Divider(color: AppColors.hairline, height: 1)),
    ]));

  // Мөрүүд — DM жагсаалтын мөртэй ижил хэмнэлтэй (20/12, avatar 46)
  Widget _userTile(Map<String, dynamic> u) {
    final uname = (u['username'] as String? ?? 'User').replaceAll('@', '');
    return InkWell(
      onTap: () => context.push('/creator/${u['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          AppAvatar(imageUrl: u['avatar_url'] as String?,
            initial: uname.isNotEmpty ? uname[0].toUpperCase() : '?', size: 46),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(child: Text('@$uname',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
                if (u['is_verified'] == true) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: AppColors.neonCyan, size: 14),
                ],
              ]),
              if ((u['full_name'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(u['full_name'] as String,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textSecondary)),
              ],
            ])),
          const Icon(Icons.chevron_right,
            color: AppColors.textTertiary, size: 18),
        ]),
      ),
    );
  }

  Widget _venueTile(Map<String, dynamic> v) => InkWell(
    onTap: () => context.push('/venue/reviews/${v['id']}'),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(children: [
        // Газрын icon — зөөлөн amber glass дугуй
        Container(width: 46, height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.amber.withValues(alpha: 0.12),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.35))),
          child: const Center(child: Icon(Icons.location_on,
            color: AppColors.amber, size: 20))),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(v['name'] as String? ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMd.copyWith(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            if ((v['district'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Text(v['district'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyXs.copyWith(
                  color: AppColors.textSecondary)),
            ],
          ])),
        const Icon(Icons.chevron_right,
          color: AppColors.textTertiary, size: 18),
      ]),
    ),
  );

  Widget _exploreGrid() {
    if (_exploreLoading && _explore.isEmpty) {
      // Skeleton grid — bare spinner-ээс илүү зөөлөн
      return _SkeletonGrid();
    }
    if (_exploreError) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, size: 44, color: AppColors.textTertiary),
        const SizedBox(height: 10),
        Text('Алдаа гарлаа — дахин оролдоно уу',
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
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
                CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                  memCacheWidth: 400, // grid thumbnail — жижиг decode, хурдан
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
              // Доод scrim + лайкийн тоолуур (татсан likes_count-оо ашиглана)
              if (likes > 0)
                Positioned(left: 0, right: 0, bottom: 0, child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54])),
                    child: Row(children: [
                      const Icon(Icons.favorite,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(_fmtLikes(likes),
                          style: const TextStyle(color: Colors.white,
                              fontSize: 11, fontWeight: FontWeight.w600)),
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
  const _Pressable({required this.child, required this.onTap});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child),
    ),
  );
}

// ─── Explore grid-ийн skeleton ───
class _SkeletonGrid extends StatefulWidget {
  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900),
    lowerBound: 0.35, upperBound: 0.8)..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: 12,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(14))),
    ),
  );
}
