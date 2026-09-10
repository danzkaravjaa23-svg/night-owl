import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../models/venue.dart';
import '../widgets/google_map_view.dart';
import '../widgets/map_controller.dart';
import '../providers/venue_provider.dart';

/// Бүтэн дэлгэцийн газрын зураг — бүх venue pin + доод venue carousel.
/// Карт дарвал зураг тухайн газар руу ниснэ; сум дарвал дэлгэрэнгүй нээнэ.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapCtrl = LeafletMapController();
  int _selected = -1;

  @override
  Widget build(BuildContext context) {
    final venuesAsync = ref.watch(venuesProvider);
    final venues = venuesAsync.value ?? const <Venue>[];
    // Байршилтай газрууд — хөл хөдөлгөөнтэй нь эхэндээ (carousel-д гоё)
    final located = [
      for (final v in venues) if (v.lat != null && v.lng != null) v
    ]..sort((a, b) => b.checkinCount.compareTo(a.checkinCount));
    final pinned = [
      for (final v in located)
        {
          'id': v.id, 'lat': v.lat, 'lng': v.lng, 'name': v.name,
          'img': v.coverUrl ?? (v.photos.isNotEmpty ? v.photos.first : null),
        }
    ];
    final markersJson = jsonEncode(pinned);
    // Refresh үед хуучин өгөгдлөө барьж үлдэнэ — зураг анивчихгүй
    final loading = venuesAsync.isLoading && !venuesAsync.hasValue;
    final failed = venuesAsync.hasError && !venuesAsync.hasValue;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      // Давхарлахгүй зохиомж: бар / зураг / carousel тусдаа бүсэд —
      // iframe нь Flutter товчнуудын дарлыг залгидаг тул давхцуулахгүй.
      body: SafeArea(child: Column(children: [
        // ── Дээд бар ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            // Буцах — апп даяарх нэгдсэн шилэн icon товч (44px хүрэх талбар)
            GlassIconButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Буцах',
              onTap: () => context.canPop()
                  ? context.pop() : context.go(AppRoutes.explore),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: _glassDeco(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.map_rounded,
                    color: AppColors.neonCyan, size: 17),
                const SizedBox(width: 7),
                Text('Газрын зураг', style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.textPrimary, letterSpacing: 0,
                    fontWeight: FontWeight.w800)),
              ]),
            ),
            const Spacer(),
            if (!loading && !failed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: _glassDeco(
                    borderColor: AppColors.neonCyan.withValues(alpha: 0.4)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.neonCyan,
                      boxShadow: [BoxShadow(
                          color: AppColors.neonCyan.withValues(alpha: 0.8),
                          blurRadius: 8)])),
                  const SizedBox(width: 6),
                  Text('${pinned.length} газар',
                      style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.neonCyan, letterSpacing: 0,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),

        // ── Газрын зураг (дунд бүс — юутай ч давхцахгүй) ──
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ClipRRect(
              borderRadius: AppRadii.lgR,
              child: failed
                  ? _MapError(onRetry: () => ref.invalidate(venuesProvider))
                  : loading
                      ? const _MapLoading()
                      : GoogleMapView(
                          // key хэрэггүй — marker өөрчлөгдвөл postMessage
                          // bridge-ээр iframe дотроо шинэчилнэ (зураг анивчихгүй)
                          lat: AppConstants.ubLat,
                          lng: AppConstants.ubLng,
                          zoom: 12,
                          markersJson: markersJson,
                          controller: _mapCtrl,
                          onVenueTap: (id) => context.push('/venue/reviews/$id'),
                        ),
            ),
          ),
        ),

        // ── Доод carousel ──
        if (!loading && !failed && located.isNotEmpty)
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              itemCount: located.length > 30 ? 30 : located.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _VenueMapCard(
                venue: located[i],
                selected: _selected == i,
                onTap: () {
                  setState(() => _selected = i);
                  _mapCtrl.center(located[i].lat!, located[i].lng!);
                },
                onOpen: () =>
                    context.push('/venue/reviews/${located[i].id}'),
              ),
            ),
          )
        else
          const SizedBox(height: 10),
      ])),
    );
  }

  // Шилэн шошго — жигд glass + зөөлөн доош унасан сүүдэр
  BoxDecoration _glassDeco({double radius = AppRadii.lg, Color? borderColor}) =>
      BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.hairline2),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 14, offset: const Offset(0, 4))],
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

