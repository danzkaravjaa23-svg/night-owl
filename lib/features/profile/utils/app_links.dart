/// Хуваалцах/урилгын холбоосыг АЖИЛЛАЖ БУЙ origin-оос үүсгэх туслахууд.
/// Хуучин nightowl.ub (.ub гэдэг TLD байхгүй — үхмэл домэйн) холбоосын оронд
/// веб дээр Uri.base-ээс жинхэнэ deploy хаягийг (Netlify г.м.) авна.
library;

import '../../../core/constants/app_constants.dart';

/// Одоогийн deploy origin (ж: https://nightowl-ub.netlify.app).
/// Веб биш орчинд (native апп, тест) fallback хаяг буцаана.
String appOrigin() {
  try {
    final o = Uri.base.origin;
    if (o.startsWith('http')) return o;
  } catch (_) {
    // Uri.base нь http(s) биш үед origin шидэлт хийдэг — fallback руу унана
  }
  return AppConstants.publicAppUrl;
}

/// Урилгын холбоос — апп-ын үндсэн хуудас руу ref кодтой оруулна
/// (router-т /join route нэмэгдтэл root хаяг ашиглана — заавал нээгдэнэ).
String inviteLink(String refCode) => Uri.parse('${appOrigin()}/').replace(queryParameters: {'ref': refCode}).toString();

/// Профайл хуваалцах холбоос — hash routing тул #/creator/:id хэлбэртэй
String profileLink(String userId) => '${appOrigin()}/#/creator/${Uri.encodeComponent(userId)}';
