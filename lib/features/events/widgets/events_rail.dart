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
        height: 184,
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

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppColors.hairline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(event.title, style: AppTextStyles.h2),
            const SizedBox(height: 8),
            _line(Icons.location_on_outlined, event.venueName ?? '—'),
            _line(Icons.schedule, _dateStr(event.startsAt)),
            _line(Icons.confirmation_num_outlined,
              event.price == 0 ? 'Үнэгүй' : '₮${event.price}'),
            if (event.description?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(event.description!, style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.textSecondary, height: 1.4)),
            ],
          ]),
      ),
    );
  }

  Widget _line(IconData i, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(i, size: 16, color: AppColors.accentStart),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary))),
    ]));

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
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cover
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(height: 96, width: double.infinity,
              child: event.coverUrl != null
                ? CachedNetworkImage(imageUrl: event.coverUrl!, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _coverPlaceholder())
                : _coverPlaceholder()),
          ),
          Padding(padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.location_on, size: 11, color: AppColors.textSecondary),
                const SizedBox(width: 3),
                Expanded(child: Text(event.venueName ?? '—',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Text(_dateStr(event.startsAt),
                  style: AppTextStyles.bodyXs.copyWith(color: AppColors.accentStart,
                    fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(event.price == 0 ? 'Үнэгүй' : '₮${event.price}',
                  style: AppTextStyles.bodyXs.copyWith(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
              ]),
            ])),
        ]),
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: const Center(child: Text('🎉', style: TextStyle(fontSize: 36))));
}