/// Газрууд ачаалагдаж байх үеийн байдал
class _MapLoading extends StatelessWidget {
  const _MapLoading();
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.bgBase,
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const CircularProgressIndicator(
          color: AppColors.neonCyan, strokeWidth: 2),
      const SizedBox(height: 16),
      Text('Газрын зураг ачааллаж байна…',
          style: AppTextStyles.bodySm.copyWith(
              color: AppColors.textSecondary)),
    ])),
  );
}

/// Газрууд ачаалж чадаагүй — хоосон зураг биш, алдаа + retry харуулна
class _MapError extends StatelessWidget {
  final VoidCallback onRetry;
  const _MapError({required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.bgBase,
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_outlined,
          color: AppColors.textTertiary, size: 44),
      const SizedBox(height: 14),
      Text('Газрууд ачаалж чадсангүй', style: AppTextStyles.h3),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: onRetry, child: const Text('Дахин оролдох')),
    ])),
  );
}

/// Газрын зургийн доод carousel-ийн venue карт
class _VenueMapCard extends StatelessWidget {
  final Venue venue;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  const _VenueMapCard({
    required this.venue, required this.selected,
    required this.onTap, required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final img = venue.coverUrl ??
        (venue.photos.isNotEmpty ? venue.photos.first : null);
    return _Tap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 240,
        decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.92),
          borderRadius: AppRadii.lgR,
          border: Border.all(
            color: selected
                ? AppColors.neonCyan.withValues(alpha: 0.8)
                : AppColors.hairline2,
            width: selected ? 1.4 : 1),
          // Сүүдэр — жигд гүн + сонгогдсон үед cyan glow тодорно
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 14, offset: const Offset(0, 6)),
            if (selected)
              BoxShadow(color: AppColors.neonCyan.withValues(alpha: 0.35),
                  blurRadius: 20, spreadRadius: -2),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadii.lgR,
          child: Row(children: [
            // Зураг
            SizedBox(
              width: 86, height: double.infinity,
              child: img != null
                  ? CachedNetworkImage(
                      imageUrl: img, fit: BoxFit.cover,
                      memCacheWidth: 260,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) =>
                          Container(color: AppColors.bgSurface),
                      errorWidget: (_, __, ___) => _imgFallback())
                  : _imgFallback(),
            ),
            // Мэдээлэл
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 6, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(venue.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMd.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800, letterSpacing: 0)),
                  const SizedBox(height: 3),
                  Text(venue.district ?? venue.typeLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 5),
                  Row(children: [
                    if (venue.rating > 0) ...[
                      const Icon(Icons.star_rounded,
                          color: AppColors.amber, size: 13),
                      const SizedBox(width: 2),
                      Text(venue.rating.toStringAsFixed(1),
                          style: AppTextStyles.bodyXs.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                    ],
                    if (venue.checkinCount > 0) ...[
                      const Icon(Icons.people_alt_rounded,
                          size: 12, color: AppColors.neonCyan),
                      const SizedBox(width: 3),
                      Text('${venue.checkinCount}',
                          style: AppTextStyles.bodyXs.copyWith(
                              color: AppColors.neonCyan,
                              fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ]),
            )),
            // Дэлгэрэнгүй нээх сум
            _Tap(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 34, height: double.infinity,
                alignment: Alignment.center,
                child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonCyan.withValues(alpha: 0.14),
                    border: Border.all(
                        color: AppColors.neonCyan.withValues(alpha: 0.5))),
                  child: const Icon(Icons.arrow_forward_ios_rounded,
                      color: AppColors.neonCyan, size: 12)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _imgFallback() => Container(
    color: AppColors.bgSurface,
    child: const Center(child: Icon(Icons.local_bar_outlined,
        color: AppColors.textTertiary, size: 26)),
  );
}
