class LeafletMapController {
  void Function(double lat, double lng, {int zoom})? centerImpl;
  void Function()? fitImpl;

  void center(double lat, double lng, {int zoom = 15}) =>
      centerImpl?.call(lat, lng, zoom: zoom);
  void fitVenues() => fitImpl?.call();
}
