import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../core/widgets/sculpted_icon.dart';
import 'map_controller.dart';

class VenueMapMarker {
  final String id;
  final String name;
  final String type;
  final LatLng point;
  const VenueMapMarker(this.id, this.name, this.type, this.point);

  static List<VenueMapMarker> parse(String json) {
    try {
      final rows = jsonDecode(json);
      if (rows is! List) return [];
      final seen = <String>{};
      return [
        for (final row in rows)
          if (row is Map && row['id'] is String && seen.add(row['id']))
            if (_coordinate(row['lat'], 90) != null &&
                _coordinate(row['lng'], 180) != null)
              VenueMapMarker(
                  row['id'],
                  row['name']?.toString() ?? '',
                  row['type']?.toString() ?? 'venue',
                  LatLng(_coordinate(row['lat'], 90)!,
                      _coordinate(row['lng'], 180)!))
      ];
    } catch (_) {
      return [];
    }
  }

  static double? _coordinate(Object? value, double limit) {
    final number = double.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite && number.abs() <= limit
        ? number
        : null;
  }
}

class GoogleMapView extends StatefulWidget {
  final double lat;
  final double lng;
  final int zoom;
  final String markersJson;
  final String? selectedId;
  final LatLng? userLocation;
  final double bottomInset;
  final void Function(String venueId)? onVenueTap;
  final LeafletMapController? controller;
  const GoogleMapView(
      {super.key,
      required this.lat,
      required this.lng,
      this.zoom = 13,
      this.markersJson = '[]',
      this.selectedId,
      this.userLocation,
      this.bottomInset = 0,
      this.onVenueTap,
      this.controller});

  @override
  State<GoogleMapView> createState() => _VenueMapState();
}

class _VenueMapState extends State<GoogleMapView> {
  final _map = MapController();
  bool _ready = false;
  bool _tileError = false;
  int _tileRetry = 0;
  ({double lat, double lng, int zoom})? _pending;
  List<VenueMapMarker> _venues = [];

  @override
  void initState() {
    super.initState();
    _venues = VenueMapMarker.parse(widget.markersJson);
    _attach();
  }

  void _attach() {
    widget.controller?.centerImpl = _center;
    widget.controller?.fitImpl = _fit;
  }

  void _detach(LeafletMapController? controller) {
    if (controller?.centerImpl == _center) controller?.centerImpl = null;
    if (controller?.fitImpl == _fit) controller?.fitImpl = null;
  }

