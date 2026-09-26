import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'map_controller.dart';

/// Native газрын зураг — flutter_map + CARTO (вебийн Leaflet-тэй ижил tile/pin).
class GoogleMapView extends StatefulWidget {
  final double lat;
  final double lng;
  final int zoom;
  final String markersJson; // [{"id":"..","lat":..,"lng":..,"name":"..","img":".."}]
  final void Function(String venueId)? onVenueTap;
  final LeafletMapController? controller;
  const GoogleMapView({
    super.key,
    required this.lat,
    required this.lng,
    this.zoom = 13,
    this.markersJson = '[]',
    this.onVenueTap,
    this.controller,
  });

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _Venue {
  final String key;
  final String id;
  final String name;
  final LatLng point;
  final String? img;
  const _Venue({
    required this.key,
    required this.id,
    required this.name,
    required this.point,
    this.img,
  });
}

class _GoogleMapViewState extends State<GoogleMapView>
    with SingleTickerProviderStateMixin {
  static const _userAgent = 'com.nightowl.ub.night_owl_ub';
  static const double _maxZoom = 19;
  // 3-аас доош бол нэг marker хоёр "дэлхий"-д зэрэг гарч key давхцана
  static const double _minZoom = 3;

  final _map = MapController();
  final _tiles = NetworkTileProvider();
  late final AnimationController _fly;
  LatLngTween? _flyCenter;
  Tween<double>? _flyZoom;
  bool _ready = false;
  LatLng? _pendingCenter;
  double _pendingZoom = 15;
  List<_Venue> _venues = const [];

  static String get _cartoKeyParam {
    const k = AppConstants.cartoBasemapKey;
    return k.isEmpty ? '' : '?key=$k';
  }

  @override
  void initState() {
    super.initState();
    _fly = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..addListener(_onFly);
    _venues = _parse(widget.markersJson) ?? const [];
    widget.controller?.centerImpl = _center;
  }

  @override
  void didUpdateWidget(covariant GoogleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller;
      if (old != null && old.centerImpl == _center) old.centerImpl = null;
      widget.controller?.centerImpl = _center;
    }
    // Буруу JSON ирвэл веб шиг хуучин pin-үүдээ үлдээнэ
    if (oldWidget.markersJson != widget.markersJson) {
      final parsed = _parse(widget.markersJson);
      if (parsed != null) _venues = parsed;
    }
  }

  @override
  void dispose() {
    final c = widget.controller;
    if (c != null && c.centerImpl == _center) c.centerImpl = null;
    _fly
      ..removeListener(_onFly)
      ..dispose();
    _map.dispose();
    super.dispose();
  }

  static List<_Venue>? _parse(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! List) return null;
      final out = <_Venue>[];
      final seen = <String, int>{};
      for (final e in data) {
        if (e is! Map) continue;
        final lat = _num(e['lat']);
        final lng = _num(e['lng']);
        if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
          continue;
        }
        final id = e['id']?.toString() ?? '';
        final img = _safeUrl(e['img']);
        final base = '$id|${img ?? ''}';
        final n = seen[base] = (seen[base] ?? 0) + 1;
        out.add(_Venue(
          key: n == 1 ? base : '$base#$n',
          id: id,
          name: e['name']?.toString() ?? '',
          point: LatLng(lat, lng),
          img: img,
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  static double? _num(Object? v) {
    final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    return d != null && d.isFinite ? d : null;
  }

  static String? _safeUrl(Object? v) {
    final u = v?.toString() ?? '';
    return u.startsWith('https://') || u.startsWith('http://') ? u : null;
  }

  void _center(double lat, double lng, {int zoom = 15}) {
    if (!mounted || !lat.isFinite || !lng.isFinite) return;
    final target = LatLng(lat, lng);
    if (!_ready) {
      _pendingCenter = target;
      _pendingZoom = zoom.toDouble();
      return;
    }
    _animateTo(target, zoom.toDouble(), const Duration(milliseconds: 800));
  }

  void _onReady() {
    if (!mounted) return;
    _ready = true;
    final p = _pendingCenter;
    if (p != null) {
      _pendingCenter = null;
      _animateTo(p, _pendingZoom, const Duration(milliseconds: 800));
    }
  }

  void _animateTo(LatLng center, double zoom, Duration duration) {
    try {
      final cam = _map.camera;
      _flyCenter = LatLngTween(begin: cam.center, end: center);
      _flyZoom = Tween<double>(
          begin: cam.zoom, end: zoom.clamp(_minZoom, _maxZoom).toDouble());
      _fly
        ..duration = duration
        ..forward(from: 0);
    } catch (_) {}
  }

  void _onFly() {
    final c = _flyCenter;
    final z = _flyZoom;
    if (c == null || z == null) return;
    final t = Curves.easeInOutCubic.transform(_fly.value);
    try {
      _map.move(c.transform(t), z.transform(t));
    } catch (_) {}
  }

  void _zoomBy(double delta) {
    try {
      final cam = _map.camera;
      _animateTo(cam.center, (cam.zoom + delta).roundToDouble(),
          const Duration(milliseconds: 250));
    } catch (_) {}
  }

  void _stopFly(PointerDownEvent _, LatLng __) {
    if (_fly.isAnimating) _fly.stop();
  }

  void _tap(String id) {
    if (id.isNotEmpty) widget.onVenueTap?.call(id);
  }

  List<Marker> _markers(bool dark) {
    final dots = <Marker>[];
    final pins = <Marker>[];
    for (final v in _venues) {
      final isPin = v.img != null;
      (isPin ? pins : dots).add(Marker(
        key: ValueKey(v.key),
        point: v.point,
        width: isPin ? 42.0 : 32.0,
        height: isPin ? 42.0 : 32.0,
        child: _VenueMarker(venue: v, dark: dark, onTap: () => _tap(v.id)),
      ));
    }
    // Leaflet шиг: зурагтай pin цэгүүдийн дээр, өмнөд талынх нь дээр давхарлана
    pins.sort((a, b) => b.point.latitude.compareTo(a.point.latitude));
    return [...dots, ...pins];
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDarkMode;
    final retina = MediaQuery.devicePixelRatioOf(context) > 1.0;
    return Stack(children: [
      Positioned.fill(
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: LatLng(widget.lat, widget.lng),
            initialZoom: widget.zoom.toDouble(),
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            backgroundColor: AppColors.bgBase,
            interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: _onReady,
            onPointerDown: _stopFly,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/'
                  '${dark ? 'dark_all' : 'light_all'}/{z}/{x}/{y}{r}.png'
                  '$_cartoKeyParam',
              subdomains: const ['a', 'b', 'c', 'd'],
              maxNativeZoom: 19,
              keepBuffer: 5,
              retinaMode: retina,
              tileProvider: _tiles,
              userAgentPackageName: _userAgent,
            ),
            MarkerLayer(markers: _markers(dark)),
          ],
        ),
      ),
      Positioned(
        top: 20,
        right: 14,
        child: _ZoomBar(
            dark: dark, onIn: () => _zoomBy(1), onOut: () => _zoomBy(-1)),
      ),
      Positioned(
        right: 10,
        bottom: 6,
        child: IgnorePointer(child: _Attribution(dark: dark)),
      ),
    ]);
  }
}

