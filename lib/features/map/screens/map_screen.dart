import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../widgets/google_map_view.dart';
import '../providers/venue_provider.dart';
import '../../../models/venue.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  String _filter = 'all';
  String _search = '';

  // 'map' нь шүүлтүүр биш — Google Map харах горим (хамгийн хойно)
  static const _types = ['all', 'bar', 'lounge', 'nightclub', 'pub', 'rooftop', 'map'];
  static const _emoji = {
    'bar': '🍺', 'lounge': '🛋️', 'nightclub': '🎵',
    'pub': '🍻', 'rooftop': '🌃', 'all': '📍', 'map': '🗺️',
  };

  List<Venue> get _filtered {
    final venues = ref.watch(venuesProvider).value ?? const <Venue>[];
    return venues.where((v) {
      final matchType = _filter == 'all' || _filter == 'map' || v.type == _filter;
      final matchSearch = _search.isEmpty ||
          v.name.toLowerCase().contains(_search.toLowerCase());
      return matchType && matchSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Text('UB Nightlife',
                    style: AppTextStyles.h1),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    Container(width: 6, height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.success)),
                    const SizedBox(width: 6),
                    Text('${_filtered.length} open',
                      style: AppTextStyles.bodyXs.copyWith(color: AppColors.success)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),

              // Search
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search venues...',
                        hintStyle: AppTextStyles.bodySm.copyWith(color: AppColors.textTertiary),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),

              // Filter chips
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _types.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final t = _types[i];
                    final active = _filter == t;
                    return GestureDetector(
                      onTap: () => setState(() => _filter = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.accentStart
                              : AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active ? AppColors.accentStart : AppColors.hairline),
                        ),
                        child: Text(
                          '${_emoji[t] ?? ''} ${t[0].toUpperCase()}${t.substring(1)}',
                          style: AppTextStyles.bodyXs.copyWith(
                            color: active ? Colors.white : AppColors.textSecondary,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Venue list эсвэл Google Map ──
          Expanded(
            child: _filter == 'map'
              ? GoogleMapView(
                  lat: AppConstants.ubLat, lng: AppConstants.ubLng, zoom: 12,
                  onVenueTap: (id) => context.push('/venue/reviews/$id'),
                  markersJson: jsonEncode([
                    for (final v in _filtered)
                      if (v.lat != null && v.lng != null)
                        {'id': v.id, 'lat': v.lat, 'lng': v.lng, 'name': v.name,
                         'img': v.coverUrl ?? (v.photos.isNotEmpty ? v.photos.first : null)}
                  ]))
              : _filtered.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🔍', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('No venues found', style: AppTextStyles.h2),
                    ]),
                  )
                : _BentoGrid(venues: _filtered),
          ),
        ]),
      ),
    );
  }
}

// ─── Bento Grid — асимметрик зургийн grid ───
class _BentoGrid extends StatelessWidget {
  final List<Venue> venues;
  const _BentoGrid({required this.venues});

  @override
  Widget build(BuildContext context) {
    // 3-аар бүлэглэнэ (1 том + 2 жижиг), үлдэгдлийг 2/1-ээр
    final blocks = <List<Venue>>[];
    for (var i = 0; i < venues.length;) {
      final take = (venues.length - i >= 3) ? 3 : (venues.length - i);
      blocks.add(venues.sublist(i, i + take));
      i += take;
    }
    const gap = 12.0;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: gap),
      itemBuilder: (_, bi) {
        final b = blocks[bi];
        if (b.length == 3) {
          final bigLeft = bi.isEven; // блок бүрд том tile тал солигдоно
          final big = Expanded(child: _BentoTile(venue: b[0], big: true));
          final smalls = Expanded(child: Column(children: [
            Expanded(child: _BentoTile(venue: b[1])),
            const SizedBox(height: gap),
            Expanded(child: _BentoTile(venue: b[2])),
          ]));
          return SizedBox(height: 232, child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: bigLeft
              ? [big, const SizedBox(width: gap), smalls]
              : [smalls, const SizedBox(width: gap), big]));
        }
        if (b.length == 2) {
          return SizedBox(height: 150, child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _BentoTile(venue: b[0])),
              const SizedBox(width: gap),
              Expanded(child: _BentoTile(venue: b[1])),
            ]));
        }
        return SizedBox(height: 160, child: _BentoTile(venue: b[0], big: true));
      },
    );
  }
}

