import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../../events/providers/event_provider.dart' show EventItem;
import '../../events/widgets/events_rail.dart' show showEventDetailSheet;
import '../providers/venue_provider.dart';

const _kMonths = ['', '1-р сар','2-р сар','3-р сар','4-р сар','5-р сар','6-р сар',
  '7-р сар','8-р сар','9-р сар','10-р сар','11-р сар','12-р сар'];

String _venueEmoji(String? t) => switch (t) {
  'pub' => '🍺', 'lounge' => '🍸', 'nightclub' => '🎧',
  'rooftop' => '🌃', 'karaoke' => '🎤', 'jazz' => '🎷', 'bar' => '🍻', _ => '🎵',
};

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

// Amber одод — дүүргэсэн од зөөлөн glow-той (info card + review картад хамт)
Widget _starsRow(int n, {double size = 14}) => Row(mainAxisSize: MainAxisSize.min,
  children: [for (int i = 1; i <= 5; i++)
    Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded,
      color: AppColors.amber, size: size,
      shadows: i <= n
        ? [Shadow(color: AppColors.amber.withValues(alpha: 0.5), blurRadius: 8)]
        : null)]);

class VenueDetailScreen extends ConsumerStatefulWidget {
  final String venueId;
  const VenueDetailScreen({super.key, required this.venueId});
  @override
  ConsumerState<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends ConsumerState<VenueDetailScreen> {
  Map<String, dynamic>? _venue;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _reviewsPreview = []; // сүүлийн 3 сэтгэгдэл
  bool _loading = true;
  bool _error = false;    // сүлжээ/RLS алдаа
  bool _notFound = false; // venue устсан / буруу id
  bool _checkinBusy = false;

  String? get _ownerId => _venue?['owner_id'] as String?;
  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    // Идэвхтэй check-in төлвөө сэргээнэ (нэг удаа, кэштэй)
    Future.microtask(() => ref.read(checkInProvider.notifier).loadCurrent());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; _notFound = false; });
    try {
      final v = await SupabaseService.client.from('venues')
          .select('id, name, district, venue_type, description, cover_url, lat, lng, '
              'rating, review_count, owner_id, phone, open_time, close_time')
          .eq('id', widget.venueId).maybeSingle();
      final now = DateTime.now().subtract(const Duration(hours: 3)).toIso8601String();
      final ev = await SupabaseService.client.from('events')
          .select('id, title, description, cover_url, starts_at, price')
          .eq('venue_id', widget.venueId)
          .gte('starts_at', now)
          .order('starts_at').limit(10);
      // Сэтгэгдлийн урьдчилсан харагдац — алдвал section-оо л нуух тул тусдаа try
      List<Map<String, dynamic>> preview = [];
      try {
        final rv = await SupabaseService.client.from('venue_reviews')
            .select('user_id, rating, comment, created_at')
            .eq('venue_id', widget.venueId)
            .order('created_at', ascending: false).limit(3);
        final rows = (rv as List).cast<Map<String, dynamic>>();
        final ids = rows.map((r) => r['user_id'] as String).toSet().toList();
        Map<String, Map<String, dynamic>> pmap = {};
        if (ids.isNotEmpty) {
          final profs = await SupabaseService.client.from('profiles')
              .select('id, username, avatar_url').inFilter('id', ids);
          pmap = { for (final p in (profs as List).cast<Map<String, dynamic>>())
            p['id'] as String: p };
        }
        preview = rows.map((r) {
          final p = pmap[r['user_id']];
          return {...r, 'username': p?['username'] ?? 'User',
            'avatar_url': p?['avatar_url']};
        }).toList();
      } catch (_) { preview = []; }
      if (mounted) {
        setState(() {
          _venue = v;
          _notFound = v == null; // амжилттай хариу, гэхдээ ийм venue алга
          _events = (ev as List).cast<Map<String, dynamic>>();
          _reviewsPreview = preview;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  void _goBack() => context.canPop()
      ? context.pop() : context.go(AppRoutes.explore);

  Future<void> _openDirections() async {
    if (_venue == null) return; // өгөгдөлгүй үед хоосон maps tab нээхгүй
    final lat = (_venue?['lat'] as num?)?.toDouble();
    final lng = (_venue?['lng'] as num?)?.toDouble();
    final name = _venue?['name'] as String? ?? '';
    // origin-г орхивол Google Maps хэрэглэгчийн одоогийн байршлыг ашиглана
    final dest = (lat != null && lng != null) ? '$lat,$lng' : Uri.encodeComponent(name);
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$dest';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _openReviews() {
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ReviewsSheet(venueId: widget.venueId),
    ).then((_) => _load()); // хаагдахад дундаж шинэчлэх
  }

  // ── Check-in / check-out toggle ──
  Future<void> _toggleCheckIn() async {
    if (_checkinBusy) return;
    final notifier = ref.read(checkInProvider.notifier);
    final checkedIn = ref.read(checkInProvider) == widget.venueId;
    setState(() => _checkinBusy = true);
    final err = checkedIn
        ? await notifier.checkOut(widget.venueId)
        : await notifier.checkIn(widget.venueId);
    if (!mounted) return;
    setState(() => _checkinBusy = false);
    final messenger = ScaffoldMessenger.of(context);
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text(err)));
    } else {
      // checkin_count-ыг дахин татна (trigger шинэчилсэн бол шууд тусна)
      ref.invalidate(venuesProvider);
      messenger.showSnackBar(SnackBar(content: Text(checkedIn
          ? 'Та энэ газраас гарлаа'
          : 'Ирснээ мэдэгдлээ! 🎉 (4 цаг хүчинтэй)')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _skeleton();
    if (_error || _notFound) return _problemView();

    final name = _venue?['name'] as String? ?? 'Газар';
    final type = _venue?['venue_type'] as String?;
    final district = _venue?['district'] as String?;
    final desc = _venue?['description'] as String?;
    final cover = _venue?['cover_url'] as String?;
    final avg = (_venue?['rating'] as num?)?.toDouble() ?? 0;
    final count = _venue?['review_count'] as int? ?? 0;
    final checkedIn = ref.watch(checkInProvider) == widget.venueId;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: RefreshIndicator(
        color: AppColors.accentStart,
        backgroundColor: AppColors.bgElevated,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: Stack(children: [
              // ── Hero зураг 280 — ард нь бүтэн өргөнөөр ──
              Positioned(top: 0, left: 0, right: 0,
                child: SizedBox(height: 280,
                  child: Stack(fit: StackFit.expand, children: [
                    cover != null
                      ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _coverFallback(type))
                      : _coverFallback(type),
                    // Доод scrim — хөвөгч карт руу зөөлөн уусна
                    const DecoratedBox(decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        stops: [0.4, 1.0],
                        colors: [Colors.transparent, Color(0xE6050505)]))),
                  ]))),
              // ── Контент — 240-с эхэлж info card hero дээр 40px давхарлана ──
              Padding(
                padding: const EdgeInsets.only(top: 240),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _infoCard(name, type, district, avg, count, checkedIn)),
                    ..._sections(desc),
                    const SizedBox(height: 40),
                  ]),
              ),
              // ── Дээд шилэн товчнууд — буцах + чиглэл ──
              Positioned(top: 0, left: 0, right: 0,
                child: SafeArea(bottom: false, child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(children: [
                    _CircleBtn(icon: Icons.arrow_back_ios_new, onTap: _goBack),
                    const Spacer(),
                    _CircleBtn(icon: Icons.directions_rounded,
                      onTap: _openDirections),
                  ])))),
            ])),
          ]),
      ),
    );
  }

  // ── Хөвөгч шилэн info card — hero-гийн доод ирмэг дээр давхарлана ──
  Widget _infoCard(String name, String? type, String? district,
      double avg, int count, bool checkedIn) {
    final micro = [
      if (type != null) '${_venueEmoji(type)} $type',
      if (district != null) district,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline2),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: AppTextStyles.h2),
        if (micro.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(micro, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textTertiary, letterSpacing: 0.3)),
        ],
        const SizedBox(height: 10),
        // ⭐ Дундаж үнэлгээ — одод + тоо
        Row(children: [
          _starsRow(avg.round(), size: 18),
          const SizedBox(width: 8),
          Text(avg.toStringAsFixed(1), style: AppTextStyles.h3),
          const SizedBox(width: 6),
          Text('($count үнэлгээ)', style: AppTextStyles.bodySm.copyWith(
            color: AppColors.textSecondary)),
        ]),
        // Цагийн хуваарь + утас
        if (_venue?['open_time'] != null && (_venue!['open_time'] as String).isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.schedule, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('${_venue!['open_time']} - ${_venue?['close_time'] ?? ''}',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary)),
          ]),
        ],
        if (_venue?['phone'] != null && (_venue!['phone'] as String).isNotEmpty) ...[
          const SizedBox(height: 8),
          _Tap(
            onTap: () => launchUrl(Uri.parse('tel:${_venue!['phone']}')),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.phone, size: 15, color: AppColors.accentStart),
              const SizedBox(width: 6),
              Text(_venue!['phone'] as String, style: AppTextStyles.bodySm.copyWith(
                color: AppColors.accentStart, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        // ── Үйлдлийн мөр: Check-in gradient pill + Үнэлгээ glass pill ──
        Row(children: [
          Expanded(child: _checkInPill(checkedIn)),
          const SizedBox(width: 10),
          Expanded(child: _glassPill(Icons.star_outline_rounded, 'Үнэлгээ',
            _openReviews)),
        ]),
        if (_ownerId != null && _ownerId != _myId) ...[
          const SizedBox(height: 10),
          _glassPill(Icons.chat_bubble_outline_rounded, 'Эзэнтэй чатлах',
            () => context.push('/dm/$_ownerId')),
        ],
      ]),
    );
  }

  // ── Доорх section-ууд: танилцуулга, сэтгэгдэл, эвент ──
  List<Widget> _sections(String? desc) => [
    if (desc != null && desc.isNotEmpty) ...[
      _sectionHeader('Танилцуулга'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(desc, style: AppTextStyles.bodyMd.copyWith(
          color: AppColors.textPrimary, height: 1.5))),
    ],
    // АМЬДРАЛ — сүүлийн сэтгэгдлүүд (карт хэлбэрээр)
    _sectionHeader('Амьдрал · Сэтгэгдэл', onSeeAll: _openReviews),
    if (_reviewsPreview.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _Tap(
          onTap: _openReviews,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.hairline)),
            child: Row(children: [
              const Icon(Icons.rate_review_outlined,
                color: AppColors.textTertiary, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text('Сэтгэгдэл байхгүй — анхных нь бай!',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.textSecondary))),
              const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.neonCyan, size: 14),
            ]),
          ),
        ))
    else
      for (final r in _reviewsPreview)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: _ReviewCard(review: r)),
    // ЭВЕНТҮҮД
    if (_events.isNotEmpty) ...[
      _sectionHeader('Эвентүүд'),
      for (final e in _events)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _eventTile(e)),
    ],
  ];

  Widget _sectionHeader(String title, {VoidCallback? onSeeAll}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
    child: Row(children: [
      Text(title.toUpperCase(), style: AppTextStyles.sectionLabel),
      const Spacer(),
      if (onSeeAll != null)
        _Tap(
          behavior: HitTestBehavior.opaque,
          onTap: onSeeAll,
          child: Text('Бүгд →', style: AppTextStyles.labelSm.copyWith(
            color: AppColors.neonCyan, letterSpacing: 0))),
    ]),
  );

  // ── Ачаалж байх үеийн skeleton — шинэ layout-ын хэлбэрээр ──
  Widget _skeleton() => const Scaffold(
    backgroundColor: AppColors.bgBase,
    body: SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SkelBox(height: 240, radius: 0), // hero
        Padding(
          padding: EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SkelBox(height: 230, radius: 24), // хөвөгч info card
            SizedBox(height: 28),
            _SkelBox(width: 140, height: 12, radius: 6),
            SizedBox(height: 12),
            _SkelBox(height: 84, radius: 24),
            SizedBox(height: 10),
            _SkelBox(height: 84, radius: 24),
          ]),
        ),
      ]),
    ),
  );

  // ── Алдаа / олдсонгүй байдал — чимээгүй хоосон дэлгэцийн оронд ──
  Widget _problemView() => Scaffold(
    backgroundColor: AppColors.bgBase,
    body: SafeArea(child: Stack(children: [
      Positioned(top: 8, left: 12, child: _CircleBtn(
        icon: Icons.arrow_back_ios_new, onTap: _goBack)),
      Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_notFound ? Icons.location_off_outlined : Icons.wifi_off_outlined,
            color: AppColors.textTertiary, size: 48),
          const SizedBox(height: 16),
          Text(_notFound ? 'Газар олдсонгүй' : 'Ачаалж чадсангүй',
            style: AppTextStyles.h2),
          const SizedBox(height: 8),
          Text(_notFound
              ? 'Энэ газар устсан эсвэл холбоос хуучирсан байна'
              : 'Сүлжээгээ шалгаад дахин оролдоно уу',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          if (_notFound)
            ElevatedButton(onPressed: _goBack, child: const Text('Буцах'))
          else
            ElevatedButton(onPressed: _load, child: const Text('Дахин оролдох')),
        ]),
      )),
    ])),
  );

  Widget _coverFallback(String? type) => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: Center(child: Text(_venueEmoji(type), style: const TextStyle(fontSize: 72))));

  // Check-in pill — идэвхгүй үед accentGradient, идэвхтэй үед lime glass
  Widget _checkInPill(bool checkedIn) => _Tap(
    onTap: _checkinBusy ? null : _toggleCheckIn,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      height: 50,
      decoration: BoxDecoration(
        gradient: checkedIn ? null : AppColors.accentGradient,
        color: checkedIn ? AppColors.lime.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(999),
        border: checkedIn
            ? Border.all(color: AppColors.lime.withValues(alpha: 0.7))
            : null,
        boxShadow: checkedIn
            ? AppColors.glowShadow(AppColors.lime, alpha: 0.25)
            : AppColors.glowShadow(AppColors.accentStart),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (_checkinBusy)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(
            color: checkedIn ? AppColors.lime : Colors.white, strokeWidth: 2))
        else
          Icon(checkedIn ? Icons.where_to_vote : Icons.where_to_vote_outlined,
            size: 20, color: checkedIn ? AppColors.lime : Colors.white),
        const SizedBox(width: 8),
        Flexible(child: Text(checkedIn ? 'Та энд байна · Гарах' : 'Ирснээ мэдэгдэх',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: AppTextStyles.btn.copyWith(
            color: checkedIn ? AppColors.lime : Colors.white,
            fontSize: 14))),
      ]),
    ),
  );

  // Glass pill товч — icon + label
  Widget _glassPill(IconData icon, String label, VoidCallback onTap) =>
    _Tap(onTap: onTap, child: Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.bgSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline2)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: AppColors.textPrimary),
        const SizedBox(width: 8),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: AppTextStyles.btn.copyWith(
            color: AppColors.textPrimary, fontSize: 14))),
      ])));

  Widget _eventTile(Map<String, dynamic> e) {
    final starts = DateTime.tryParse(e['starts_at'] as String? ?? '');
    final dateStr = starts == null ? '' :
      '${starts.toLocal().day} ${_kMonths[starts.toLocal().month]}, '
      '${starts.toLocal().hour.toString().padLeft(2,'0')}:${starts.toLocal().minute.toString().padLeft(2,'0')}';
    final price = e['price'] as int? ?? 0;
    return _Tap(
      onTap: () => showEventDetailSheet(context, EventItem(
        id: e['id'] as String,
        title: e['title'] as String? ?? 'Event',
        description: e['description'] as String?, // sheet дээр тайлбар харагдана
        coverUrl: e['cover_url'] as String?,
        startsAt: starts ?? DateTime.now(),
        price: price,
        venueName: _venue?['name'] as String?,
      )),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      // Шилэн эвент карт — glass давхарга + hairline
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline)),
      child: Row(children: [
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
          child: SizedBox(width: 74, height: 74,
            child: e['cover_url'] != null
              ? CachedNetworkImage(imageUrl: e['cover_url'] as String, fit: BoxFit.cover,
                  errorWidget: (_,__,___) => _evPlaceholder())
              : _evPlaceholder())),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(e['title'] as String? ?? 'Event', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text(dateStr, style: AppTextStyles.bodyXs.copyWith(color: AppColors.accentStart)),
          ])),
        Padding(padding: const EdgeInsets.only(right: 14),
          child: Text(price == 0 ? 'Үнэгүй' : _fmtPrice(price),
            style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
      ]),
    ),
    );
  }

  Widget _evPlaceholder() => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: const Center(child: Text('🎉', style: TextStyle(fontSize: 26))));
}

