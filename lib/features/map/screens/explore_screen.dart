import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../models/venue.dart';
import '../providers/venue_provider.dart';

/// Explore — UB nightlife venues (Futurist Nightscape).
/// Жинхэнэ venue өгөгдөл (venuesProvider) дээр суурилсан grid + glow status pill.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String _query = '';
  String? _typeFilter; // null = бүгд

  static const _cats = <(String, String?)>[
    ('Бүгд', null),
    ('Pub', 'pub'),
    ('Lounge', 'lounge'),
    ('Club', 'nightclub'),
    ('Rooftop', 'rooftop'),
    ('Restaurant', 'restaurant'),
  ];

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
            final featured = venues.isNotEmpty ? venues.first : null;
            final grid = featured != null ? venues.skip(1).toList() : venues;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverToBoxAdapter(child: _searchBar()),
                SliverToBoxAdapter(child: _chips()),
                if (featured != null)
                  SliverToBoxAdapter(child: _FeaturedCard(venue: featured)),
                if (venues.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false, child: _EmptyView()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _VenueCard(venue: grid[i]),
                      childCount: grid.length,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header ──
  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 16, 6),
    child: Row(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Explore', style: AppTextStyles.displaySm),
        const SizedBox(height: 2),
        Text('UB · ШӨНИЙН ГАЗРУУД',
          style: AppTextStyles.monoSm.copyWith(
            letterSpacing: 2, color: AppColors.textTertiary)),
      ]),
      const Spacer(),
      // Газрын зураг руу (хуучин map дэлгэц хадгалагдсан)
      GestureDetector(
        onTap: () => context.push(AppRoutes.map),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: const Icon(Icons.map_outlined,
            color: AppColors.neonCyan, size: 22),
        ),
      ),
    ]),
  );

  // ── Search ──
  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: TextField(
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Газар, бар, клуб хайх…',
        prefixIcon: const Icon(Icons.search,
          color: AppColors.textTertiary, size: 20),
      ),
    ),
  );

  // ── Category chips ──
  Widget _chips() => SizedBox(
    height: 52,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      itemCount: _cats.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final (label, type) = _cats[i];
        final active = _typeFilter == type;
        return GestureDetector(
          onTap: () => setState(() => _typeFilter = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.neonCyan : AppColors.bgSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active
                ? Colors.transparent : AppColors.hairline),
              boxShadow: active
                ? [BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.45),
                    blurRadius: 16, spreadRadius: -3)]
                : [],
            ),
            child: Text(label, style: AppTextStyles.labelMd.copyWith(
              color: active ? AppColors.bgBase : AppColors.textSecondary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: 0)),
          ),
        );
      },
    ),
  );
}

// ─── Status (real data: checkinCount) ───
({String label, Color color}) _statusFor(int checkins) {
  if (checkins >= 15) return (label: 'Busy', color: AppColors.orange);
  if (checkins >= 5)  return (label: 'Lively', color: AppColors.amber);
  return (label: 'Chill', color: AppColors.lime);
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
      child: Center(child: Icon(Icons.local_bar_outlined,
        color: AppColors.textTertiary, size: 34)),
    );
    if (url == null) return fallback;
    return CachedNetworkImage(
      imageUrl: url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: AppColors.bgSurface, height: height),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

// ─── Featured (large) card ───
class _FeaturedCard extends StatelessWidget {
  final Venue venue;
  const _FeaturedCard({required this.venue});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: GestureDetector(
      onTap: () => context.push('/venue/reviews/${venue.id}'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.hairline2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(children: [
            SizedBox(height: 190, width: double.infinity,
              child: _VenueImage(venue: venue, height: 190)),
            Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)])))),
            Positioned(top: 12, left: 12, child: _StatusPill(checkins: venue.checkinCount)),
            if (venue.isOpen)
              Positioned(top: 12, right: 12, child: _OpenPill()),
            Positioned(left: 14, right: 14, bottom: 12,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(venue.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.h1.copyWith(fontWeight: FontWeight.w800))),
                  if (venue.verified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified, color: AppColors.neonCyan, size: 18),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, color: AppColors.amber, size: 15),
                  const SizedBox(width: 3),
                  Text(venue.rating > 0 ? venue.rating.toStringAsFixed(1) : '—',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary)),
                  const SizedBox(width: 12),
                  const Icon(Icons.place_outlined, color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 2),
                  Flexible(child: Text(venue.district ?? venue.typeLabel,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary))),
                ]),
              ])),
          ]),
        ),
      ),
    ),
  );
}

class _OpenPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.lime.withValues(alpha: 0.4)),
    ),
    child: Text('Нээлттэй', style: AppTextStyles.labelSm.copyWith(
      color: AppColors.lime, letterSpacing: 0)),
  );
}

// ─── Grid venue card ───
class _VenueCard extends StatelessWidget {
  final Venue venue;
  const _VenueCard({required this.venue});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => context.push('/venue/reviews/${venue.id}'),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Stack(children: [
            SizedBox(height: 116, width: double.infinity,
              child: _VenueImage(venue: venue, height: 116)),
            Positioned(top: 8, left: 8, child: _StatusPill(checkins: venue.checkinCount)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(venue.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.h3)),
              if (venue.verified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: AppColors.neonCyan, size: 13),
              ],
            ]),
            const SizedBox(height: 5),
            Row(children: [
              const Icon(Icons.star_rounded, color: AppColors.amber, size: 13),
              const SizedBox(width: 3),
              Text(venue.rating > 0 ? venue.rating.toStringAsFixed(1) : '—',
                style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Flexible(child: Text('· ${venue.typeLabel}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary))),
            ]),
            if (venue.district != null) ...[
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.place_outlined, color: AppColors.textTertiary, size: 12),
                const SizedBox(width: 2),
                Flexible(child: Text(venue.district!,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary))),
              ]),
            ],
          ]),
        ),
      ]),
    ),
  );
}

// ─── Loading / error / empty ───
class _ExploreSkeleton extends StatelessWidget {
  const _ExploreSkeleton();
  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(color: AppColors.neonCyan, strokeWidth: 2));
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
