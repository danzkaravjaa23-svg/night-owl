/// Платформоос хамаарсан Web Share API дэмжлэг шалгагч
/// (web=navigator.share/canShare байгаа эсэх, бусад платформ=үргэлж true).
/// share_plus нь дэмжлэггүй browser дээр mailto: руу унадаг тул
/// урьдчилан шалгаж, clipboard fallback руу шилжихэд ашиглана.
library;
export 'web_share_stub.dart'
    if (dart.library.js_interop) 'web_share_web.dart';
