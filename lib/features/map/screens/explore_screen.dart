import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../models/venue.dart';
import '../providers/venue_provider.dart';

/// Explore — UB nightlife discovery (Futurist Nightscape).
/// Discovery template: том гарчиг + pill хайлт + map товч, icon chips,
/// "Өнөө орой" том карт carousel, доор нь bento grid.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchFocused = false;
  String _query = '';
  String? _typeFilter; // null = бүгд

  static const _cats = <(String, String?, IconData)>[
    ('Бүгд', null, Icons.auto_awesome_rounded),
    ('Pub', 'pub', Icons.sports_bar_rounded),
    ('Lounge', 'lounge', Icons.local_bar_rounded),
    ('Club', 'nightclub', Icons.headphones_rounded),
    ('Rooftop', 'rooftop', Icons.deck_rounded),
    ('Restaurant', 'restaurant', Icons.restaurant_rounded),
  ];

  @override
  void initState() {
    super.initState();
    // Хайлтын талбар фокуслагдахад cyan glow асаана
    _searchFocus.addListener(() =>
        setState(() => _searchFocused = _searchFocus.hasFocus));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Venue> _filter(List<Venue> all) {
    var list = all;
    if (_typeFilter != null) {
      list = list.where((v) => v.type == _typeFilter).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((v) =>
          v.name.toLowerCase().contains(q) ||
          (v.district?.toLowerCase().contains(q) ?? false)).toList();
    }
    // Хамгийн хөл хөдөлгөөнтэйг нь эхэнд
    final sorted = [...list]..sort((a, b) => b.checkinCount.compareTo(a.checkinCount));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final venuesAsync = ref.watch(venuesProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: false,
        child: venuesAsync.when(
          loading: () => const _ExploreSkeleton(),
          error: (e, _) => _ErrorView(
            onRetry: () => ref.invalidate(venuesProvider)),
          data: (all) {
            final venues = _filter(all);
            // Өнөө орой — хамгийн халуун 5 газар (хайлтын үед нуугдана)
            final hot = venues.take(5).toList();
            final showHot = _query.trim().isEmpty && hot.isNotEmpty;

            return RefreshIndicator(
              color: AppColors.neonCyan,
              backgroundColor: AppColors.bgElevated,
              onRefresh: () => ref.refresh(venuesProvider.future),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _searchRow()),
                SliverToBoxAdapter(child: _chips()),
                if (showHot) ...[
                  SliverToBoxAdapter(child: _sectionTitle('Өнөө орой 🔥')),
                  SliverToBoxAdapter(child: _HotCarousel(venues: hot)),
                ],
                if (venues.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false, child: _EmptyView())
                else
                  SliverToBoxAdapter(child: _sectionTitle(
                    'Бүх газрууд', trailing: '${venues.length}')),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 110),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.62,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      // Bento хэмнэл — шатрын хөлөг маягаар өндөр/намхан зураг ээлжилнэ
                      (ctx, i) => _VenueCard(
                        venue: venues[i],
                        tall: ((i ~/ 2) + (i % 2)) % 2 == 0),
                      childCount: venues.length,
                    ),
                  ),
                ),
              ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Header — том гарчиг + дэд мөр ──
  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Нээ', style: AppTextStyles.h1.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text('УБ шөнийн газрууд — өнөөдөр хаашаа?',
        style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textTertiary, letterSpacing: 0.3)),
    ]),
  );

  // ── Section гарчиг — uppercase label + баруун талд тоо ──
  Widget _sectionTitle(String title, {String? trailing}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
    child: Row(children: [
      Text(title.toUpperCase(), style: AppTextStyles.sectionLabel),
      const Spacer(),
      if (trailing != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.bgElevated.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.hairline)),
          child: Text(trailing, style: AppTextStyles.labelSm.copyWith(
            color: AppColors.textSecondary, letterSpacing: 0))),
    ]),
  );

  // ── Хайлт pill + map квадрат товч ──
  Widget _searchRow() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
    child: Row(children: [
      Expanded(child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52,
        // Шилэн pill хайлт — фокус үед cyan хүрээ + glow
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _searchFocused
              ? AppColors.neonCyan.withValues(alpha: 0.6)
              : AppColors.hairline),
          boxShadow: _searchFocused
              ? AppColors.glowShadow(AppColors.neonCyan, alpha: 0.22)
              : const [],
        ),
        child: Row(children: [
          const SizedBox(width: 16),
          Icon(Icons.search,
            color: _searchFocused ? AppColors.neonCyan : AppColors.textTertiary,
            size: 20),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Газар, бар, клуб хайх…',
              hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero),
          )),
          if (_query.isNotEmpty)
            _Tap(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _searchCtrl.clear(); // харагдах текстийг мөн цэвэрлэнэ
                setState(() => _query = '');
              },
              child: const Padding(padding: EdgeInsets.only(right: 16),
                child: Icon(Icons.close, color: AppColors.textTertiary, size: 16))),
        ]),
      )),
      const SizedBox(width: 12),
      // Газрын зураг — квадрат товч (хуучин map banner-ын үйлдэл энд шилжсэн)
      _Tap(
        onTap: () => context.push(AppRoutes.map),
        child: Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppColors.bgElevated.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.4)),
            boxShadow: AppColors.glowShadow(AppColors.neonCyan, alpha: 0.2)),
          child: const Icon(Icons.map_rounded,
            color: AppColors.neonCyan, size: 24)),
      ),
    ]),
  );

  // ── Category chips — icon + label pill 40 ──
  Widget _chips() => SizedBox(
    height: 56,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _cats.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final (label, type, icon) = _cats[i];
        final active = _typeFilter == type;
        // Сонгогдсон chip — accentGradient + glow, бусад нь glass
        return _Tap(
          onTap: () => setState(() => _typeFilter = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: active ? AppColors.accentGradient : null,
              color: active ? null : AppColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active
                ? Colors.transparent : AppColors.hairline),
              boxShadow: active
                ? AppColors.glowShadow(AppColors.accentStart, alpha: 0.45)
                : const [],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16,
                color: active ? Colors.white : AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(label, style: AppTextStyles.labelMd.copyWith(
                color: active ? Colors.white : AppColors.textSecondary,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0)),
            ]),
          ),
        );
      },
    ),
  );
}