class _BentoTile extends StatelessWidget {
  final Venue venue;
  final bool big;
  const _BentoTile({required this.venue, this.big = false});

  // Хэр их хүн байгааг (heatmap) checkin + id-ээс түвшин болгоно (0..4)
  int get _heatLevel {
    final c = venue.checkinCount;
    if (c >= 30) return 4;
    if (c >= 10) return 3;
    if (c >= 3)  return 2;
    if (c >= 1)  return 1;
    return venue.id.hashCode.abs() % 4; // бодит checkin байхгүй бол амьд харагдуулна
  }

  @override
  Widget build(BuildContext context) {
    final cover = venue.coverUrl ??
        (venue.photos.isNotEmpty ? venue.photos.first : null);
    return GestureDetector(
      onTap: () => context.push('/venue/reviews/${venue.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(fit: StackFit.expand, children: [
          // Бодит зураг (fallback — emoji gradient)
          cover != null
            ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover,
                placeholder: (_, __) => _emojiBox(), errorWidget: (_, __, ___) => _emojiBox())
            : _emojiBox(),

          // Доод gradient
          const DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x40000000), Color(0xE6000000)],
              stops: [0.4, 0.62, 1.0]))),

          // Heatmap badge (зүүн дээд)
          Positioned(top: 8, left: 8, child: _HeatBadge(level: _heatLevel)),

          // Rating (баруун дээд)
          if (venue.rating > 0)
            Positioned(top: 8, right: 8, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
                const SizedBox(width: 2),
                Text(venue.rating.toStringAsFixed(1), style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ]))),

          // Нэр + байршил
          Positioned(left: 10, right: 10, bottom: 10,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
                Text(venue.name, maxLines: big ? 2 : 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: big ? 16 : 13,
                    fontWeight: FontWeight.w800, height: 1.15,
                    shadows: const [Shadow(blurRadius: 8, color: Colors.black87)])),
                const SizedBox(height: 2),
                Text('${venue.district ?? ''} · ${venue.typeLabel}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black87)])),
              ])),
        ]),
      ),
    );
  }

  Widget _emojiBox() => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradientSoft),
    child: Center(child: Text(venue.emoji,
      style: TextStyle(fontSize: big ? 44 : 30))),
  );
}

// ─── Heatmap — pulsing неон цэг + хөл хүний түвшин ───
const _heatColors = [
  Color(0xFF8A8A95), // 0 Quiet
  Color(0xFF32D74B), // 1 Chill
  Color(0xFFFFD60A), // 2 Lively
  Color(0xFFFF8A00), // 3 Busy
  Color(0xFFFF2D55), // 4 Packed
];
const _heatLabels = ['Quiet', 'Chill', 'Lively', 'Busy', '🔥 Packed'];

class _HeatBadge extends StatefulWidget {
  final int level;
  const _HeatBadge({required this.level});
  @override
  State<_HeatBadge> createState() => _HeatBadgeState();
}

class _HeatBadgeState extends State<_HeatBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    // Хэдий халуун, төдий хурдан цохилно
    final ms = 1500 - widget.level * 220;
    _c = AnimationController(
      vsync: this, duration: Duration(milliseconds: ms.clamp(700, 1500)))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = _heatColors[widget.level.clamp(0, 4)];
    final label = _heatLabels[widget.level.clamp(0, 4)];
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Pulsing dot
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value; // 0..1
            return Container(
              width: 9, height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: color,
                boxShadow: [BoxShadow(
                  color: color.withValues(alpha: 0.4 + 0.5 * t),
                  blurRadius: 4 + 8 * t, spreadRadius: 0.5 + 2 * t)]));
          }),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
