import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../providers/event_provider.dart';

const _kMonths = ['', '1-р сар','2-р сар','3-р сар','4-р сар','5-р сар','6-р сар',
  '7-р сар','8-р сар','9-р сар','10-р сар','11-р сар','12-р сар'];

// Мянгатын таслалтай үнэ (₮12,000)
String _fmtPrice(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '₮$b';
}

// Товч тоо: 1200 → 1.2k
String _fmtCount(int n) =>
    n >= 1000 ? '${(n / 100).round() / 10}k' : '$n';

/// Постерын өргөн — дэлгэц бүтэн (хажуу 20 padding), веб өргөн цонхонд clamp
double _posterWidth(BuildContext context) =>
    (MediaQuery.of(context).size.width - 40).clamp(240.0, 540.0);

class EventsRail extends ConsumerWidget {
  const EventsRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(upcomingEventsProvider);
    // Ачаалж байхад skeleton — feed доош "үсрэхгүй", байрлалаа урьдчилж эзэлнэ
    if (eventsAsync.isLoading && !eventsAsync.hasValue) {
      return const _RailSkeleton();
    }
    final events = eventsAsync.value ?? [];
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Секцийн гарчиг — нэгдсэн sectionLabel хэв маяг
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Text('УДАХГҮЙ БОЛОХ ЭВЕНТҮҮД',
          style: AppTextStyles.sectionLabel),
      ),
      // Бүтэн өргөн постер картууд — хэвтээ swipe
      SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) => _EventCard(event: events[i]),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }
}

// ─── Ачаалж байх үеийн skeleton мөр (постер хэмжээтэй) ───
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();
  @override
  Widget build(BuildContext context) {
    final w = _posterWidth(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: _SkelBox(width: 180, height: 12, radius: 6)),
        SizedBox(
          height: 200,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _SkelBox(width: w, height: 200, radius: 24),
              const SizedBox(width: 14),
              _SkelBox(width: w, height: 200, radius: 24),
            ]),
        ),
        const SizedBox(height: 14),
      ]);
  }
}

class _SkelBox extends StatefulWidget {
  final double? width, height;
  final double radius;
  const _SkelBox({this.width, this.height, this.radius = 12});
  @override
  State<_SkelBox> createState() => _SkelBoxState();
}

class _SkelBoxState extends State<_SkelBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 700),
    lowerBound: 0.45, upperBound: 1.0)..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _c,
    child: Container(
      width: widget.width, height: widget.height,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(widget.radius)),
    ),
  );
}

// ─── Дарлт мэдрэмж — scale + hover курсор (веб) ───
class _Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Tap({required this.child, this.onTap});
  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null
        ? MouseCursor.defer : SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    ),
  );
}

/// Гарын үсэг болсон nightlife постер карт:
/// бүтэн зураг (200 өндөр, радиус 24) + 3 шатлалт scrim,
/// зүүн дээд ШИЛЭН ОГНООНЫ chip (өдөр том / сар micro),
/// баруун дээд үнийн pill, зүүн доод гарчиг+газар, баруун доод RSVP stack.
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

  static String _timeStr(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = event.startsAt.toLocal();
    return _Tap(
      onTap: () => _showDetail(context),
      child: Container(
        width: _posterWidth(context),
        // Постер хүрээ + гүн сүүдэр (карт агаарт хөвөх мэдрэмж)
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.shadowCard,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.hairline, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(fit: StackFit.expand, children: [
            // ── Бүтэн зураг (full-bleed постер) ──
            event.coverUrl != null
              ? CachedNetworkImage(imageUrl: event.coverUrl!, fit: BoxFit.cover,
                  memCacheWidth: 1000, // постер хэмжээний decode
                  fadeInDuration: const Duration(milliseconds: 180),
                  placeholder: (_, __) => _coverPlaceholder(),
                  errorWidget: (_, __, ___) => _coverPlaceholder())
              : _coverPlaceholder(),

            // ── 3 шатлалт scrim — доод текст уншигдахуйц ──
            const DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0x59000000),
                  Color(0xE8000000),
                ],
                stops: [0.35, 0.62, 1.0]))),

            // ── Огнооны chip — зүүн дээд (өдөр том / сар micro, шилэн) ──
            Positioned(top: 12, left: 12, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairline2, width: 1)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(d.day.toString().padLeft(2, '0'),
                  style: const TextStyle(color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w800, height: 1.05)),
                Text('${d.month}-Р САР',
                  style: const TextStyle(color: Colors.white70, fontSize: 8,
                    fontWeight: FontWeight.w700, letterSpacing: 1.1)),
              ]),
            )),

            // ── Үнийн pill — баруун дээд (шилэн) ──
            Positioned(top: 12, right: 12, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.hairline2, width: 1)),
              child: Text(event.price == 0 ? 'Үнэгүй' : _fmtPrice(event.price),
                style: TextStyle(
                  color: event.price == 0 ? AppColors.lime : Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w800)),
            )),

            // ── Доод контент: гарчиг+газар (зүүн) / RSVP stack (баруун) ──
            Positioned(left: 14, right: 14, bottom: 13,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                    Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17,
                        fontWeight: FontWeight.w800, height: 1.15,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black87)])),
                    const SizedBox(height: 5),
                    Row(children: [
                      const Icon(Icons.location_on, size: 12, color: Colors.white70),
                      const SizedBox(width: 3),
                      Flexible(child: Text(event.venueName ?? '—',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSm.copyWith(
                          color: Colors.white70, letterSpacing: 0.3,
                          shadows: const [Shadow(blurRadius: 6, color: Colors.black87)]))),
                      const SizedBox(width: 8),
                      const Icon(Icons.schedule, size: 12, color: Colors.white70),
                      const SizedBox(width: 3),
                      Text(_timeStr(event.startsAt),
                        style: AppTextStyles.labelSm.copyWith(
                          color: Colors.white70, letterSpacing: 0.3,
                          shadows: const [Shadow(blurRadius: 6, color: Colors.black87)])),
                    ]),
                  ])),
                // Бодит RSVP тоо — цөөхөн үед огт харуулахгүй (хуурамч hype байхгүй)
                if (event.attendeeCount >= 5) ...[
                  const SizedBox(width: 10),
                  _AttendeeStack(count: event.attendeeCount),
                ],
              ])),
          ]),
        ),
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: const Center(child: Text('🎉', style: TextStyle(fontSize: 36))));
}