// ─── Дарлт мэдрэмж — scale + hover курсор (веб) ───
class _Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final HitTestBehavior behavior;
  const _Tap({required this.child, this.onTap,
    this.behavior = HitTestBehavior.deferToChild});
  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null
        ? MouseCursor.defer : SystemMouseCursors.click,
    child: GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    ),
  );
}

// ─── Status (real data: checkinCount) — Монгол шошго ───
({String label, Color color}) _statusFor(int checkins) {
  if (checkins >= 15) return (label: 'Дүүрэн', color: AppColors.orange);
  if (checkins >= 5)  return (label: 'Хөгжөөнтэй', color: AppColors.amber);
  return (label: 'Тайван', color: AppColors.lime);
}

class _StatusPill extends StatelessWidget {
  final int checkins;
  const _StatusPill({required this.checkins});
  @override
  Widget build(BuildContext context) {
    final s = _statusFor(checkins);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: s.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.color.withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: s.color.withValues(alpha: 0.25),
          blurRadius: 12, spreadRadius: -3)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          shape: BoxShape.circle, color: s.color,
          boxShadow: [BoxShadow(color: s.color, blurRadius: 6)])),
        const SizedBox(width: 6),
        Text(s.label, style: AppTextStyles.labelSm.copyWith(
          color: s.color, letterSpacing: 0, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ─── Venue image with gradient fallback ───
class _VenueImage extends StatelessWidget {
  final Venue venue;
  final double? height;
  const _VenueImage({required this.venue, this.height});
  @override
  Widget build(BuildContext context) {
    final url = venue.coverUrl ?? (venue.photos.isNotEmpty ? venue.photos.first : null);
    final fallback = Container(
      height: height,
      decoration: const BoxDecoration(gradient: AppColors.accentGradientSoft),
      child: const Center(child: Icon(Icons.local_bar_outlined,
        color: AppColors.textTertiary, size: 34)),
    );
    if (url == null) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      memCacheWidth: 600, // карт хэмжээний decode — хурдан, бага RAM
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => Container(color: AppColors.bgSurface, height: height),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

// ─── Шилэн rating chip — зурган дээр тод уншигдана ───
class _RatingChip extends StatelessWidget {
  final double rating;
  const _RatingChip({required this.rating});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.hairline)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, color: AppColors.amber, size: 12),
      const SizedBox(width: 3),
      Text(rating > 0 ? rating.toStringAsFixed(1) : '—',
        style: AppTextStyles.labelSm.copyWith(
          color: AppColors.textPrimary, letterSpacing: 0,
          fontWeight: FontWeight.w700)),
    ]),
  );
}

