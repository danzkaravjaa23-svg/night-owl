import 'package:flutter/material.dart';

/// NightOwl UB — зайн (spacing) нэгдсэн токен. 4px суурьтай шатлал.
/// Шинэ код SizedBox/EdgeInsets-д эдгээрийг ашиглана.
abstract class AppSpacing {
  /// 4 — хамгийн нягт зай (icon ↔ тоо, badge дотор).
  static const double x1 = 4;

  /// 8 — элемент хоорондын жижиг зай.
  static const double x2 = 8;

  /// 12 — жагсаалтын мөр доторх зай.
  static const double x3 = 12;

  /// 16 — блок хоорондын стандарт зай.
  static const double x4 = 16;

  /// 20 — хуудасны хажуугийн зай, том блок хоорондын зай.
  static const double x5 = 20;

  /// 24 — хэсэг (section) хоорондын зай.
  static const double x6 = 24;

  /// 32 — том хэсэг тусгаарлах зай.
  static const double x8 = 32;

  /// Хуудасны хажуугийн стандарт зай (420px MobileFrame дотор).
  static const double page = 20;

  /// Хуудасны хэвтээ padding — Padding(padding: AppSpacing.pageH).
  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: page);

  /// Shell allocates the footer's height itself. Only a little scroll
  /// breathing room is needed above the fixed navigation bar.
  static const double dockClearance = 16;
}
