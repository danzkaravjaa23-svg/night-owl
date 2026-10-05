import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/widgets/app_motion.dart';
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

/// Every marker belongs to exactly one group. The first member anchors its
/// position, so panning never moves a bubble or changes its membership.
class VenueMarkerGroup {
  final List<VenueMapMarker> members;
  VenueMarkerGroup(List<VenueMapMarker> members)
      : members = List.unmodifiable(members);
  LatLng get point => members.first.point;
  bool get isCluster => members.length > 1;
  bool get isCoincident => members.every((member) =>
      (member.point.latitude - point.latitude).abs() < 1e-7 &&
      (member.point.longitude - point.longitude).abs() < 1e-7);
}

/// Deterministic screen-space grouping with a bounded spatial neighborhood.
/// Fixed anchors cannot form a long chain; no all-pairs distance scan is used.
abstract class VenueMarkerGrouping {
  static const double radius = 72;

  static double zoomBucket(double zoom) =>
      ((zoom.isFinite ? zoom.clamp(3, 19) : 13) * 2).floor() / 2;

  static List<VenueMarkerGroup> group(List<VenueMapMarker> venues,
      {required double zoom, String? selectedId}) {
    final scale = 256 * math.pow(2, zoomBucket(zoom));
    final sorted = [...venues]..sort((a, b) => a.id.compareTo(b.id));
    final cells = <(int, int), List<int>>{};
    final anchors = <Offset>[];
    final members = <List<VenueMapMarker>>[];
    VenueMapMarker? selected;
    for (final venue in sorted) {
      if (venue.id == selectedId) {
        selected = venue;
        continue;
      }
      final latitude = venue.point.latitude.clamp(-85.05112878, 85.05112878);
      final sin = math.sin(latitude * math.pi / 180);
      final pixel = Offset((venue.point.longitude + 180) / 360 * scale,
          (.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale);
      final cell = ((pixel.dx / radius).floor(), (pixel.dy / radius).floor());
      int? closest;
      var distance = radius * radius;
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final index in cells[(cell.$1 + dx, cell.$2 + dy)] ?? <int>[]) {
            final candidate = (pixel - anchors[index]).distanceSquared;
            if (candidate < distance ||
                (candidate == distance && closest != null && index < closest)) {
              closest = index;
              distance = candidate;
            }
          }
        }
      }
      if (closest != null) {
        members[closest].add(venue);
      } else {
        final index = members.length;
        anchors.add(pixel);
        members.add([venue]);
        (cells[cell] ??= []).add(index);
      }
    }
    return [
      for (final group in members) VenueMarkerGroup(group),
      if (selected != null) VenueMarkerGroup([selected]),
    ];
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

  void _openGroup(VenueMarkerGroup group) {
    if (!_ready || !mounted) return;
    if (group.isCoincident || _map.camera.zoom >= 18.9) {
      _showGroupMembers(group);
      return;
    }
    final height = _map.camera.nonRotatedSize.height;
    final fit = CameraFit.bounds(
      bounds:
          LatLngBounds.fromPoints(group.members.map((v) => v.point).toList()),
      padding: EdgeInsets.fromLTRB(
          40,
          44,
          40,
          (44 + widget.bottomInset)
              .clamp(44, math.max(44, height - 120))
              .toDouble()),
      maxZoom: 19,
    );
    // A small viewport with an open venue card may not permit a closer fit.
    // The member list is then a reachable alternative to a repeated no-op tap.
    if (fit.fit(_map.camera).zoom <= _map.camera.zoom + .1) {
      _showGroupMembers(group);
    } else {
      _map.fitCamera(fit);
    }
  }

  void _showGroupMembers(VenueMarkerGroup group) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: AppMotion.reduced(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppMotion.enter, reverseDuration: AppMotion.exit),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SizedBox(
        height: math.min(560, MediaQuery.sizeOf(sheetContext).height * .72),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(children: [
                Expanded(
                    child: Text('${group.members.length} ойролцоох газар',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: 'Хаах',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded)),
              ])),
          Expanded(
              child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: group.members.length,
            itemBuilder: (_, index) {
              final venue = group.members[index];
              return ListTile(
                key: ValueKey('venue-group-member-${venue.id}'),
                leading: Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFF211737)),
                    child: const NightOwlMark(size: 26)),
                title: Text(venue.name.isEmpty ? 'Нэргүй газар' : venue.name),
                subtitle: const Text('Газрын дэлгэрэнгүйг нээх'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (mounted) widget.onVenueTap?.call(venue.id);
                },
              );
            },
          )),
        ]),
      ),
    );
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
            _VenueMarkerLayer(
                venues: _venues,
                selectedId: widget.selectedId,
                userLocation: widget.userLocation,
                dark: dark,
                onVenueTap: widget.onVenueTap,
                onGroupTap: _openGroup),
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

