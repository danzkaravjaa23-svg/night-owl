import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

int _mapCounter = 0;

/// Веб дээр интерактив газрын зураг — Leaflet + OpenStreetMap (үнэгүй,
/// API key/billing шаардахгүй). Pin дарвал venue нээх + миний байршил.
class GoogleMapView extends StatefulWidget {
  final double lat;
  final double lng;
  final int zoom;
  final String markersJson; // [{"id":"..","lat":..,"lng":..,"name":".."}]
  final void Function(String venueId)? onVenueTap;
  const GoogleMapView({
    super.key,
    required this.lat,
    required this.lng,
    this.zoom = 13,
    this.markersJson = '[]',
    this.onVenueTap,
  });

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  late final String _viewType;

  // Leaflet + OpenStreetMap (үнэгүй, key шаардахгүй)
  String _buildHtml() => '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html,body,#map{height:100%;margin:0;background:#0a0a0f}
  .vt{background:rgba(0,0,0,.7);border:none;color:#fff;font:600 11px sans-serif;
      box-shadow:none;padding:2px 6px;border-radius:8px;cursor:pointer}
  .vt:before{display:none}
  #loc{position:absolute;right:12px;bottom:24px;z-index:1000;width:44px;height:44px;
    border:none;border-radius:50%;background:#FF3B7B;color:#fff;font-size:20px;
    box-shadow:0 2px 8px rgba(0,0,0,.5);cursor:pointer}
  .vpin{width:40px;height:40px;border-radius:50%;border:2px solid #FF3B7B;
    background-size:cover;background-position:center;box-shadow:0 2px 6px rgba(0,0,0,.6);
    cursor:pointer}
</style></head><body><div id="map"></div>
<button id="loc" title="Миний байршил">📍</button>
<script>
  var map = L.map('map',{zoomControl:true}).setView([${widget.lat}, ${widget.lng}], ${widget.zoom});
  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    {maxZoom:19, attribution:'© OpenStreetMap, © CARTO'}).addTo(map);
  var venues = ${widget.markersJson};
  venues.forEach(function(v){
    if (v.lat==null || v.lng==null) return;
    var mk;
    if (v.img) {
      // Эзэн зураг оруулсан бол дугуй зургийн marker
      var icon = L.divIcon({className:'', iconSize:[40,40], iconAnchor:[20,20],
        html:'<div class="vpin" style="background-image:url(\\''+v.img+'\\')"></div>'});
      mk = L.marker([v.lat, v.lng], {icon:icon}).addTo(map)
        .bindTooltip(v.name, {permanent:false, direction:'top', className:'vt'});
    } else {
      // Зураггүй бол одоогийн цэг
      mk = L.circleMarker([v.lat, v.lng], {radius:9, color:'#fff', weight:2,
        fillColor:'#FF3B7B', fillOpacity:1}).addTo(map)
        .bindTooltip(v.name, {permanent:false, direction:'top', className:'vt'});
    }
    // Pin/нэр дарвал Flutter руу venue id илгээж дэлгэц нээнэ
    mk.on('click', function(){ if(v.id) parent.postMessage('venue:'+v.id,'*'); });
  });
  // Миний байршил
  var meMarker = null;
  document.getElementById('loc').onclick = function(){
    if(!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(function(p){
      var ll = [p.coords.latitude, p.coords.longitude];
      map.setView(ll, 15);
      if(meMarker) map.removeLayer(meMarker);
      meMarker = L.circleMarker(ll, {radius:7, color:'#fff', weight:2,
        fillColor:'#3B82F6', fillOpacity:1}).addTo(map).bindTooltip('Та энд',
        {permanent:false, direction:'top'});
    });
  };
</script></body></html>''';

  StreamSubscription? _msgSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'leaflet-map-${_mapCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = html.IFrameElement()
        ..srcdoc = _buildHtml()
        ..allow = 'geolocation'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });

    // iframe доторх pin дарахад venue дэлгэц нээх (postMessage)
    _msgSub = html.window.onMessage.listen((e) {
      final d = e.data;
      if (d is String && d.startsWith('venue:')) {
        widget.onVenueTap?.call(d.substring(6));
      }
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
