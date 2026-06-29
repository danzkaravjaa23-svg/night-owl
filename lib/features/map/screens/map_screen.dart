import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../widgets/google_map_view.dart';
import '../providers/venue_provider.dart';

/// Цэвэр энгийн газрын зураг — бүх venue-г pin-ээр (Leaflet + OSM, key шаардахгүй).
/// Venue хайлт / жагсаалт нь Explore дэлгэц дээр; энд ЗӨВХӨН газрын зураг.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(venuesProvider).value ?? const [];
    final markersJson = jsonEncode([
      for (final v in venues)
        if (v.lat != null && v.lng != null)
          {
            'id': v.id, 'lat': v.lat, 'lng': v.lng, 'name': v.name,
            'img': v.coverUrl ?? (v.photos.isNotEmpty ? v.photos.first : null),
          }
    ]);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(children: [
        // Бүтэн дэлгэцийн интерактив газрын зураг
        Positioned.fill(
          child: GoogleMapView(
            lat: AppConstants.ubLat,
            lng: AppConstants.ubLng,
            zoom: 12,
            markersJson: markersJson,
            onVenueTap: (id) => context.push('/venue/reviews/$id'),
          ),
        ),
        // Буцах товч — зүүн дээд, шилэн
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: () =>
                  context.canPop() ? context.pop() : context.go(AppRoutes.explore),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hairline2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
                  ],
                ),
                child: const Icon(Icons.chevron_left_rounded,
                    color: AppColors.textPrimary, size: 26),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