// ─── Жижиг stat chip — grid картын amber/cyan мөрөнд ───
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _StatChip({required this.icon, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.35))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 3),
      Text(text, style: AppTextStyles.labelSm.copyWith(
        color: color, letterSpacing: 0, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ─── "Өнөө орой" carousel — PageView-peek: том 280×180 карт, snap-тай ───
class _HotCarousel extends StatefulWidget {
  final List<Venue> venues;
  const _HotCarousel({required this.venues});
  @override
  State<_HotCarousel> createState() => _HotCarouselState();
}

class _HotCarouselState extends State<_HotCarousel> {
  PageController? _ctrl;
  double _fraction = 0;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  // Viewport-ын өргөнөөс 280+14 картын эзлэх хувийг тооцно — нарийн дэлгэцэд
  // дараагийн карт "peek" хийж, өргөн дэлгэцэд карт томрохгүйгээр snap хийнэ
  PageController _controllerFor(double width) {
    final f = ((280.0 + 14.0) / width).clamp(0.25, 0.92).toDouble();
    if (_ctrl == null || (f - _fraction).abs() > 0.01) {
      final old = _ctrl;
      _ctrl = PageController(viewportFraction: f);
      _fraction = f;
      // Resize үед хуучин контроллерийг дараагийн фреймд чөлөөлнө
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    return _ctrl!;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: Padding(
      padding: const EdgeInsets.only(left: 20),
      child: LayoutBuilder(builder: (context, box) => PageView.builder(
        controller: _controllerFor(box.maxWidth),
        padEnds: false,
        itemCount: widget.venues.length,
        itemBuilder: (_, i) => Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: SizedBox(width: 280, height: 180,
              child: _HotCard(venue: widget.venues[i])),
          ),
        ),
      )),
    ),
  );
}

class _HotCard extends StatelessWidget {
  final Venue venue;
  const _HotCard({required this.venue});
  @override
  Widget build(BuildContext context) => _Tap(
    onTap: () => context.push('/venue/reviews/${venue.id}'),
    child: Container(
      width: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline2),
        boxShadow: AppColors.shadowCard,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(fit: StackFit.expand, children: [
          _VenueImage(venue: venue, height: 180),
          // Доод scrim — нэр уншигдахуйц гүн
          DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            stops: const [0.4, 1.0],
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)]))),
          Positioned(top: 12, left: 12, child: _StatusPill(checkins: venue.checkinCount)),
          Positioned(top: 12, right: 12, child: _RatingChip(rating: venue.rating)),
          Positioned(left: 14, right: 14, bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(venue.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.place_outlined,
                  color: AppColors.textSecondary, size: 13),
                const SizedBox(width: 3),
                Flexible(child: Text(venue.district ?? venue.typeLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.textSecondary, letterSpacing: 0))),
              ]),
            ])),
        ]),
      ),
    ),
  );
}

