import 'dart:convert';

import 'package:flutter/services.dart';

enum VenueOperatingEvidence {
  recentActivity,
  publishedHours,
  needsReview,
}

enum VenueReviewFreshness { current, stale, future }

class VenueReviewSource {
  final String label;
  final String kind;
  final Uri url;

  const VenueReviewSource({
    required this.label,
    required this.kind,
    required this.url,
  });
}

class VenuePublishedHours {
  final String opens;
  final String closes;
  final String weekdayNote;

  const VenuePublishedHours({
    required this.opens,
    required this.closes,
    required this.weekdayNote,
  });
}

/// Evidence about a public listing, never a live open/closed determination.
class VenueOperatingEvidenceReview {
  final String venueRef;
  final VenueOperatingEvidence status;
  final String summary;
  final DateTime checkedAt;
  final DateTime? evidenceDate;
  final VenuePublishedHours? publishedHours;
  final List<VenueReviewSource> sources;

  const VenueOperatingEvidenceReview({
    required this.venueRef,
    required this.status,
    required this.summary,
    required this.checkedAt,
    required this.evidenceDate,
    required this.publishedHours,
    required this.sources,
  });

  VenueReviewFreshness freshnessAt(DateTime now) {
    final instant = now.toUtc();
    if (checkedAt.isAfter(instant)) return VenueReviewFreshness.future;
    if (instant.difference(checkedAt) > const Duration(days: 30)) {
      return VenueReviewFreshness.stale;
    }
    // Event publication dates are calendar dates in Ulaanbaatar, not instants.
    if (evidenceDate != null) {
      final local = instant.add(const Duration(hours: 8));
      final today = DateTime.utc(local.year, local.month, local.day);
      if (evidenceDate!.isAfter(today)) return VenueReviewFreshness.future;
      if (status == VenueOperatingEvidence.recentActivity &&
          today.difference(evidenceDate!) > const Duration(days: 30)) {
        return VenueReviewFreshness.stale;
      }
    }
    return VenueReviewFreshness.current;
  }
}

class VenueReviewSelection {
  final VenueOperatingEvidenceReview? review;
  final bool conflicting;

  const VenueReviewSelection({this.review, this.conflicting = false});
}

typedef VenueOperatingReviewLoader = Future<VenueOperatingReviewCatalog>
    Function();

class VenueOperatingReviewCatalog {
  final Map<String, VenueOperatingEvidenceReview> reviews;

  VenueOperatingReviewCatalog._(
    Map<String, VenueOperatingEvidenceReview> reviews,
  ) : reviews = Map.unmodifiable(reviews);

