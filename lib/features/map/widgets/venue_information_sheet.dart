import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../models/venue.dart';

/// Public venue links use the place name/address, never the user's position.
Uri venueGoogleMapsUrl(Venue venue) {
  final address = venue.address?.trim();
  var query =
      '${venue.name}, ${address?.isNotEmpty == true ? address : 'Улаанбаатар'}';
  query = String.fromCharCodes(query.runes.take(240));
  Uri build() => Uri.https(
      'www.google.com', '/maps/search/', {'api': '1', 'query': query});
  // Google Maps URLs have a 2,048 character limit, including URL encoding.
  while (build().toString().length > 2000) {
    final runes = query.runes.toList();
    query = String.fromCharCodes(runes.take(runes.length - 1));
  }
  return build();
}

Uri? venueWebsiteUrl(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null ||
      !const {'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Uri? venuePhoneUrl(String? value) {
  final first = value?.split(';').first.trim() ?? '';
  if (first.isEmpty || !RegExp(r'^\+?[0-9() \-]+$').hasMatch(first)) {
    return null;
  }
  final number = first.replaceAll(RegExp(r'[^0-9+]'), '');
  final digits = number.replaceAll('+', '').length;
  return digits >= 5 && digits <= 15 ? Uri(scheme: 'tel', path: number) : null;
}

String? venueRecordedHours(Venue venue) {
  const days = {
    'mon': 'Даваа',
    'tue': 'Мягмар',
    'wed': 'Лхагва',
    'thu': 'Пүрэв',
    'fri': 'Баасан',
    'sat': 'Бямба',
    'sun': 'Ням'
  };
  final entries = <String>[
    for (final day in days.entries)
      if (venue.openingHours[day.key]?.trim().isNotEmpty == true)
        '${day.value}: ${venue.openingHours[day.key]!.trim()}',
  ];
  if (entries.isNotEmpty) return entries.join('\n');
  final start = venue.openTime?.trim();
  final end = venue.closeTime?.trim();
  return start?.isNotEmpty == true && end?.isNotEmpty == true
      ? '$start – $end'
      : null;
}

/// Supplemental catalog places expose public information and directions.
/// They do not call community RPCs until a real backend venue has been matched.
class VenueInformationSheet extends StatefulWidget {
  final Venue venue;
  final Future<bool> Function(Uri)? openUri;
  const VenueInformationSheet({super.key, required this.venue, this.openUri});

  @override
  State<VenueInformationSheet> createState() => _VenueInformationSheetState();
}

class _VenueInformationSheetState extends State<VenueInformationSheet> {
  String? _error;
  bool _opening = false;

  Future<void> _open(Uri uri) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final opened = await (widget.openUri?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (mounted && !opened) {
        setState(() => _error = 'Холбоос нээгдсэнгүй. Дахин оролдоорой.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Холбоос нээгдсэнгүй. Дахин оролдоорой.');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final venue = widget.venue;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground =
        dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final muted =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final surface = dark ? AppColors.bgSurfaceDark : AppColors.bgSurfaceLight;
    final website = venueWebsiteUrl(venue.websiteUrl);
    final phone = venuePhoneUrl(venue.phone);
    final source = venueWebsiteUrl(venue.sourceUrl ?? venue.locationSourceUrl);
    final ownedHours = venueRecordedHours(venue);
    final hours = ownedHours ?? venue.sourceOpeningHours?.trim();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: muted.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 20),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: surface, borderRadius: BorderRadius.circular(18)),
              child: const NightOwlMark(size: 40),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.name,
                        style: TextStyle(
                            color: foreground,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(venue.typeLabel,
                        style: TextStyle(color: muted, fontSize: 13)),
                  ]),
            ),
            IconButton(
                tooltip: 'Хаах',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: 24),
          _info(
              Icons.location_on_outlined,
              'Хаяг',
              venue.address?.trim().isNotEmpty == true
                  ? venue.address!
                  : 'Хаягийн дэлгэрэнгүй нэмэгдээгүй',
              foreground,
              muted),
          if (hours?.isNotEmpty == true)
            _info(
                Icons.schedule_rounded,
                ownedHours == null
                    ? 'OpenStreetMap-ийн цаг'
                    : 'Газрын бүртгэлийн цаг',
                hours!,
                foreground,
                muted),
          if (phone != null)
            _info(Icons.call_outlined, 'Утас',
                venue.phone!.split(';').first.trim(), foreground, muted),
          if (website != null)
            _info(Icons.language_rounded, 'Вэбсайт', website.host, foreground,
                muted),
          const SizedBox(height: 12),
          Text('Ажиллах цаг, хаягаа очихын өмнө шалгаарай.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: PressFeedback(
                enabled: !_opening,
                child: FilledButton.icon(
                  onPressed:
                      _opening ? null : () => _open(venueGoogleMapsUrl(venue)),
                  icon: _opening
                      ? const OwlLoading(size: 20, compact: true)
                      : const Icon(Icons.map_outlined, size: 20),
                  label: const Text('Google Maps-д харах'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7654D6),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48)),
                )),
          ),
          if (website != null || phone != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              if (phone != null)
                OutlinedButton.icon(
                    onPressed: _opening ? null : () => _open(phone),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Залгах')),
              if (website != null)
                OutlinedButton.icon(
                    onPressed: _opening ? null : () => _open(website),
                    icon: const Icon(Icons.language_rounded, size: 18),
                    label: const Text('Вэбсайт нээх')),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
                semanticsLabel: _error),
          ],
          if (source != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _opening ? null : () => _open(source),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text('${venue.sourceLabel ?? 'Байршлын'} эх сурвалж'),
            ),
          ],
          if (venue.sourceLabel == 'OpenStreetMap')
            TextButton(
              onPressed: _opening
                  ? null
                  : () =>
                      _open(Uri.https('www.openstreetmap.org', '/copyright')),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: muted,
                  visualDensity: VisualDensity.compact),
              child: const Text('© OpenStreetMap contributors · ODbL',
                  style: TextStyle(fontSize: 11)),
            ),
          if (venue.sourceRetrievedAt != null) ...[
            const SizedBox(height: 5),
            Text(
                'Мэдээлэл авсан: ${venue.sourceRetrievedAt!.toIso8601String().split('T').first}',
                style: TextStyle(color: muted, fontSize: 11)),
          ],
        ]),
      ),
    );
  }

  Widget _info(IconData icon, String label, String value, Color foreground,
          Color muted) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 21, color: muted),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                        color: foreground, fontSize: 14, height: 1.4)),
              ])),
        ]),
      );
}