class _VenueMarkerLayer extends StatefulWidget {
  final List<VenueMapMarker> venues;
  final String? selectedId;
  final LatLng? userLocation;
  final bool dark;
  final void Function(String)? onVenueTap;
  final void Function(VenueMarkerGroup) onGroupTap;
  const _VenueMarkerLayer(
      {required this.venues,
      required this.selectedId,
      required this.userLocation,
      required this.dark,
      required this.onVenueTap,
      required this.onGroupTap});

  @override
  State<_VenueMarkerLayer> createState() => _VenueMarkerLayerState();
}

class _VenueMarkerLayerState extends State<_VenueMarkerLayer> {
  double? _cachedZoom;
  String? _cachedSelected;
  List<VenueMapMarker>? _cachedVenues;
  List<VenueMarkerGroup> _groups = [];

  @override
  Widget build(BuildContext context) {
    final zoom = VenueMarkerGrouping.zoomBucket(MapCamera.of(context).zoom);
    if (_cachedZoom != zoom ||
        _cachedSelected != widget.selectedId ||
        _cachedVenues != widget.venues) {
      _groups = VenueMarkerGrouping.group(widget.venues,
          zoom: zoom, selectedId: widget.selectedId);
      _cachedZoom = zoom;
      _cachedSelected = widget.selectedId;
      _cachedVenues = widget.venues;
    }
    return MarkerLayer(markers: [
      for (final group in _groups)
        if (group.isCluster)
          Marker(
              key: ValueKey('venue-group-${group.members.first.id}'),
              point: group.point,
              width: 56,
              height: 48,
              child: _VenueGroupBubble(
                  count: group.members.length,
                  onTap: () => widget.onGroupTap(group)))
        else
          _venuePin(group.members.single),
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
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                      BoxShadow(color: Color(0x662563EB), blurRadius: 12)
                    ])))),
    ]);
  }

  Marker _venuePin(VenueMapMarker venue) => Marker(
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
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onVenueTap?.call(venue.id),
                  child: CustomPaint(
                      painter: _OwlPinPainter(
                          dark: widget.dark,
                          selected: venue.id == widget.selectedId),
                      child: const Padding(
                          padding: EdgeInsets.fromLTRB(10, 8, 10, 24),
                          child: NightOwlMark(size: 30)))))));
}

class _VenueGroupBubble extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _VenueGroupBubble({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [
            Color(0xFF9879EC),
            Color(0xFF7654D6),
            Color(0xFF503294)
          ]),
          border: Border.all(color: const Color(0xFFBCA6F8)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x55301B57), offset: Offset(0, 2), blurRadius: 4)
          ]),
      child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const NightOwlMark(size: 18),
            const SizedBox(width: 3),
            Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ])),
    );
    return Tooltip(
        message: '$count газар · Газруудыг харах',
        child: Semantics(
            button: true,
            label: '$count ойролцоох газар',
            child: PressFeedback(
                pressedScale: .96,
                hover: false,
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: Center(child: bubble)))));
  }
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