/// Оролцогчдын stack — 3 давхарласан 24px дүрс (-8 offset) + "+N" шилэн pill.
/// Provider-т аватар URL байхгүй тул дүрсүүд нь ерөнхий silhouette,
/// тоо нь бодит attendee_count (>=5 үед л харагдана).
class _AttendeeStack extends StatelessWidget {
  final int count;
  const _AttendeeStack({required this.count});

  static const _tints = [
    AppColors.accentPurple, AppColors.magenta, AppColors.steel];

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 24 + 2 * 16, height: 24, child: Stack(children: [
        for (var i = 0; i < 3; i++)
          Positioned(left: i * 16.0, child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _tints[i].withValues(alpha: 0.85),
              border: Border.all(color: const Color(0xE6050505), width: 2)),
            child: const Icon(Icons.person, size: 12, color: Colors.white70),
          )),
      ])),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2, width: 1)),
        child: Text('+${_fmtCount(count)}',
          style: const TextStyle(color: Colors.white, fontSize: 11,
            fontWeight: FontWeight.w800)),
      ),
    ]);
}

/// Event detail-ийг RSVP-тэй sheet-ээр нээх (feed rail + venue detail-аас дуудна)
void showEventDetailSheet(BuildContext context, EventItem event) {
  showModalBottomSheet(
    context: context, backgroundColor: AppColors.bgElevated,
    // Урт тайлбартай эвент overflow хийхгүй — өндөр нь дотроо scroll-тай
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _EventDetailSheet(event: event),
  );
}

// ─── Event detail + RSVP (Очно / Сонирхож байна) ───
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
    // Эхний төлөв ачаалагдаагүй байхад дарвал буруу delta + race үүснэ
    if (_loading) return;
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
      // Буцаасан шалтгаанаа хэлж өгнө (чимээгүй flicker байхгүй)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        err == 'Нэвтэрнэ үү' ? 'Нэвтэрнэ үү'
          : 'Илгээж чадсангүй. Дахин оролдоно уу')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppColors.hairline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            // ── Scroll болох хэсэг (урт тайлбар) — RSVP мөр доор нь тогтмол ──
            Flexible(child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.title, style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  _line(Icons.location_on_outlined, e.venueName ?? '—'),
                  _line(Icons.schedule, _EventCard._dateStr(e.startsAt)),
                  _line(Icons.confirmation_num_outlined,
                    e.price == 0 ? 'Үнэгүй' : _fmtPrice(e.price)),
                  if (e.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text(e.description!, style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textSecondary, height: 1.4)),
                  ],
                ]),
            )),
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
      ),
    );
  }

  Widget _rsvpBtn({
    required String label, required int count, required bool active,
    required IconData icon, required Color color, required VoidCallback onTap,
  }) => _Tap(
    // Ачаалж дуустал идэвхгүй — stale optimistic race-ээс сэргийлнэ
    onTap: _loading ? null : onTap,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: _loading ? 0.5 : 1,
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