/// Venue pin — удаан дарвал нэр гарна (веб дээрх hover tooltip-ийн оронд).
class _VenueMarker extends StatefulWidget {
  final _Venue venue;
  final bool dark;
  final VoidCallback onTap;
  const _VenueMarker(
      {required this.venue, required this.dark, required this.onTap});

  @override
  State<_VenueMarker> createState() => _VenueMarkerState();
}

class _VenueMarkerState extends State<_VenueMarker> {
  bool _down = false;

  void _press(bool down) {
    if (mounted && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.venue;
    final dark = widget.dark;
    final img = v.img;
    final Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: img != null
          ? AnimatedScale(
              scale: _down ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: _pin(img, dark),
            )
          : Center(child: _dot()),
    );
    if (v.name.isEmpty) return child;
    return Tooltip(
      message: v.name,
      triggerMode: TooltipTriggerMode.longPress,
      preferBelow: false,
      verticalOffset: img != null ? 25.0 : 14.0,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: dark ? 0.88 : 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.45)),
        boxShadow: [
          dark
              ? BoxShadow(
                  color: AppColors.neonCyan.withValues(alpha: 0.25),
                  blurRadius: 14)
              : const BoxShadow(
                  color: Color(0x291A0B2E),
                  blurRadius: 10,
                  offset: Offset(0, 2)),
        ],
      ),
      textStyle: AppTextStyles.bodyXs.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2),
      child: child,
    );
  }

  Widget _pin(String url, bool dark) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.bgSurface,
          border: Border.all(color: AppColors.accentEnd, width: 2),
          boxShadow: [
            BoxShadow(
                color: AppColors.accentEnd.withValues(alpha: dark ? 0.55 : 0.45),
                blurRadius: 14),
            BoxShadow(
                color: dark ? const Color(0x99000000) : const Color(0x4D1A0B2E),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 128,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );

  Widget _dot() => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accentEnd.withValues(alpha: 0.95),
          border: Border.all(color: Colors.white, width: 2),
        ),
      );
}

/// Вебийн Leaflet zoom товчтой ижил шилэн +/− (баруун дээд буланд)
class _ZoomBar extends StatelessWidget {
  final bool dark;
  final VoidCallback onIn;
  final VoidCallback onOut;
  const _ZoomBar({required this.dark, required this.onIn, required this.onOut});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x33000000), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _btn('+', 'Томруулах', onIn),
            _btn('−', 'Жижигрүүлэх', onOut),
          ]),
        ),
      );

  Widget _btn(String label, String tip, VoidCallback onTap) => Semantics(
        button: true,
        label: tip,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: dark ? 0.85 : 0.92),
              border: Border.all(color: AppColors.hairline2),
            ),
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: AppColors.textPrimary)),
          ),
        ),
      );
}

class _Attribution extends StatelessWidget {
  final bool dark;
  const _Attribution({required this.dark});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: dark ? const Color(0x66000000) : const Color(0xB3FFFFFF),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('© OpenStreetMap © CARTO',
            style: AppTextStyles.bodyXs.copyWith(
                fontSize: 9, height: 1.4, color: AppColors.textTertiary)),
      );
}
