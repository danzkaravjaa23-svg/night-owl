import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:night_owl_ub/features/map/widgets/venue_map_label_layout.dart';

const _zoom = 14.0;

VenueLabelAnchor anchor(String id, double x, double y,
    {bool hasLabel = true, double above = 96, double below = 0}) {
  final scale = 256 * math.pow(2, _zoom);
  return VenueLabelAnchor(
    id: id,
    point: LatLng(
      (2 * math.atan(math.exp(-2 * math.pi * y / scale)) - math.pi / 2) *
          180 /
          math.pi,
      x / scale * 360,
    ),
    above: above,
    below: below,
    width: hasLabel ? 60 : 64,
    hasLabel: hasLabel,
  );
}

Set<String> visible(List<VenueLabelAnchor> anchors,
        {String? selected, double labelHeight = 28}) =>
    VenueMapLabelLayout.visibleIds(anchors,
        zoom: _zoom,
        labelWidth: 148,
        labelHeight: labelHeight,
        selectedId: selected);

void main() {
  test('isolated venue names remain visible without selecting a marker', () {
    expect(visible([anchor('a', 0, 0), anchor('b', 220, 0)]), {'a', 'b'});
    expect(visible([]), isEmpty);
  });

  test('conflicting names choose a stable ID regardless of input order', () {
    final anchors = [anchor('b', 100, 0), anchor('a', 0, 0)];
    expect(visible(anchors), {'a'});
    expect(visible(anchors.reversed.toList()), {'a'});
    expect(visible([anchor('b', 1100, 500), anchor('a', 1000, 500)]), {'a'});
  });

  test('selected name wins and reserves space before other names', () {
    final anchors = [anchor('a', 0, 0), anchor('b', 100, 0)];
    expect(visible(anchors, selected: 'b'), {'b'});
    expect(visible(anchors.reversed.toList(), selected: 'b'), {'b'});
  });

  test('cluster bodies reserve space but never create a venue name', () {
    final anchors = [
      anchor('a', 0, 0),
      anchor('cluster', 80, 20, hasLabel: false, above: 40, below: 40),
      anchor('b', 300, 0),
    ];
    expect(visible(anchors), {'b'});
    expect(visible(anchors, selected: 'a'), {'a', 'b'});
    expect(visible(anchors, selected: 'cluster'), {'b'});
  });

  test('coincident markers keep exactly one stable overview name', () {
    final anchors = [
      for (var i = 0; i < 270; i++)
        anchor('id-${i.toString().padLeft(3, '0')}', 0, 0),
    ];
    expect(visible(anchors), {'id-000'});
    expect(visible(anchors.reversed.toList()), {'id-000'});
    expect(visible(anchors, selected: 'id-269'), {'id-269'});
  });

  test('larger text reserves its actual height against nearby pin bodies', () {
    final anchors = [anchor('a', 0, 0), anchor('b', 0, 150)];
    expect(visible(anchors), {'a', 'b'});
    expect(visible(anchors, labelHeight: 60), {'b'});
  });

  test('layout preserves input order, coordinates and anchor dimensions', () {
    final anchors = [anchor('b', 100, 0), anchor('a', 0, 0)];
    final original = [...anchors];
    final points = [for (final entry in anchors) entry.point];
    visible(anchors, selected: 'a');
    expect(anchors, original);
    expect([for (final entry in anchors) entry.point], points);
    expect(anchors.every((entry) => entry.width == 60 && entry.above == 96),
        isTrue);
  });
}