// ─── Bento grid card — зураг дээр (өндөр/намхан ээлжилнэ), доор glass body ───
class _VenueCard extends StatelessWidget {
  final Venue venue;
  final bool tall; // bento хэмнэл — зургийн өндөр ээлжилнэ
  const _VenueCard({required this.venue, this.tall = true});
  @override
  Widget build(BuildContext context) {
    final imgH = tall ? 140.0 : 104.0;
    return _Tap(
      onTap: () => context.push('/venue/reviews/${venue.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.hairline),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Зураг — картын дотор 20 радиустай media
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                SizedBox(height: imgH, width: double.infinity,
                  child: _VenueImage(venue: venue, height: imgH)),
                // Доод scrim — status pill уншигдана
                Positioned.fill(child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                    colors: [Colors.transparent,
                      Colors.black.withValues(alpha: 0.45)])))),
                Positioned(top: 8, left: 8,
                  child: _StatusPill(checkins: venue.checkinCount)),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(venue.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(venue.district ?? venue.typeLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary)),
              const Spacer(),
              // Rating + check-in stat chips
              Row(children: [
                _StatChip(icon: Icons.star_rounded, color: AppColors.amber,
                  text: venue.rating > 0 ? venue.rating.toStringAsFixed(1) : '—'),
                const SizedBox(width: 6),
                Flexible(child: _StatChip(icon: Icons.bolt_rounded,
                  color: AppColors.neonCyan, text: '${venue.checkinCount}')),
              ]),
            ]),
          )),
        ]),
      ),
    );
  }
}

// ─── Loading / error / empty ───
// Зөөлөн цохилдог skeleton хайрцаг (spinner-ийн оронд layout хэлбэрээ хадгална)
class _SkelBox extends StatefulWidget {
  final double? width, height;
  final double radius;
  const _SkelBox({this.width, this.height, this.radius = 12});
  @override
  State<_SkelBox> createState() => _SkelBoxState();
}

class _SkelBoxState extends State<_SkelBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 700),
    lowerBound: 0.45, upperBound: 1.0)..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(widget.radius)),
    ),
  );
}

class _ExploreSkeleton extends StatelessWidget {
  const _ExploreSkeleton();
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SkelBox(width: 90, height: 32, radius: 8),
      const SizedBox(height: 6),
      const _SkelBox(width: 200, height: 13, radius: 6),
      const SizedBox(height: 18),
      // хайлт pill + map товч
      const Row(children: [
        Expanded(child: _SkelBox(height: 52, radius: 999)),
        SizedBox(width: 12),
        _SkelBox(width: 52, height: 52, radius: 16),
      ]),
      const SizedBox(height: 12),
      Row(children: [ // chips
        for (int i = 0; i < 4; i++) ...[
          const _SkelBox(width: 84, height: 40, radius: 999),
          const SizedBox(width: 8),
        ]]),
      const SizedBox(height: 28),
      const _SkelBox(width: 120, height: 12, radius: 6),
      const SizedBox(height: 12),
      // Carousel skeleton
      const SizedBox(height: 180, child: Row(children: [
        Expanded(child: _SkelBox(height: 180, radius: 24)),
        SizedBox(width: 14),
        _SkelBox(width: 60, height: 180, radius: 24),
      ])),
      const SizedBox(height: 28),
      const _SkelBox(width: 120, height: 12, radius: 6),
      const SizedBox(height: 12),
      // Grid skeleton — 4 карт
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.62,
        children: [for (int i = 0; i < 4; i++) const _SkelBox(radius: 24)]),
    ]),
  );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_outlined, color: AppColors.textTertiary, size: 44),
      const SizedBox(height: 14),
      Text('Газрууд ачаалж чадсангүй', style: AppTextStyles.h3),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: onRetry, child: const Text('Дахин оролдох')),
    ]),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off_rounded, color: AppColors.textTertiary, size: 44),
        const SizedBox(height: 14),
        Text('Газар олдсонгүй', style: AppTextStyles.h3),
        const SizedBox(height: 6),
        Text('Хайлт эсвэл шүүлтээ өөрчилж үзээрэй',
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary)),
      ]),
    ),
  );
}
