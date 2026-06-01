import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _mapCounter = 0;

/// Веб дээр интерактив газрын зураг — Leaflet + OpenStreetMap (API key
/// шаардахгүй). venue бүрийг тусдаа pin + нэрээр харуулна.
class GoogleMapView extends StatefulWidget {
  final double lat;
  final double lng;
  final int zoom;
  final String markersJson; // [{"lat":..,"lng":..,"name":".."}]
  const GoogleMapView({
    super.key,
    required this.lat,
    required this.lng,
    this.zoom = 13,
    this.markersJson = '[]',
  });

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  late final String _viewType;

  String _buildHtml() => '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html,body,#map{height:100%;margin:0;background:#0a0a0f}
  .vt{background:rgba(0,0,0,.7);border:none;color:#fff;font:600 11px sans-serif;
      box-shadow:none;padding:2px 6px;border-radius:8px}
  .vt:before{display:none}
  .leaflet-popup-content{font:600 13px sans-serif}
</style></head><body><div id="map"></div>
<script>
  var map = L.map('map',{zoomControl:true}).setView([${widget.lat}, ${widget.lng}], ${widget.zoom});
  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    {maxZoom:19, attribution:'© OpenStreetMap, © CARTO'}).addTo(map);
  var venues = ${widget.markersJson};
  venues.forEach(function(v){
    if (v.lat==null || v.lng==null) return;
    L.circleMarker([v.lat, v.lng], {radius:9, color:'#fff', weight:2,
      fillColor:'#FF3B7B', fillOpacity:1}).addTo(map)
      .bindTooltip(v.name, {permanent:true, direction:'top', className:'vt'})
      .bindPopup('<b>'+v.name+'</b>');
  });
</script></body></html>''';

  @override
  void initState() {
    super.initState();
    _viewType = 'leaflet-map-${_mapCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = html.IFrameElement()
        ..srcdoc = _buildHtml()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
