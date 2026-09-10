import 'package:flutter/material.dart';

/// NightOwl UB — булангийн радиусын нэгдсэн токен.
/// Өмнө нь апп даяар 19 өөр радиус (2,4,5,...,31,999) хэрэглэгдэж байсныг
/// 4 үндсэн шатлал болгож нэгтгэв. Шинэ код ЗӨВХӨН эдгээрийг ашиглана.
abstract class AppRadii {
  /// 8 — чип, шошго, жижиг зураг/inset, skeleton мөр.
  static const double sm = 8;

  /// 14 — талбар (input), товч, жижиг хяналтын элемент.
  static const double md = 14;

  /// 20 — карт, жагсаалтын мөр (tile), медиа хайрцаг.
  static const double lg = 20;

  /// 28 — доод sheet (bottom sheet), том модаль хуудас.
  static const double xl = 28;

  /// 999 — бүрэн дугуй "эм" хэлбэр (pill): фильтр чип, avatar, дугуй товч.
  static const double pill = 999;

  // ─── Бэлэн BorderRadius getter-ууд (давтан бичихээс сэргийлнэ) ───

  /// [sm] радиустай бүх талын BorderRadius.
  static BorderRadius get smR => BorderRadius.circular(sm);

  /// [md] радиустай бүх талын BorderRadius.
  static BorderRadius get mdR => BorderRadius.circular(md);

  /// [lg] радиустай бүх талын BorderRadius.
  static BorderRadius get lgR => BorderRadius.circular(lg);

  /// [xl] радиустай бүх талын BorderRadius.
  static BorderRadius get xlR => BorderRadius.circular(xl);

  /// [pill] радиустай бүх талын BorderRadius — эм хэлбэр.
  static BorderRadius get pillR => BorderRadius.circular(pill);
}
