import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

/// A map marker's occupied body, relative to its geographic anchor.
/// Cluster bubbles reserve space with [hasLabel] set to false.
class VenueLabelAnchor {
  final String id;
  final LatLng point;
  final double above;
  final double below;
  final double width;
  final bool hasLabel;

  const VenueLabelAnchor({
    required this.id,
    required this.point,
    required this.above,
    required this.below,
    required this.width,
    this.hasLabel = true,
  });
}

/// Chooses readable overview labels without moving venues or changing groups.
/// World pixels and stable IDs keep the result independent of camera panning
/// and backend row order. The caller supplies its cached zoom bucket.
abstract class VenueMapLabelLayout {
  static Set<String> visibleIds(
    List<VenueLabelAnchor> anchors, {
    required double zoom,
    required double labelWidth,
    required double labelHeight,
    double gap = 4,
    String? selectedId,
  }) {
    assert(labelWidth.isFinite && labelWidth > 0);
    assert(labelHeight.isFinite && labelHeight > 0);
    assert(gap.isFinite && gap >= 0);
    final scale = 256 * math.pow(2, zoom.isFinite ? zoom.clamp(3, 19) : 13);
    final bodyIndex = _RectIndex(labelWidth + 12, labelHeight + 12);
    final labelIndex = _RectIndex(labelWidth + 12, labelHeight + 12);
    final projected = <String, Offset>{};
    final sorted = [...anchors]..sort((a, b) {
        if ((a.id == selectedId) != (b.id == selectedId)) {
          return a.id == selectedId ? -1 : 1;
        }
        return a.id.compareTo(b.id);
      });

    for (final anchor in sorted) {
      final latitude = anchor.point.latitude.clamp(-85.05112878, 85.05112878);
      final sin = math.sin(latitude * math.pi / 180);
      final point = Offset(
        (anchor.point.longitude + 180) / 360 * scale,
        (.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale,
      );
      projected[anchor.id] = point;
      bodyIndex.add(_ReservedRect(
        anchor.id,
        Rect.fromLTRB(point.dx - anchor.width / 2, point.dy - anchor.above,
            point.dx + anchor.width / 2, point.dy + anchor.below),
      ));
    }

    final visible = <String>{};
    for (final anchor in sorted) {
      if (!anchor.hasLabel) continue;
      final point = projected[anchor.id]!;
      final label = Rect.fromLTWH(
          point.dx - labelWidth / 2, point.dy + gap, labelWidth, labelHeight);
      // Selection deliberately wins. Reserve it first so every other name
      // respects the selected venue, even when its own body is crowded.
      if (anchor.id != selectedId &&
          (bodyIndex.intersects(label.inflate(4), exceptId: anchor.id) ||
              labelIndex.intersects(label.inflate(6)))) {
        continue;
      }
      visible.add(anchor.id);
      labelIndex.add(_ReservedRect(anchor.id, label));
    }
    return Set.unmodifiable(visible);
  }
}

class _ReservedRect {
  final String id;
  final Rect rect;
  const _ReservedRect(this.id, this.rect);
}

/// Rectangles are indexed in every occupied cell, so tall pin bodies and large
/// accessibility text need only local collision queries, not all-pairs scans.
class _RectIndex {
  final double cellWidth;
  final double cellHeight;
  final _cells = <(int, int), List<_ReservedRect>>{};

  _RectIndex(this.cellWidth, this.cellHeight);

  Iterable<(int, int)> _keys(Rect rect) sync* {
    for (var x = (rect.left / cellWidth).floor();
        x <= (rect.right / cellWidth).floor();
        x++) {
      for (var y = (rect.top / cellHeight).floor();
          y <= (rect.bottom / cellHeight).floor();
          y++) {
        yield (x, y);
      }
    }
  }

  void add(_ReservedRect entry) {
    for (final key in _keys(entry.rect)) {
      (_cells[key] ??= []).add(entry);
    }
  }

  bool intersects(Rect rect, {String? exceptId}) {
    final checked = <_ReservedRect>{};
    for (final key in _keys(rect)) {
      for (final entry in _cells[key] ?? const <_ReservedRect>[]) {
        if (entry.id != exceptId &&
            checked.add(entry) &&
            rect.overlaps(entry.rect)) {
          return true;
        }
      }
    }
    return false;
  }
}
