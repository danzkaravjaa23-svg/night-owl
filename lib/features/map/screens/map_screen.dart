import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
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
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.success.withOpacity(0.4)),
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
                  markersJson: jsonEncode([
                    for (final v in _filtered)
                      if (v.lat != null && v.lng != null)
                        {'lat': v.lat, 'lng': v.lng, 'name': v.name}
                  ]))
              : _filtered.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🔍', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('No venues found', style: AppTextStyles.h2),
                    ]),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) => _VenueCard(venue: _filtered[i]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  const _VenueCard({required this.venue});

  @override
  Widget build(BuildContext context) {
    final emoji = venue.emoji;
    return GestureDetector(
      onTap: () => context.push('/venue/reviews/${venue.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(children: [
          // Icon
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradientSoft,
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(venue.name, style: AppTextStyles.labelLg),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.location_on, size: 11, color: AppColors.textSecondary),
                const SizedBox(width: 3),
                Text(venue.district ?? '',
                  style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Open',
                    style: AppTextStyles.bodyXs.copyWith(
                      color: AppColors.success, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(venue.typeLabel,
                    style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
                ),
              ]),
            ],
          )),

          // Arrow
          const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
        ]),
      ),
    );
  }
}
