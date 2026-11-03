import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../data/venue_operating_reviews.dart';

/// Public source evidence is intentionally separate from community verification
/// and the live story activity shown on the map.
class VenueOperatingReview extends StatefulWidget {
  final List<String> venueRefs;
  final VenueOperatingReviewLoader? loader;
  final Future<bool> Function(Uri)? openUri;
  final DateTime Function()? now;

  const VenueOperatingReview({
    super.key,
    required this.venueRefs,
    this.loader,
    this.openUri,
    this.now,
  });

  @override
  State<VenueOperatingReview> createState() => _VenueOperatingReviewState();
}

class _VenueOperatingReviewState extends State<VenueOperatingReview> {
  late Future<VenueOperatingReviewCatalog> _catalog;
  bool _opening = false;
  String? _linkError;
  int _scope = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _catalog = Future.sync(
      widget.loader ?? VenueOperatingReviewCatalog.loadBundled,
    );
  }

  @override
  void didUpdateWidget(covariant VenueOperatingReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) _load();
    if (!listEquals(oldWidget.venueRefs, widget.venueRefs)) {
      _scope++;
      _linkError = null;
      _opening = false;
    }
  }

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    final scope = _scope;
    setState(() {
      _opening = true;
      _linkError = null;
    });
    try {
      final opened = await (widget.openUri?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (mounted && scope == _scope && !opened) {
        setState(
            () => _linkError = 'Эх сурвалж нээгдсэнгүй. Дахин оролдоорой.');
      }
    } catch (_) {
      if (mounted && scope == _scope) {
        setState(
            () => _linkError = 'Эх сурвалж нээгдсэнгүй. Дахин оролдоорой.');
      }
    } finally {
      if (mounted && scope == _scope) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground =
        dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final muted =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final accent = dark ? AppColors.neonCyanDark : AppColors.neonCyanLight;
    return FutureBuilder<VenueOperatingReviewCatalog>(
      future: _catalog,
      builder: (context, snapshot) {
        var title = 'Үйл ажиллагааны мэдээлэл';
        var summary = 'Эх сурвалжийн мэдээллийг уншиж байна…';
        VenueOperatingEvidenceReview? review;
        VenueReviewFreshness? freshness;
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError) {
          title = 'Мэдээлэл уншигдсангүй';
          summary =
              'Үйл ажиллагааны эх сурвалжийг одоогоор харуулах боломжгүй. '
              'Энэ нь газар хаалттай гэсэн үг биш.';
        } else if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          final selection = snapshot.data!.select(widget.venueRefs);
          review = selection.review;
          if (selection.conflicting) {
            title = 'Байршлыг дахин нягтлах шаардлагатай';
            summary = 'Холбогдсон газрын мэдээлэл зөрүүтэй байна. '
                'Очихын өмнө тухайн газрын албан ёсны мэдээллийг шалгаарай.';
          } else if (review == null) {
            title = 'Үйл ажиллагаа баталгаажаагүй';
            summary =
                'Газрын зурагт бүртгэлтэй байх нь өнөөдөр ажиллаж байгааг '
                'батлахгүй. Очихын өмнө тухайн газрын цаг, хаягийг шалгаарай.';
          } else {
            freshness =
                review.freshnessAt(widget.now?.call() ?? DateTime.now());
            title = switch (freshness) {
              VenueReviewFreshness.stale => 'Мэдээллийг дахин нягтлах хэрэгтэй',
              VenueReviewFreshness.future => 'Мэдээллийн огноо баталгаажаагүй',
              _ => switch (review.status) {
                  VenueOperatingEvidence.recentActivity =>
                    'Огноотой үйл ажиллагааны мэдээлэл бий',
                  VenueOperatingEvidence.publishedHours =>
                    'Нийтэлсэн цагийн мэдээлэл бий',
                  VenueOperatingEvidence.needsReview =>
                    'Нэмэлт нягтлал шаардлагатай',
                },
            };
            summary = review.summary;
          }
        }
        return Container(
          key: const ValueKey('venue-operating-review'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: .18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.4)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(summary,
                  style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
              if (snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasError)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _linkError = null;
                    _load();
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Дахин унших'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
              if (review != null) ...[
                const SizedBox(height: 8),
                if (freshness == VenueReviewFreshness.stale)
                  Text(
                      'Эх сурвалжийн мэдээлэл хуучирсан. '
                      'Шинэ мэдээлэл авах шаардлагатай.',
                      style: TextStyle(
                          color: foreground, fontSize: 12, height: 1.5)),
                if (freshness == VenueReviewFreshness.future)
                  Text('Огноо зөрүүтэй тул одоогийн мэдээлэл гэж үзэхгүй.',
                      style: TextStyle(
                          color: foreground, fontSize: 12, height: 1.5)),
                Text(
                    'Эх сурвалж нягталсан: ${_day(review.checkedAt, local: true)}',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
                if (review.evidenceDate != null)
                  Text('Мэдээллийн огноо: ${_day(review.evidenceDate!)}',
                      style:
                          TextStyle(color: muted, fontSize: 11, height: 1.5)),
                if (review.publishedHours case final hours?) ...[
                  const SizedBox(height: 6),
                  Text(
                      'Эх сурвалжид нийтэлсэн цаг: '
                      '${hours.opens} – ${hours.closes}',
                      style: TextStyle(
                          color: foreground, fontSize: 12, height: 1.5)),
                  Text(hours.weekdayNote,
                      style:
                          TextStyle(color: muted, fontSize: 11, height: 1.5)),
                ],
                const SizedBox(height: 6),
                Text('Энэ мэдээлэл яг одоо нээлттэй эсэхийг батлахгүй.',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
                for (final source in review.sources)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _opening ? null : () => _open(source.url),
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: const Size(0, 44),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.open_in_new_rounded, size: 15),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(source.label,
                                style:
                                    const TextStyle(fontSize: 12, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (_linkError != null)
                Text(_linkError!,
                    style: TextStyle(
                        color: dark ? AppColors.error : const Color(0xFFB81F40),
                        fontSize: 12,
                        height: 1.5)),
            ],
          ),
        );
      },
    );
  }
}

String _day(DateTime value, {bool local = false}) {
  final date = local ? value.toUtc().add(const Duration(hours: 8)) : value;
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