  factory VenueOperatingReviewCatalog.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map ||
        decoded['schema_version'] != 1 ||
        decoded['reviews'] is! List ||
        (decoded['reviews'] as List).length > 500) {
      throw const FormatException('Invalid venue review catalog');
    }
    final result = <String, VenueOperatingEvidenceReview>{};
    for (final raw in decoded['reviews'] as List) {
      if (raw is! Map) {
        throw const FormatException('Invalid venue review');
      }
      final ref = _string(raw['venue_ref'], 80);
      if (!RegExp(r'^osm:(node|way|relation):[1-9][0-9]{0,19}$')
          .hasMatch(ref)) {
        throw const FormatException('Invalid venue review reference');
      }
      if (result.containsKey(ref)) {
        throw const FormatException('Duplicate venue review reference');
      }
      final status = switch (raw['status']) {
        'evidence_recent_activity' => VenueOperatingEvidence.recentActivity,
        'published_hours_only' => VenueOperatingEvidence.publishedHours,
        'needs_review' => VenueOperatingEvidence.needsReview,
        _ => throw const FormatException('Invalid venue review status'),
      };
      final checkedText = _string(raw['checked_at'], 40);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
          .hasMatch(checkedText)) {
        throw const FormatException('Invalid venue review timestamp');
      }
      _date(checkedText.substring(0, 10));
      final checked = DateTime.tryParse(checkedText);
      if (checked == null ||
          checked.hour != int.parse(checkedText.substring(11, 13)) ||
          checked.minute != int.parse(checkedText.substring(14, 16)) ||
          checked.second != int.parse(checkedText.substring(17, 19))) {
        throw const FormatException('Invalid venue review timestamp');
      }
      final evidence = raw['evidence_date'] == null
          ? null
          : _date(_string(raw['evidence_date'], 10));
      final checkedLocal = checked.add(const Duration(hours: 8));
      final checkedDay = DateTime.utc(
        checkedLocal.year,
        checkedLocal.month,
        checkedLocal.day,
      );
      if (evidence != null && evidence.isAfter(checkedDay)) {
        throw const FormatException('Evidence is later than its review');
      }
      final sourcesRaw = raw['sources'];
      if (sourcesRaw is! List || sourcesRaw.isEmpty || sourcesRaw.length > 2) {
        throw const FormatException('Invalid venue evidence sources');
      }
      final sources = <VenueReviewSource>[];
      for (final item in sourcesRaw) {
        if (item is! Map) {
          throw const FormatException('Invalid venue evidence source');
        }
        final kind = _string(item['kind'], 40);
        if (!const {
          'official',
          'business_menu',
          'tenant_directory',
          'secondary_directory',
        }.contains(kind)) {
          throw const FormatException('Invalid source authority');
        }
        final urlText = _string(item['url'], 2048);
        final url = Uri.tryParse(urlText);
        if (url == null ||
            !const {'http', 'https'}.contains(url.scheme) ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty ||
            urlText.contains(RegExp(r'[\x00-\x20\x7f]'))) {
          throw const FormatException('Unsafe venue evidence URL');
        }
        sources.add(VenueReviewSource(
          label: _string(item['label'], 100),
          kind: kind,
          url: url,
        ));
      }
      if (status == VenueOperatingEvidence.recentActivity &&
          (evidence == null || !sources.any((s) => s.kind == 'official'))) {
        throw const FormatException('Dated official activity required');
      }
      VenuePublishedHours? hours;
      final hoursRaw = raw['published_hours'];
      if (hoursRaw != null) {
        if (hoursRaw is! Map) {
          throw const FormatException('Invalid published hours');
        }
        final opens = _string(hoursRaw['opens'], 5);
        final closes = _string(hoursRaw['closes'], 5);
        final time = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
        if (!time.hasMatch(opens) || !time.hasMatch(closes)) {
          throw const FormatException('Invalid published hours');
        }
        hours = VenuePublishedHours(
          opens: opens,
          closes: closes,
          weekdayNote: _string(hoursRaw['weekday_note'], 200),
        );
      }
      if (status == VenueOperatingEvidence.publishedHours && hours == null) {
        throw const FormatException('Published hours required');
      }
      result[ref] = VenueOperatingEvidenceReview(
        venueRef: ref,
        status: status,
        summary: _string(raw['summary'], 700),
        checkedAt: checked,
        evidenceDate: evidence,
        publishedHours: hours,
        sources: List.unmodifiable(sources),
      );
    }
    return VenueOperatingReviewCatalog._(result);
  }

  /// Duplicate aliases collapse to one entry. Multiple business identities do
  /// not borrow the most positive review from one another.
  VenueReviewSelection select(Iterable<String> venueRefs) {
    final matches = <String, VenueOperatingEvidenceReview>{};
    for (final value in venueRefs) {
      final ref = canonicalOperatingVenueRef(value);
      final review = reviews[ref];
      if (review != null) matches[review.venueRef] = review;
    }
    if (matches.length > 1) {
      return const VenueReviewSelection(conflicting: true);
    }
    return VenueReviewSelection(
      review: matches.isEmpty ? null : matches.values.single,
    );
  }

  static Future<VenueOperatingReviewCatalog>? _bundle;

  static Future<VenueOperatingReviewCatalog> loadBundled() {
    return _bundle ??= _readBundle();
  }

  static Future<VenueOperatingReviewCatalog> _readBundle() async {
    try {
      return VenueOperatingReviewCatalog.parse(
        await rootBundle.loadString('assets/data/venue_operating_reviews.json'),
      );
    } catch (_) {
      _bundle = null;
      rethrow;
    }
  }
}

String _string(Object? value, int max) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > max ||
      value.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
    throw const FormatException('Invalid venue review text');
  }
  return value.trim();
}

DateTime _date(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid evidence date');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid evidence date');
  }
  return parsed;
}

String? canonicalOperatingVenueRef(String value) {
  final trimmed = value.trim();
  if (RegExp(r'^osm:(node|way|relation):[1-9][0-9]{0,19}$').hasMatch(trimmed)) {
    return trimmed;
  }
  if (trimmed.length > 2048 || trimmed.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri != null &&
      const {'http', 'https'}.contains(uri.scheme) &&
      const {'www.openstreetmap.org', 'openstreetmap.org'}.contains(uri.host) &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      RegExp(r'^/(node|way|relation)/[1-9][0-9]{0,19}/?$').hasMatch(uri.path)) {
    final path = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    return 'osm:${path[0]}:${path[1]}';
  }
  return null;
}