  @override
  void didUpdateWidget(covariant GoogleMapView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _detach(old.controller);
      _attach();
    }
    if (old.markersJson != widget.markersJson) {
      final wasEmpty = _venues.isEmpty;
      _venues = VenueMapMarker.parse(widget.markersJson);
      if (wasEmpty && _venues.isNotEmpty && _ready) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit();
        });
      }
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _map.dispose();
    super.dispose();
  }

  void _center(double lat, double lng, {int zoom = 15}) {
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      return;
    }
    if (!_ready) {
      _pending = (lat: lat, lng: lng, zoom: zoom);
      return;
    }
    _map.move(LatLng(lat, lng), zoom.clamp(3, 19).toDouble(),
        offset: Offset(0, -widget.bottomInset / 2));
  }

  void _fit() {
    if (!_ready || _venues.isEmpty) return;
    if (_venues.length == 1) {
      final p = _venues.first.point;
      _center(p.latitude, p.longitude);
    } else {
      _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(_venues.map((v) => v.point).toList()),
          padding: EdgeInsets.fromLTRB(
              44,
              44,
              44,
              (44 + widget.bottomInset)
                  .clamp(
                      44,
                      (_map.camera.nonRotatedSize.height - 92)
                          .clamp(44, double.infinity))
                  .toDouble()),
          maxZoom: 16));
    }
  }

  void _zoom(double step) {
    if (_ready) {
      _map.move(_map.camera.center, (_map.camera.zoom + step).clamp(3, 19));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tileGeneration = _tileRetry;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(children: [
      FlutterMap(
          mapController: _map,
          options: MapOptions(
              initialCenter: LatLng(widget.lat, widget.lng),
              initialZoom: widget.zoom.toDouble(),
              minZoom: 3,
              maxZoom: 19,
              backgroundColor:
                  dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () {
                _ready = true;
                final pending = _pending;
                if (pending != null) {
                  _pending = null;
                  _center(pending.lat, pending.lng, zoom: pending.zoom);
                } else if (_venues.isNotEmpty) {
                  _fit();
                }
              }),
          children: [
            ColorFiltered(
                colorFilter: dark
                    ? const ColorFilter.matrix([
                        -.1034,
                        -.3478,
                        -.0351,
                        0,
                        135,
                        -.1034,
                        -.3478,
                        -.0351,
                        0,
                        144,
                        -.1176,
                        -.3955,
                        -.0399,
                        0,
                        176,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ])
                    : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: TileLayer(
                    key: ValueKey(_tileRetry),
                    urlTemplate: AppConstants.mapTileUrl,
                    maxNativeZoom: 19,
                    userAgentPackageName: 'com.nightowl.ub.night_owl_ub',
                    keepBuffer: 2,
                    errorTileCallback: (_, __, ___) {
                      if (!mounted ||
                          _tileError ||
                          tileGeneration != _tileRetry) {
                        return;
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && tileGeneration == _tileRetry) {
                          setState(() => _tileError = true);
                        }
                      });
                    })),
            MarkerLayer(markers: [
              for (final venue in _venues)
                Marker(
                    key: ValueKey(venue.id),
                    point: venue.point,
                    width: 52,
                    height: 64,
                    alignment: Alignment.topCenter,
                    child: Tooltip(
                        message: venue.name,
                        child: Semantics(
                            label: venue.name,
                            selected: venue.id == widget.selectedId,
                            child: GestureDetector(
                                onTap: () => widget.onVenueTap?.call(venue.id),
                                behavior: HitTestBehavior.opaque,
                                child: CustomPaint(
                                    painter: _OwlPinPainter(
                                        dark: dark,
                                        selected:
                                            venue.id == widget.selectedId),
                                    child: const Padding(
                                        padding:
                                            EdgeInsets.fromLTRB(10, 8, 10, 24),
                                        child: NightOwlMark(size: 30))))))),
              if (widget.userLocation != null)
                Marker(
                    point: widget.userLocation!,
                    width: 28,
                    height: 28,
                    child: Semantics(
                        label: 'Миний байршил',
                        child: Container(
                            decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                boxShadow: const [
                              BoxShadow(
                                  color: Color(0x662563EB), blurRadius: 12)
                            ])))),
            ]),
          ]),
      if (widget.bottomInset == 0)
        Positioned(
            right: 12,
            top: 12,
            child: Column(children: [
              _control(Icons.add, 'Томруулах', () => _zoom(1)),
              const SizedBox(height: 6),
              _control(Icons.remove, 'Жижигрүүлэх', () => _zoom(-1)),
              const SizedBox(height: 6),
              _control(Icons.center_focus_strong, 'Бүх газрыг харах', _fit),
            ])),
      Positioned(
          left: 4,
          bottom: 4,
          child: Container(
              color: dark
                  ? const Color(0xE60B0D17)
                  : Colors.white.withValues(alpha: .94),
              child: InkWell(
                  onTap: () =>
                      launchUrl(Uri.parse(AppConstants.mapAttributionUrl)),
                  child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(AppConstants.mapAttribution,
                          style: TextStyle(
                              fontSize: 10,
                              color: dark
                                  ? const Color(0xFFB9B8CE)
                                  : AppColors.textSecondaryLight)))))),
      if (_tileError)
        Positioned(
            left: 12,
            right: 70,
            top: 12,
            child: Material(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          'Газрын зургийн хэсэг ачаалсангүй. Сүлжээгээ шалгаарай.',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      TextButton.icon(
                          onPressed: () => setState(() {
                                _tileError = false;
                                _tileRetry++;
                              }),
                          icon: SculptedIcon(Icons.refresh_rounded,
                              size: 16,
                              color: dark
                                  ? AppColors.neonCyanDark
                                  : AppColors.neonCyanLight,
                              onDark: dark),
                          label: const Text('Зураг дахин ачаалах')),
                    ])))),
    ]);
  }

  Widget _control(IconData icon, String label, VoidCallback onTap) => Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? AppColors.bgElevatedDark
          : AppColors.bgElevatedLight,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: IconButton(
          onPressed: onTap,
          tooltip: label,
          icon: SculptedIcon(icon,
              size: 22,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.neonCyanDark
                  : AppColors.neonCyanLight,
              onDark: Theme.of(context).brightness == Brightness.dark)));
}

class _OwlPinPainter extends CustomPainter {
  final bool selected;
  final bool dark;
  const _OwlPinPainter({required this.selected, required this.dark});
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..cubicTo(size.width * .3, size.height * .7, 0, size.height * .52, 0,
          size.height * .36)
      ..cubicTo(0, -size.height * .12, size.width, -size.height * .12,
          size.width, size.height * .36)
      ..cubicTo(size.width, size.height * .52, size.width * .7,
          size.height * .7, size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: dark ? .8 : .28),
        selected ? 8 : 4, true);
    final base =
        selected && dark ? const Color(0xFFB6A4FF) : const Color(0xFF7654D6);
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(base, Colors.white, .26)!,
                base,
                Color.lerp(base, const Color(0xFF25114A), .30)!
              ],
              stops: const [
                0,
                .46,
                1
              ]).createShader(Offset.zero & size));
    canvas.drawPath(
        path,
        Paint()
          ..color = selected && dark
              ? const Color(0xFFE5DEFF)
              : const Color(0xFF9680EA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1);
  }

  @override
  bool shouldRepaint(covariant _OwlPinPainter old) =>
      selected != old.selected || dark != old.dark;
}
