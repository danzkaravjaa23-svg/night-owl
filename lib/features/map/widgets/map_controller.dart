/// Leaflet газрын зургийг гаднаас удирдах хөнгөн controller.
/// Web view нь `_centerImpl`-ийг оноож өгнө; бусад платформ дээр no-op.
class LeafletMapController {
  void Function(double lat, double lng, {int zoom})? centerImpl;

  /// Газрын зургийг тухайн цэг рүү гөлгөр шилжүүлнэ
  void center(double lat, double lng, {int zoom = 15}) =>
      centerImpl?.call(lat, lng, zoom: zoom);
}
