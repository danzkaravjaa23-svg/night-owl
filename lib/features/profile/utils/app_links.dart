/// Хуваалцах/урилгын холбоосыг АЖИЛЛАЖ БУЙ origin-оос үүсгэх туслахууд.
/// Хуучин nightowl.ub (.ub гэдэг TLD байхгүй — үхмэл домэйн) холбоосын оронд
/// веб дээр Uri.base-ээс жинхэнэ deploy хаягийг (Netlify г.м.) авна.
library;

/// Одоогийн deploy origin (ж: https://night-owl-ub.netlify.app).
/// Веб биш орчинд (тест) fallback хаяг буцаана.
String appOrigin() {
  try {
    final o = Uri.base.origin;
    if (o.startsWith('http')) return o;
  } catch (_) {
    // Uri.base нь http(s) биш үед origin шидэлт хийдэг — fallback руу унана
  }
  // TODO: app_constants.dart-д канон deploy origin нэмэгдвэл түүнийг ашиглах
  return 'https://nightowl-ub.netlify.app';
}

/// Урилгын холбоос — апп-ын үндсэн хуудас руу ref кодтой оруулна
/// (router-т /join route нэмэгдтэл root хаяг ашиглана — заавал нээгдэнэ).
String inviteLink(String refCode) => '${appOrigin()}/?ref=$refCode';

/// Профайл хуваалцах холбоос — hash routing тул #/creator/:id хэлбэртэй
String profileLink(String userId) => '${appOrigin()}/#/creator/$userId';
