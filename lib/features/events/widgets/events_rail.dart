import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/event_provider.dart';

const _kMonths = ['', '1-р сар','2-р сар','3-р сар','4-р сар','5-р сар','6-р сар',
  '7-р сар','8-р сар','9-р сар','10-р сар','11-р сар','12-р сар'];

class EventsRail extends ConsumerWidget {
  const EventsRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(upcomingEventsProvider).value ?? [];
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          const Text('🎉 ', style: TextStyle(fontSize: 15)),
          Text('Удахгүй болох эвентүүд', style: AppTextStyles.labelMd.copyWith(
            color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        ]),
      ),
      SizedBox(
        height: 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => _EventCard(event: events[i]),
        ),
      ),
      const SizedBox(height: 8),
    ]);
  }
}

class _EventCard extends StatelessWidget {
  final EventItem event;
  const _EventCard({required this.event});

  void _showDetail(BuildContext context) => showEventDetailSheet(context, event);

  static String _dateStr(DateTime d) {
    final l = d.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day} ${_kMonths[l.month]}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: SizedBox(
        width: 210,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [
            // ── Бүтэн зураг (full-bleed) ──
            event.coverUrl != null
              ? CachedNetworkImage(imageUrl: event.coverUrl!, fit: BoxFit.cover,
                  placeholder: (_, __) => _coverPlaceholder(),
                  errorWidget: (_, __, ___) => _coverPlaceholder())
              : _coverPlaceholder(),

            // ── Доод бараан gradient (текст уншигдахуйц) ──
            const DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0x33000000),
                  Color(0xCC000000),
                  Color(0xF2000000),
                ],
                stops: [0.32, 0.52, 0.78, 1.0]))),

            // ── Неон social-proof badge (баруун дээд буланд) ──
            Positioned(top: 10, right: 10, child: _SocialBadge(text: _socialProof())),

            // ── Текст контент (доод хэсэг) ──
            Positioned(left: 12, right: 12, bottom: 12,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
                  Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w800, height: 1.15,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black87)])),
                  const SizedBox(height: 5),
                  Row(children: [
                    const Icon(Icons.location_on, size: 12, color: Colors.white70),
                    const SizedBox(width: 3),
                    Expanded(child: Text(event.venueName ?? '—',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black87)]))),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(_dateStr(event.startsAt),
                      style: const TextStyle(color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black87)])),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10)),
                      child: Text(event.price == 0 ? 'Үнэгүй' : '₮${event.price}',
                        style: const TextStyle(color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w800))),
                  ]),
                ])),
          ]),
        ),
      ),
    );
  }

  // Динамик social proof — event id-ээс тогтвортой утга үүсгэнэ
  String _socialProof() {
    final h = event.id.hashCode.abs();
    if (h % 3 == 0) return '⚡️ High Energy';
    final n = 300 + (h % 1700); // 300..1999
    final label = n >= 1000 ? '${(n / 100).round() / 10}k' : '$n';
    return '🔥 $label hyped';
  }

  Widget _coverPlaceholder() => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: const Center(child: Text('🎉', style: TextStyle(fontSize: 36))));
}

/// Хөвдөг неон badge — social proof харуулна
class _SocialBadge extends StatelessWidget {
  final String text;
  const _SocialBadge({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.accentStart.withValues(alpha: 0.9), width: 1),
      boxShadow: [
        BoxShadow(color: AppColors.accentStart.withValues(alpha: 0.55),
          blurRadius: 12, spreadRadius: 0.5),
        BoxShadow(color: AppColors.accentEnd.withValues(alpha: 0.3),
          blurRadius: 16, spreadRadius: 1),
      ]),
    child: Text(text, style: const TextStyle(
      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800,
      letterSpacing: 0.2)),
  );
}

/// Event detail-ийг RSVP-тэй sheet-ээр нээх (feed rail + venue detail-аас дуудна)
void showEventDetailSheet(BuildContext context, EventItem event) {
  showModalBottomSheet(
    context: context, backgroundColor: AppColors.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _EventDetailSheet(event: event),
  );
}

// ─── Event detail + RSVP (Going / Interested) ───
class _EventDetailSheet extends StatefulWidget {
  final EventItem event;
  const _EventDetailSheet({required this.event});
  @override
  State<_EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<_EventDetailSheet> {
  int _going = 0, _interested = 0;
  String? _mine; // 'going' | 'interested' | null
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await EventRsvpService.load(widget.event.id);
    if (mounted) {
      setState(() {
        _going = r.going; _interested = r.interested; _mine = r.mine;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String status) async {
    final prev = _mine, pg = _going, pi = _interested;
    final next = _mine == status ? null : status; // дахин дарвал болих
    setState(() {
      // хуучин төлвөөс хасах
      if (_mine == 'going') _going--;
      if (_mine == 'interested') _interested--;
      // шинэ төлөв
      if (next == 'going') _going++;
      if (next == 'interested') _interested++;
      _mine = next;
    });
    final err = await EventRsvpService.setRsvp(widget.event.id, next);
    if (err != null && mounted) {
      setState(() { _mine = prev; _going = pg; _interested = pi; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
            color: AppColors.hairline, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(e.title, style: AppTextStyles.h2),
          const SizedBox(height: 8),
          _line(Icons.location_on_outlined, e.venueName ?? '—'),
          _line(Icons.schedule, _EventCard._dateStr(e.startsAt)),
          _line(Icons.confirmation_num_outlined,
            e.price == 0 ? 'Үнэгүй' : '₮${e.price}'),
          if (e.description?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(e.description!, style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary, height: 1.4)),
          ],
          const SizedBox(height: 16),

          // ── RSVP товчнууд ──
          Row(children: [
            Expanded(child: _rsvpBtn(
              label: 'Очно', count: _going, active: _mine == 'going',
              icon: Icons.check_circle, color: AppColors.success,
              onTap: () => _toggle('going'))),
            const SizedBox(width: 10),
            Expanded(child: _rsvpBtn(
              label: 'Сонирхож байна', count: _interested,
              active: _mine == 'interested',
              icon: Icons.star, color: AppColors.accentStart,
              onTap: () => _toggle('interested'))),
          ]),
          const SizedBox(height: 8),
          if (!_loading)
            Text('$_going очно · $_interested сонирхож байна',
              style: AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary)),
        ]),
    );
  }

  Widget _rsvpBtn({
    required String label, required int count, required bool active,
    required IconData icon, required Color color, required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.18) : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? color : AppColors.hairline,
          width: active ? 1.5 : 1),
      ),
      child: Column(children: [
        Icon(icon, color: active ? color : AppColors.textSecondary, size: 20),
        const SizedBox(height: 4),
        Text('$label${count > 0 ? '  ·  $count' : ''}',
          style: AppTextStyles.bodyXs.copyWith(
            color: active ? color : AppColors.textPrimary,
            fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  Widget _line(IconData i, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(i, size: 16, color: AppColors.accentStart),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary))),
    ]));
}
