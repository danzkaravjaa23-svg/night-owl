/// Web хостинг (Netlify free plan) баруун доод буланд "Powered by Netlify"
/// iframe badge оруулдаг. Үүнийг нуух/хөдөлгөх/хаахгүй — оронд нь апп
/// өөрөө доороо badge-ийн өндөртэй зай үлдээж, товчнууд badge-ийн доор
/// орохгүй байлгана. Badge байхгүй үед (локал, Android/iOS, өөр хостинг,
/// badge-гүй plan) зай 0. Android/iOS дээр мод огт өөрчлөгдөхгүй; web
/// дээр бүтэц тогтмол, зөвхөн зайн утга өөрчлөгдөнө.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'host_badge_rect_stub.dart'
    if (dart.library.js_interop) 'host_badge_rect_web.dart' as platform;

export 'host_badge_rect_stub.dart'
    if (dart.library.js_interop) 'host_badge_rect_web.dart';

/// Badge-ээс дээш үлдээх нэмэлт зай.
const double hostBadgeGap = 8;

/// Үүнээс өндөр "badge" бол буруу танисан гэж үзээд зай үлдээхгүй.
const double hostBadgeMaxHeight = 160;

/// Цэвэр функц: цонхны хэмжээ, аппын баганын өргөн (MobileFrame нь
/// баганыг цонхны голд байрлуулдаг), badge-ийн rect (CSS px = Flutter
/// logical px) → доор үлдээх зай.
///
/// Badge байхгүй, эсвэл бүхэлдээ хажуугийн хоосон зайд (баганатай
/// хэвтээ давхцахгүй) бол 0.
double hostBadgeInset({
  required Size window,
  required double columnWidth,
  required Rect? badge,
  double gap = hostBadgeGap,
}) {
  if (badge == null || badge.isEmpty) return 0;
  if (badge.height > hostBadgeMaxHeight) return 0;
  final column = math.min(columnWidth, window.width);
  final columnLeft = (window.width - column) / 2;
  final columnRight = columnLeft + column;
  final overlaps = badge.left < columnRight && badge.right > columnLeft;
  if (!overlaps) return 0;
  final covered = window.height - badge.top;
  if (covered <= 0) return 0;
  return math.min(covered, hostBadgeMaxHeight) + gap;
}

/// Аппын баганыг (MobileFrame-ийн дотор) badge-ийн өндрөөр доороос нь
/// scaffold-ийн дэвсгэр өнгөөр дүүргэж зай үлдээнэ. Зөвхөн web дээр
/// идэвхтэй. MediaQuery-ийн padding-д нэмдэггүй (давхар зай гарахгүй);
/// харин энэ зай аль хэдийн эзэлсэн доод padding/viewInsets-ийг хасна.
class HostBadgeInset extends StatelessWidget {
  final Widget child;

  /// Тестэд солих боломжтой; анхдагч нь [kIsWeb].
  final bool enabled;

  /// Тестэд солих боломжтой; анхдагч нь платформын [hostBadgeRect].
  final ValueListenable<Rect?>? badge;

  const HostBadgeInset({
    super.key,
    required this.child,
    this.enabled = kIsWeb,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ValueListenableBuilder<Rect?>(
      valueListenable: badge ?? platform.hostBadgeRect,
      child: child,
      builder: (context, rect, child) {
        // Модны бүтэц үргэлж ижил (ColoredBox > Padding > MediaQuery):
        // badge гарч ирэх/алга болох, давхцал эхлэх/дуусах үед зөвхөн зайн
        // утга өөрчлөгдөнө — доорх Router болон хуудсууд дахин mount
        // хийгдэхгүй, state хадгалагдана.
        final mq = MediaQuery.of(context);
        var inset = 0.0;
        if (rect != null) {
          final view = View.of(context);
          final window = view.physicalSize / view.devicePixelRatio;
          inset = hostBadgeInset(
              window: window, columnWidth: mq.size.width, badge: rect);
          if (inset <= 0 || inset >= mq.size.height) inset = 0;
        }
        double less(double v) => math.max(0, v - inset);
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: MediaQuery(
              data: inset == 0
                  ? mq
                  : mq.copyWith(
                      size: Size(mq.size.width, mq.size.height - inset),
                      padding:
                          mq.padding.copyWith(bottom: less(mq.padding.bottom)),
                      viewPadding: mq.viewPadding
                          .copyWith(bottom: less(mq.viewPadding.bottom)),
                      viewInsets: mq.viewInsets
                          .copyWith(bottom: less(mq.viewInsets.bottom)),
                    ),
              child: child!,
            ),
          ),
        );
      },
    );
  }
}
