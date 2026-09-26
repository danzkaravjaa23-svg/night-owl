// Live дамжуулалт браузерийн getUserMedia/MediaRecorder дээр суурилсан тул
// native (Android/iOS) дээр stub дэлгэц харуулна.
export 'go_live_stub.dart' if (dart.library.html) 'go_live_screen.dart';
