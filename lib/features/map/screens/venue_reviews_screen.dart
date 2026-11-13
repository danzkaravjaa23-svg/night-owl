import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/services/supabase_service.dart';
import '../../events/providers/event_provider.dart' show EventItem;
import '../../events/widgets/events_rail.dart' show showEventDetailSheet;
import '../providers/venue_provider.dart';
import '../../../models/venue.dart';

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

// Үнэлгээний одод (AppColors.rating) — дүүргэсэн од зөөлөн glow-той
// (info card + review картад хамт)
Widget _starsRow(int n, {double size = 14}) => Row(mainAxisSize: MainAxisSize.min,
  children: [for (int i = 1; i <= 5; i++)
    Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded,
      color: AppColors.rating, size: size,
      shadows: i <= n
        ? [Shadow(color: AppColors.rating.withValues(alpha: 0.5), blurRadius: 8)]
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

  void _goBack() =>
      AppHeader.goBack(context, fallbackLocation: AppRoutes.explore);

  Future<void> _openDirections() async {
    if (_venue == null) return; // өгөгдөлгүй үед хоосон maps tab нээхгүй
    final venue = Venue.fromJson(_venue!);
    final name = _venue?['name'] as String? ?? '';
    // origin-г орхивол Google Maps хэрэглэгчийн одоогийн байршлыг ашиглана
    final dest = venue.hasLocation ? '${venue.lat},${venue.lng}' : '$name, Улаанбаатар';
    try {
      final opened = await launchUrl(Uri.https('www.google.com', '/maps/dir/',
        {'api': '1', 'destination': dest}), mode: LaunchMode.externalApplication);
      if (!opened && mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чиглэл нээж чадсангүй'))); }
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чиглэл нээж чадсангүй'))); }
    }
  }

  void _openReviews() {
    // Өнгө, радиус, бариулыг bottomSheetTheme (showDragHandle) өгнө.
    // Sheet амжилттай илгээвэл `true`-гээр хаагдана — мэдэгдлийг энд, хуудсан
    // дээр харуулна (нээлттэй sheet-ийн доор SnackBar нуугддаг).
    showAppSheet<bool>(
      context: context,
      builder: (_) => _ReviewsSheet(venueId: widget.venueId),
    ).then((submitted) {
      if (!mounted) return;
      if (submitted == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Үнэлгээ илгээгдлээ')));
      }
      _load(); // хаагдахад дундаж шинэчлэх
    });
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
      ref.read(refreshVenueCatalogProvider)();
      messenger.showSnackBar(SnackBar(content: Text(checkedIn
          ? 'Та энэ газраас гарлаа'
          : 'Ирснээ мэдэгдлээ! (4 цаг хүчинтэй)')));
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
        color: AppColors.accentText,
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
                      ? AuthorizedImage(imageUrl: cover, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _coverFallback(type))
                      : _coverFallback(type),
                    // Доод scrim — хөвөгч карт руу зөөлөн уусна.
                    // Хуудасны дэвсгэр рүү уусдаг тул цайвар горимд cream өнгө рүү.
                    DecoratedBox(decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        stops: const [0.4, 1.0],
                        colors: AppColors.isDarkMode
                          ? const [Colors.transparent, Color(0xE6050505)]
                          : [AppColors.bgBaseLight.withValues(alpha: 0),
                             AppColors.bgBaseLight.withValues(alpha: 0.9)]))),
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
              // ── Дээд толгой (DS-06) — зураг дээрх буцах + чиглэл ──
              Positioned(top: 0, left: 0, right: 0,
                child: AppHeader.media(
                  fallbackLocation: AppRoutes.explore,
                  actions: [
                    GlassIconButton(icon: Icons.directions_rounded,
                      onMedia: true, tooltip: 'Чиглэл',
                      onTap: _openDirections),
                  ])),
            ])),
          ]),
      ),
    );
  }

  // ── Хөвөгч шилэн info card — hero-гийн доод ирмэг дээр давхарлана ──
  Widget _infoCard(String name, String? type, String? district,
      double avg, int count, bool checkedIn) {
    final micro = [
      if (type != null) type,
      if (district != null) district,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.72),
        borderRadius: AppRadii.lgR,
        border: Border.all(color: AppColors.hairline2),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: AppTextStyles.h2),
        if (micro.isNotEmpty) ...[
          const SizedBox(height: 4),
          // Газрын төрөл — emoji биш, AppIcons.venueType (DS-09)
          Row(children: [
            if (type != null) ...[
              Icon(AppIcons.venueType(type), size: 14,
                color: AppColors.textTertiary),
              const SizedBox(width: 4),
            ],
            Expanded(child: Text(micro, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSm.copyWith(
                color: AppColors.textTertiary, letterSpacing: 0.3))),
          ]),
        ],
        const SizedBox(height: 10),
        // Дундаж үнэлгээ — одод + тоо
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
            Icon(Icons.schedule, size: 15, color: AppColors.textSecondary),
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
              Icon(Icons.phone, size: 15, color: AppColors.accentText),
              const SizedBox(width: 6),
              Text(_venue!['phone'] as String, style: AppTextStyles.bodySm.copyWith(
                color: AppColors.accentText, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        // ── Үйлдлүүд (DS-03): Check-in товч, доор нь Үнэлгээ (secondary) ──
        // Бүтэн өргөнтэй: хагас өргөнд шошгууд тасардаг байсан.
        _checkInButton(checkedIn),
        const SizedBox(height: 10),
        OutlineButton(label: 'Үнэлгээ',
          icon: const Icon(Icons.star_outline_rounded, size: 18),
          onPressed: _openReviews),
        if (_ownerId != null && _ownerId != _myId) ...[
          const SizedBox(height: 10),
          OutlineButton(label: 'Эзэнтэй чатлах',
            icon: const Icon(AppIcons.message, size: 18),
            onPressed: () => context.push('/dm/$_ownerId')),
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
              borderRadius: AppRadii.lgR,
              border: Border.all(color: AppColors.hairline)),
            child: Row(children: [
              Icon(Icons.rate_review_outlined,
                color: AppColors.textTertiary, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text('Сэтгэгдэл байхгүй — анхных нь бай!',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.textSecondary))),
              Icon(AppIcons.forward, color: AppColors.neonCyan, size: 18),
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

  // Мөрийн өндөр 44 — "Бүгд →" холбоос хүрэхэд хангалттай талбайтай болно
  Widget _sectionHeader(String title, {VoidCallback? onSeeAll}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: SizedBox(
      height: 44,
      child: Row(children: [
        Text(title.toUpperCase(), style: AppTextStyles.sectionLabel),
        const Spacer(),
        if (onSeeAll != null)
          _Tap(
            behavior: HitTestBehavior.opaque,
            onTap: onSeeAll,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              padding: const EdgeInsets.only(left: 16),
              child: Text('Бүгд →', style: AppTextStyles.labelSm.copyWith(
                color: AppColors.neonCyan, letterSpacing: 0)))),
      ]),
    ),
  );

  // ── Ачаалж байх үеийн skeleton — шинэ layout-ын хэлбэрээр ──
  Widget _skeleton() => Scaffold(
    backgroundColor: AppColors.bgBase,
    body: const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SkelBox(height: 240, radius: 0), // hero
        Padding(
          padding: EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SkelBox(height: 230, radius: AppRadii.lg), // хөвөгч info card
            SizedBox(height: 28),
            _SkelBox(width: 140, height: 12, radius: 6),
            SizedBox(height: 12),
            _SkelBox(height: 84, radius: AppRadii.lg),
            SizedBox(height: 10),
            _SkelBox(height: 84, radius: AppRadii.lg),
          ]),
        ),
      ]),
    ),
  );

  // ── Алдаа / олдсонгүй байдал — чимээгүй хоосон дэлгэцийн оронд ──
  Widget _problemView() => Scaffold(
    backgroundColor: AppColors.bgBase,
    // Зөвхөн буцах товчтой толгой (DS-06)
    appBar: const AppHeader.title(title: '', fallbackLocation: AppRoutes.explore),
    body: SafeArea(child: Center(child: Padding(
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
        // Хуудасны primary (DS-03): бусад алдааны төлөвтэй ижил md pill.
        if (_notFound)
          GradientButton(label: 'Буцах', size: GradientButtonSize.md,
            fullWidth: false, onPressed: _goBack)
        else
          GradientButton(label: 'Дахин оролдох', size: GradientButtonSize.md,
            fullWidth: false, onPressed: _load),
      ]),
    ))),
  );

  // Зураггүй газрын нүүр — emoji биш, газрын төрлийн icon (DS-09)
  Widget _coverFallback(String? type) => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: Center(child: Icon(AppIcons.venueType(type), size: 72,
      color: Colors.white.withValues(alpha: 0.9))));

  // Check-in (DS-03): ирээгүй үед primary GradientButton, ирсэн үед secondary
  // OutlineButton — lime icon нь "та энд байна" төлвийг хадгална.
  // Хоёулаа бүтэн өргөнтэй 52px pill; "Үнэлгээ" товч доор нь тусдаа мөрөнд
  // байрлана, учир нь хагас өргөнд "Та энд байна · Гарах" шошго тасардаг.
  Widget _checkInButton(bool checkedIn) => checkedIn
      ? OutlineButton(label: 'Та энд байна · Гарах',
          icon: _checkinBusy
              ? const SizedBox.square(dimension: 18,
                  child: OwlLoading(size: 18, compact: true))
              : Icon(Icons.where_to_vote, size: 20, color: AppColors.lime),
          onPressed: _checkinBusy ? null : _toggleCheckIn)
      : GradientButton(label: 'Ирснээ мэдэгдэх',
          icon: const Icon(Icons.where_to_vote_outlined, size: 20),
          busy: _checkinBusy,
          onPressed: _toggleCheckIn);

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
        borderRadius: AppRadii.lgR,
        border: Border.all(color: AppColors.hairline)),
      child: Row(children: [
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(AppRadii.lg)),
          child: SizedBox(width: 74, height: 74,
            child: e['cover_url'] != null
              ? AuthorizedImage(imageUrl: e['cover_url'] as String, fit: BoxFit.cover,
                  errorWidget: (_,__,___) => _evPlaceholder())
              : _evPlaceholder())),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(e['title'] as String? ?? 'Event', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text(dateStr, style: AppTextStyles.bodyXs.copyWith(color: AppColors.accentText)),
          ])),
        Padding(padding: const EdgeInsets.only(right: 14),
          child: Text(price == 0 ? 'Үнэгүй' : _fmtPrice(price),
            style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
      ]),
    ),
    );
  }

  // Эвентийн зураггүй үеийн орлуулагч — emoji биш, Material icon
  Widget _evPlaceholder() => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: const Center(child: Icon(Icons.celebration_rounded,
      color: Colors.white, size: 26)));
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
        borderRadius: AppRadii.lgR,
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
  // Илгээх үеийн алдаа. Sheet нээлттэй үед SnackBar sheet-ийн ДООР
  // зурагддаг тул товчны доор, sheet дотор харуулна; дахин оролдоход арилна.
  String? _error;
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
    if (_myId.isEmpty) {
      // Нэвтрээгүй — чимээгүй унтрахын оронд хэлж өгнө
      setState(() => _error = 'Нэвтэрнэ үү');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseService.client.from('venue_reviews').upsert({
        'venue_id': widget.venueId, 'user_id': _myId,
        'rating': _myRating, 'comment': _commentCtrl.text.trim(),
      }, onConflict: 'venue_id, user_id');
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      // Амжилт: sheet-ээ ӨӨРИЙН context-оор хаана. Хуудас нь мэдэгдлийг
      // харуулж, дундаж ба сэтгэгдлүүдийг дахин ачаална (_openReviews).
      // Хүлээх зуур sheet хаагдаж эхэлсэн бол (current биш) pop хийхгүй —
      // эс бөгөөс доорх газрын хуудас хаагдана.
      if (ModalRoute.isCurrentOf(context) ?? false) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Илгээж чадсангүй. Дахин оролдоно уу';
        });
      }
    }
  }

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16),
        child: _loading
          ? ListView(controller: scrollCtrl, children: const [
              SizedBox(height: 14),
              _SkelBox(height: 26, width: 200, radius: AppRadii.sm),
              SizedBox(height: 14),
              _SkelBox(height: 180, radius: AppRadii.lg),
              SizedBox(height: 14),
              _SkelBox(height: 70, radius: AppRadii.lg),
              SizedBox(height: 10),
              _SkelBox(height: 70, radius: AppRadii.lg),
            ])
          : ListView(controller: scrollCtrl, children: [
              // Бариулыг theme (showDragHandle) зурна — энд дахин зурахгүй.
              // Гарчиг доорх картуудтай нэг ирмэгт (16px).
              const AppSheetHeader(title: 'Үнэлгээ ба сэтгэгдэл',
                padding: EdgeInsets.zero),
              const SizedBox(height: 14),
              // Бичих — шилэн карт хэмнэл
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface.withValues(alpha: 0.7),
                  borderRadius: AppRadii.lgR,
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
                          color: AppColors.rating, size: 34,
                          shadows: i <= _myRating
                            ? [Shadow(color: AppColors.rating.withValues(alpha: 0.5),
                                blurRadius: 10)]
                            : null)))]),
                  const SizedBox(height: 10),
                  TextField(controller: _commentCtrl, maxLines: 2,
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(hintText: 'Сэтгэгдэл...',
                      hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
                      filled: true, fillColor: AppColors.bgElevated,
                      border: OutlineInputBorder(borderRadius: AppRadii.mdR,
                        borderSide: BorderSide.none))),
                  const SizedBox(height: 10),
                  // Илгээх (DS-03) — од сонгоогүй үед идэвхгүй гадарга,
                  // илгээж байхад owl + шошго хэвээр.
                  GradientButton(label: 'Илгээх', busy: _busy,
                    onPressed: _myRating == 0 ? null : _submit),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Semantics(liveRegion: true,
                      child: Text(_error!, style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.danger))),
                  ],
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
                    borderRadius: AppRadii.lgR,
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