// ─── Шилэн дугуй товч — hero дээрх back/directions ───
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => _Tap(
    onTap: onTap,
    child: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: AppColors.hairline2)),
      child: Icon(icon, size: 18, color: Colors.white)),
  );
}

// ─── Review preview карт — АМЬДРАЛ section ───
class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});
  @override
  Widget build(BuildContext context) {
    final username = (review['username'] as String? ?? 'User').replaceAll('@', '');
    final comment = review['comment'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppAvatar(imageUrl: review['avatar_url'] as String?,
            initial: username.isNotEmpty ? username[0].toUpperCase() : '?',
            size: 32),
          const SizedBox(width: 8),
          Expanded(child: Text('@$username',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary))),
          _starsRow(review['rating'] as int? ?? 0),
        ]),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(comment, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.textPrimary, height: 1.4)),
        ],
      ]),
    );
  }
}

// ─── Дарлт мэдрэмж — scale + hover курсор (веб) ───
class _Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final HitTestBehavior behavior;
  const _Tap({required this.child, this.onTap,
    this.behavior = HitTestBehavior.deferToChild});
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
      behavior: widget.behavior,
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

// ─── Зөөлөн цохилдог skeleton хайрцаг ───
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

// ─── Үнэлгээ / сэтгэгдэл sheet ───
class _ReviewsSheet extends StatefulWidget {
  final String venueId;
  const _ReviewsSheet({required this.venueId});
  @override
  State<_ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<_ReviewsSheet> {
  List<Map<String, dynamic>> _reviews = [];
  int _myRating = 0;
  final _commentCtrl = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await SupabaseService.client.from('venue_reviews')
          .select('user_id, rating, comment, created_at')
          .eq('venue_id', widget.venueId)
          .order('created_at', ascending: false).limit(100);
      final rows = (data as List).cast<Map<String, dynamic>>();
      final ids = rows.map((r) => r['user_id'] as String).toSet().toList();
      Map<String, Map<String, dynamic>> pmap = {};
      if (ids.isNotEmpty) {
        final profs = await SupabaseService.client.from('profiles')
            .select('id, username, avatar_url').inFilter('id', ids);
        pmap = { for (final p in (profs as List).cast<Map<String, dynamic>>())
          p['id'] as String: p };
      }
      _reviews = rows.map((r) {
        final p = pmap[r['user_id']];
        return {...r, 'username': p?['username'] ?? 'User', 'avatar_url': p?['avatar_url']};
      }).toList();
      final mine = rows.where((r) => r['user_id'] == _myId).toList();
      if (mine.isNotEmpty) {
        _myRating = mine.first['rating'] as int? ?? 0;
        _commentCtrl.text = mine.first['comment'] as String? ?? '';
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _submit() async {
    if (_myRating == 0 || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_myId.isEmpty) {
      // Нэвтрээгүй — чимээгүй унтрахын оронд хэлж өгнө
      messenger.showSnackBar(const SnackBar(content: Text('Нэвтэрнэ үү')));
      return;
    }
    setState(() => _busy = true);
    try {
      await SupabaseService.client.from('venue_reviews').upsert({
        'venue_id': widget.venueId, 'user_id': _myId,
        'rating': _myRating, 'comment': _commentCtrl.text.trim(),
      }, onConflict: 'venue_id, user_id');
      await _load();
      if (mounted) {
        FocusScope.of(context).unfocus();
        messenger.showSnackBar(
          const SnackBar(content: Text('Үнэлгээ илгээгдлээ ⭐')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Илгээж чадсангүй. Дахин оролдоно уу')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 12),
        child: _loading
          ? ListView(controller: scrollCtrl, children: const [
              SizedBox(height: 14),
              _SkelBox(height: 26, width: 200, radius: 8),
              SizedBox(height: 14),
              _SkelBox(height: 180, radius: 14),
              SizedBox(height: 14),
              _SkelBox(height: 70, radius: 12),
              SizedBox(height: 10),
              _SkelBox(height: 70, radius: 12),
            ])
          : ListView(controller: scrollCtrl, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                color: AppColors.hairline, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Үнэлгээ ба сэтгэгдэл', style: AppTextStyles.h2),
              const SizedBox(height: 14),
              // Бичих — шилэн карт хэмнэл
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Таны үнэлгээ', style: AppTextStyles.labelLg),
                  const SizedBox(height: 8),
                  Row(children: [for (int i = 1; i <= 5; i++)
                    _Tap(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _myRating = i),
                      child: Padding(padding: const EdgeInsets.only(right: 4),
                        child: Icon(i <= _myRating ? Icons.star_rounded : Icons.star_border_rounded,
                          color: AppColors.amber, size: 34,
                          shadows: i <= _myRating
                            ? [Shadow(color: AppColors.amber.withValues(alpha: 0.5),
                                blurRadius: 10)]
                            : null)))]),
                  const SizedBox(height: 10),
                  TextField(controller: _commentCtrl, maxLines: 2,
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(hintText: 'Сэтгэгдэл...',
                      hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
                      filled: true, fillColor: AppColors.bgElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none))),
                  const SizedBox(height: 10),
                  _Tap(
                    onTap: (_myRating == 0 || _busy) ? null : _submit,
                    child: Container(height: 44, width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: _myRating == 0 ? null : AppColors.accentGradient,
                        color: _myRating == 0 ? AppColors.bgElevated : null,
                        borderRadius: BorderRadius.circular(999)),
                      alignment: Alignment.center,
                      child: _busy
                        ? const SizedBox(width: 20, height: 20, child:
                            CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Илгээх', style: AppTextStyles.btn.copyWith(
                            color: _myRating == 0 ? AppColors.textTertiary : Colors.white)))),
                ]),
              ),
              const SizedBox(height: 18),
              if (_reviews.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('Сэтгэгдэл байхгүй — анхных нь бай!',
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)))),
              for (final r in _reviews) Padding(
                padding: const EdgeInsets.only(bottom: 10),
                // Шилэн review карт — жигд glass хэмнэл
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.hairline)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      AppAvatar(imageUrl: r['avatar_url'] as String?,
                        initial: (r['username'] as String).replaceAll('@','').isNotEmpty
                          ? (r['username'] as String).replaceAll('@','')[0].toUpperCase() : '?',
                        size: 30),
                      const SizedBox(width: 8),
                      Expanded(child: Text('@${(r['username'] as String).replaceAll('@','')}',
                        style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary))),
                      _starsRow(r['rating'] as int? ?? 0),
                    ]),
                    if ((r['comment'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r['comment'] as String, style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textPrimary, height: 1.4)),
                    ],
                  ]),
                )),
              const SizedBox(height: 20),
            ]),
      ),
    );
  }
}
