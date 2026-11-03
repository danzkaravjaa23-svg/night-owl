import 'package:flutter/material.dart';

/// Author-facing state; approval never changes the original publication clock.
class ContentReviewNotice extends StatelessWidget {
  final String status;
  final bool onDark;
  final bool profile;
  const ContentReviewNotice(
      {super.key,
      required this.status,
      this.onDark = false,
      this.profile = false});
  @override
  Widget build(BuildContext context) {
    if (status == 'approved') return const SizedBox.shrink();
    final rejected = status == 'rejected';
    final text = profile
        ? rejected
            ? 'Профайлын өөрчлөлтийг зөвшөөрөөгүй. Өмнөх баталсан мэдээлэл хэвээр байна.'
            : 'Профайлын өөрчлөлтийг шалгаж байна. Баталсны дараа нийтэд харагдана.'
        : rejected
            ? 'Зөвшөөрөөгүй. Дүрмээ шалгаж, агуулгаа засварлан дахин илгээгээрэй.'
            : 'Шалгаж байна · Баталсны дараа бусдад харагдана.';
    final color =
        onDark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(rejected ? Icons.info_outline : Icons.schedule_rounded,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, height: 1.4, color: color))),
        ]));
  }
}

void showSubmittedForReview(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Шалгалтад илгээлээ. Баталсны дараа бусдад харагдана.')));
