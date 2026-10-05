/// Чат (DM + групп) дэлгэцүүдийн хуваалцсан токенууд.
library;

import 'package:flutter/widgets.dart';

/// Bubble-ийн хамгийн их өргөн — дэлгэцийн өргөний хувиар.
/// Өмнө нь групп чатад 0.68, энгийн DM-д 0.78, note/story хариултад 0.72 гэж
/// гурван өөр утга байсныг НЭГ утга болгож нэгтгэв.
const double kBubbleMaxWidthFactor = 0.72;

/// Keep the name and secondary label visible with enlarged accessibility text.
double chatToolbarHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final extra = (scaler.scale(19) - 19) + (scaler.scale(11) - 11);
  return 64 + (extra > 0 ? extra * 1.2 : 0);
}
