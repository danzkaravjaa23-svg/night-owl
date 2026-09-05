import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import 'map_controller.dart';

int _mapCounter = 0;

/// Веб дээр интерактив газрын зураг — Leaflet + OpenStreetMap (үнэгүй,
/// API key/billing шаардахгүй). Pin дарвал venue нээх + миний байршил.
class GoogleMapView extends StatefulWidget {
  final double lat;
  final double lng;
  final int zoom;
  final String markersJson; // [{"id":"..","lat":..,"lng":..,"name":".."}]
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

class _GoogleMapViewState extends State<GoogleMapView> {
  late final String _viewType;
  html.IFrameElement? _iframe;

  // Leaflet + CARTO dark_all дэвсгэр зураг (2026/08-аас түлхүүр шаардана)
  /// CARTO дэвсгэр зургийн түлхүүр — тохируулаагүй бол хоосон (ус тэмдэгтэй).
  static String get _cartoKeyParam {
    const k = AppConstants.cartoBasemapKey;
    return k.isEmpty ? '' : '?key=$k';
  }

  String _buildHtml() => '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  html,body{height:100%;margin:0;background:#0a0a0f}
  #map{position:fixed;inset:0}
  /* Хотын гэрэл мэт неон tooltip */
  .vt{background:rgba(10,10,18,.88);border:1px solid rgba(0,229,255,.45);color:#fff;
      font:700 11px Inter,sans-serif;box-shadow:0 0 14px rgba(0,229,255,.25);
      padding:4px 10px;border-radius:10px;cursor:pointer;letter-spacing:.2px}
  .vt:before{display:none}
  /* Миний байршил товч — неон cyan шилэн */
  /* Zoom товч — баруун дээд (бар/carousel iframe-ийн ГАДНА тул offset хэрэггүй) */
  .leaflet-top.leaflet-right{top:10px}
  .leaflet-top.leaflet-right .leaflet-control-zoom{margin-right:14px}
  #loc{position:absolute;right:14px;bottom:16px;z-index:1000;width:48px;height:48px;
    border:1px solid rgba(0,229,255,.55);border-radius:50%;
    background:rgba(10,10,18,.8);color:#00E5FF;font-size:20px;
    box-shadow:0 0 18px rgba(0,229,255,.35), 0 4px 12px rgba(0,0,0,.5);
    cursor:pointer;backdrop-filter:blur(8px);transition:transform .15s}
  #loc:active{transform:scale(.92)}
  /* Zoom товчнууд — бараан шилэн */
  .leaflet-control-zoom a{background:rgba(10,10,18,.85)!important;color:#fff!important;
    border:1px solid rgba(255,255,255,.14)!important;backdrop-filter:blur(8px)}
  .leaflet-control-attribution{background:rgba(0,0,0,.4)!important;color:#666!important;
    font-size:9px!important}
  .leaflet-control-attribution a{color:#888!important}
  /* Зурагтай venue pin — неон хүрээ + гэрэлтэлт */
  .vpin{width:42px;height:42px;border-radius:50%;border:2px solid #FF3B7B;
    background-size:cover;background-position:center;cursor:pointer;
    box-shadow:0 0 14px rgba(255,59,123,.55), 0 2px 8px rgba(0,0,0,.6);
    transition:transform .15s}
  .vpin:hover{transform:scale(1.12)}
  /* Зураггүй venue — цохилдог неон цэг */
  .npin{position:relative;width:18px;height:18px;cursor:pointer}
  .npin .dot{position:absolute;inset:3px;border-radius:50%;background:#FF3B7B;
    border:2px solid #fff;box-shadow:0 0 10px rgba(255,59,123,.8)}
  .npin .ring{position:absolute;inset:0;border-radius:50%;
    border:2px solid rgba(255,59,123,.6);animation:pulse 1.8s ease-out infinite}
  @keyframes pulse{0%{transform:scale(.7);opacity:1}100%{transform:scale(2.2);opacity:0}}
  /* Жижиг toast — байршлын алдаа мэдэгдэнэ */
  #toast{position:absolute;left:50%;bottom:76px;transform:translateX(-50%);
    z-index:1100;background:rgba(10,10,18,.92);color:#fff;
    font:600 12px Inter,sans-serif;padding:8px 14px;border-radius:12px;
    border:1px solid rgba(255,69,102,.5);box-shadow:0 4px 14px rgba(0,0,0,.5);
    opacity:0;pointer-events:none;transition:opacity .25s}
</style></head><body><div id="map"></div>
<button id="loc" title="Миний байршил">📍</button>
<div id="toast"></div>
<script>
  var canvasR = L.canvas({padding: 0.7});
  var map = L.map('map',{zoomControl:false, preferCanvas:true, renderer: canvasR,
    dragging:true, inertia:true, inertiaDeceleration:2500,
    scrollWheelZoom:false}).setView([${widget.lat}, ${widget.lng}], ${widget.zoom});
  // Zoom товчнуудыг баруун дээд буланд (зүүн дээд нь буцах товчтой давхцдаг)
  L.control.zoom({position:'topright'}).addTo(map);
  // Google Maps-маягийн удирдлага: trackpad гүйлгэх = зөөх (бүх чиглэлд),
  // pinch/Ctrl+гүйлгэх = zoom. (Leaflet default нь гүйлгэхэд зөвхөн zoom
  // хийдэг тул баруун/зүүн хөдөлгөх боломжгүй байсан.)
  map.getContainer().addEventListener('wheel', function(e){
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) {
      var dir = e.deltaY < 0 ? 1 : -1;
      map.setZoomAround(map.mouseEventToLatLng(e), map.getZoom() + dir);
    } else {
      map.panBy([e.deltaX, e.deltaY], {animate:false});
    }
  }, {passive:false});
  // iframe layout хожуу тогтдог тул хэмжээг дахин тооцуулна (хар дэлгэц засна)
  function fixSize(){ map.invalidateSize(); }
  [150, 400, 900, 2000].forEach(function(ms){ setTimeout(fixSize, ms); });
  window.addEventListener('resize', fixSize);
  if (window.ResizeObserver) {
    new ResizeObserver(fixSize).observe(document.getElementById('map'));
  }
  // Эхний 6 секундэд хагас секунд тутам шалгана (iframe хожуу байрлах үед)
  var fixN = 0;
  var fixIv = setInterval(function(){ fixSize(); if(++fixN > 12) clearInterval(fixIv); }, 500);
  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png$_cartoKeyParam',
    {maxZoom:19, keepBuffer:5, updateWhenIdle:false, subdomains:'abcd',
     attribution:'© OpenStreetMap, © CARTO'}).addTo(map);
  var venues = ${widget.markersJson.replaceAll('<', r'\u003c')};
  // HTML escape — газрын нэр дотор тег байсан ч код болж ажиллахгүй
  function esc(t){ var d=document.createElement('div'); d.textContent=String(t||''); return d.innerHTML; }
  function safeUrl(u){ u=String(u||''); if(u.indexOf('https://')!==0 && u.indexOf('http://')!==0) return ''; return u.split('"').join('').split("'").join('').split(')').join('').split('(').join(''); }
  // Marker-уудыг тусдаа layer group-д — гаднаас шинэчлэхэд зөвхөн энэ
  // давхаргыг сольж, зураг өөрөө байрлал/zoom-оо хадгална (анивчихгүй).
  var venueLayer = L.layerGroup().addTo(map);
  function addVenues(list){
    venueLayer.clearLayers();
    list.forEach(function(v){
      if (v.lat==null || v.lng==null) return;
      var mk;
      var name = esc(v.name);
      if (v.img && safeUrl(v.img)) {
        // Эзэн зураг оруулсан бол дугуй зургийн marker
        var icon = L.divIcon({className:'', iconSize:[42,42], iconAnchor:[21,21],
          html:'<div class="vpin" style="background-image:url(\\''+safeUrl(v.img)+'\\')"></div>'});
        mk = L.marker([v.lat, v.lng], {icon:icon}).addTo(venueLayer)
          .bindTooltip(name, {permanent:false, direction:'top', className:'vt'});
      } else {
        // Зураггүй бол хөнгөн неон цэг (canvas — олон зуун pin-д хурдан)
        mk = L.circleMarker([v.lat, v.lng], {radius:7, color:'#fff', weight:2,
          fillColor:'#FF3B7B', fillOpacity:0.95}).addTo(venueLayer)
          .bindTooltip(name, {permanent:false, direction:'top', className:'vt'});
      }
      // Pin/нэр дарвал Flutter руу venue id илгээж дэлгэц нээнэ
      mk.on('click', function(){ if(v.id) parent.postMessage('venue:'+v.id,'*'); });
    });
  }
  addVenues(venues);
  // Гаднаас ирэх командууд (Flutter-ээс): center + markers шинэчлэлт
  window.addEventListener('message', function(e){
    if (typeof e.data !== 'string') return;
    if (e.data.indexOf('center:') === 0) {
      var p = e.data.slice(7).split(',');
      map.flyTo([parseFloat(p[0]), parseFloat(p[1])], parseInt(p[2]||15), {duration:0.8});
    } else if (e.data.indexOf('markers:') === 0) {
      try { addVenues(JSON.parse(e.data.slice(8))); } catch(err) {}
    }
  });
  // Жижиг toast — хэрэглэгчид товч мэдээлэл
  var toastTimer = null;
  function toast(t){
    var d = document.getElementById('toast');
    d.textContent = t; d.style.opacity = '1';
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function(){ d.style.opacity = '0'; }, 2400);
  }
  // Миний байршил — татгалзсан/алдааг заавал мэдэгдэнэ
  var meMarker = null;
  document.getElementById('loc').onclick = function(){
    if(!navigator.geolocation){ toast('Байршил идэвхгүй байна'); return; }
    navigator.geolocation.getCurrentPosition(function(p){
      var ll = [p.coords.latitude, p.coords.longitude];
      map.setView(ll, 15);
      if(meMarker) map.removeLayer(meMarker);
      meMarker = L.circleMarker(ll, {radius:7, color:'#fff', weight:2,
        fillColor:'#00E5FF', fillOpacity:1}).addTo(map).bindTooltip('Та энд',
        {permanent:false, direction:'top', className:'vt'});
    }, function(){ toast('Байршил идэвхгүй байна'); });
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
      _iframe = iframe;
      return iframe;
    });

    // Гаднаас center() дуудахад iframe доторх Leaflet руу мессеж илгээнэ
    widget.controller?.centerImpl = (lat, lng, {int zoom = 15}) {
      _iframe?.contentWindow?.postMessage('center:$lat,$lng,$zoom', '*');
    };

    // iframe доторх pin дарахад venue дэлгэц нээх (postMessage)
    _msgSub = html.window.onMessage.listen((e) {
      final d = e.data;
      if (d is String && d.startsWith('venue:')) {
        widget.onVenueTap?.call(d.substring(6));
      }
    });
  }

  @override
  void didUpdateWidget(covariant GoogleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Marker өгөгдөл өөрчлөгдвөл iframe-ийг дахин үүсгэлгүй, доторх
    // Leaflet layer group-ийг postMessage-ээр шинэчилнэ (байрлал хадгална)
    if (oldWidget.markersJson != widget.markersJson) {
      _iframe?.contentWindow?.postMessage('markers:${widget.markersJson}', '*');
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
