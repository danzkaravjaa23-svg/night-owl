import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';

const _kMonths = ['', '1-р сар','2-р сар','3-р сар','4-р сар','5-р сар','6-р сар',
  '7-р сар','8-р сар','9-р сар','10-р сар','11-р сар','12-р сар'];

String _venueEmoji(String? t) => switch (t) {
  'pub' => '🍺', 'lounge' => '🍸', 'nightclub' => '🎧',
  'rooftop' => '🌃', 'karaoke' => '🎤', 'jazz' => '🎷', 'bar' => '🍻', _ => '🎵',
};

class VenueDetailScreen extends StatefulWidget {
  final String venueId;
  const VenueDetailScreen({super.key, required this.venueId});
  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  Map<String, dynamic>? _venue;
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;

  String? get _ownerId => _venue?['owner_id'] as String?;
  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await SupabaseService.client.from('venues')
          .select('id, name, district, venue_type, description, cover_url, lat, lng, '
              'rating, review_count, owner_id, phone, open_time, close_time')
          .eq('id', widget.venueId).maybeSingle();
      final now = DateTime.now().subtract(const Duration(hours: 3)).toIso8601String();
      final ev = await SupabaseService.client.from('events')
          .select('id, title, cover_url, starts_at, price')
          .eq('venue_id', widget.venueId)
          .gte('starts_at', now)
          .order('starts_at').limit(10);
      if (mounted) setState(() {
        _venue = v;
        _events = (ev as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDirections() async {
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReviewsSheet(venueId: widget.venueId),
    ).then((_) => _load()); // хаагдахад дундаж шинэчлэх
  }

  @override
  Widget build(BuildContext context) {
    final name = _venue?['name'] as String? ?? 'Venue';
    final type = _venue?['venue_type'] as String?;
    final district = _venue?['district'] as String?;
    final desc = _venue?['description'] as String?;
    final cover = _venue?['cover_url'] as String?;
    final avg = (_venue?['rating'] as num?)?.toDouble() ?? 0;
    final count = _venue?['review_count'] as int? ?? 0;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.accentStart, strokeWidth: 2))
        : CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 220, pinned: true,
              backgroundColor: AppColors.bgBase,
              leading: IconButton(onPressed: () => context.pop(),
                icon: Container(width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.5)),
                  child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white))),
              flexibleSpace: FlexibleSpaceBar(
                background: cover != null
                  ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _coverFallback(type))
                  : _coverFallback(type)),
            ),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Нэр + төрөл
                Text(name, style: AppTextStyles.h1),
                const SizedBox(height: 4),
                Row(children: [
                  if (type != null) ...[
                    Text('${_venueEmoji(type)} $type',
                      style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                  ],
                  if (district != null) ...[
                    const Icon(Icons.location_on, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 2),
                    Text(district, style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textSecondary)),
                  ],
                ]),
                const SizedBox(height: 14),
                // ⭐ Дундаж үнэлгээ
                Row(children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 22),
                  const SizedBox(width: 4),
                  Text(avg.toStringAsFixed(1), style: AppTextStyles.h2),
                  const SizedBox(width: 6),
                  Text('($count үнэлгээ)', style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textSecondary)),
                ]),
                // Цагийн хуваарь + утас
                if (_venue?['open_time'] != null && (_venue!['open_time'] as String).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.schedule, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('${_venue!['open_time']} - ${_venue?['close_time'] ?? ''}',
                      style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary)),
                  ]),
                ],
                if (_venue?['phone'] != null && (_venue!['phone'] as String).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse('tel:${_venue!['phone']}')),
                    child: Row(children: [
                      const Icon(Icons.phone, size: 16, color: AppColors.accentStart),
                      const SizedBox(width: 6),
                      Text(_venue!['phone'] as String, style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.accentStart, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                // Үйлдлүүд
                Row(children: [
                  Expanded(child: _actionBtn(Icons.directions_rounded, 'Чиглэл',
                    _openDirections, filled: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _actionBtn(Icons.star_outline_rounded, 'Үнэлгээ',
                    _openReviews)),
                ]),
                if (_ownerId != null && _ownerId != _myId) ...[
                  const SizedBox(height: 12),
                  _actionBtn(Icons.chat_bubble_outline_rounded, 'Эзэнтэй чатлах',
                    () => context.push('/dm/$_ownerId')),
                ],
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('ТАНИЛЦУУЛГА', style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.textSecondary, letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  Text(desc, style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textPrimary, height: 1.5)),
                ],
                // Events
                if (_events.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('🎉 ЭНД БОЛОХ ЭВЕНТҮҮД', style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.textSecondary, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  for (final e in _events) _eventTile(e),
                ],
                const SizedBox(height: 30),
              ]),
            )),
          ]),
    );
  }

  Widget _coverFallback(String? type) => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: Center(child: Text(_venueEmoji(type), style: const TextStyle(fontSize: 72))));

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, {bool filled = false}) =>
    GestureDetector(onTap: onTap, child: Container(
      height: 50,
      decoration: BoxDecoration(
        gradient: filled ? AppColors.accentGradient : null,
        color: filled ? null : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: filled ? null : Border.all(color: AppColors.hairline)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: filled ? Colors.white : AppColors.textPrimary),
        const SizedBox(width: 8),
        Text(label, style: AppTextStyles.btn.copyWith(
          color: filled ? Colors.white : AppColors.textPrimary, fontSize: 14)),
      ])));

  Widget _eventTile(Map<String, dynamic> e) {
    final starts = DateTime.tryParse(e['starts_at'] as String? ?? '');
    final dateStr = starts == null ? '' :
      '${starts.toLocal().day} ${_kMonths[starts.toLocal().month]}, '
      '${starts.toLocal().hour.toString().padLeft(2,'0')}:${starts.toLocal().minute.toString().padLeft(2,'0')}';
    final price = e['price'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline)),
      child: Row(children: [
        ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
          child: SizedBox(width: 70, height: 70,
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
          child: Text(price == 0 ? 'Үнэгүй' : '₮$price',
            style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Widget _evPlaceholder() => Container(
    decoration: const BoxDecoration(gradient: AppColors.accentGradient),
    child: const Center(child: Text('🎉', style: TextStyle(fontSize: 26))));
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
    if (_myRating == 0 || _myId.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client.from('venue_reviews').upsert({
        'venue_id': widget.venueId, 'user_id': _myId,
        'rating': _myRating, 'comment': _commentCtrl.text.trim(),
      }, onConflict: 'venue_id, user_id');
      await _load();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Widget _stars(int n, {double size = 14}) => Row(mainAxisSize: MainAxisSize.min,
    children: [for (int i = 1; i <= 5; i++)
      Icon(i <= n ? Icons.star_rounded : Icons.star_border_rounded,
        color: const Color(0xFFFFB300), size: size)]);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 12),
        child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accentStart, strokeWidth: 2))
          : ListView(controller: scrollCtrl, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                color: AppColors.hairline, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Үнэлгээ ба сэтгэгдэл', style: AppTextStyles.h2),
              const SizedBox(height: 14),
              // Бичих
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Таны үнэлгээ', style: AppTextStyles.labelLg),
                  const SizedBox(height: 8),
                  Row(children: [for (int i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => setState(() => _myRating = i),
                      child: Padding(padding: const EdgeInsets.only(right: 4),
                        child: Icon(i <= _myRating ? Icons.star_rounded : Icons.star_border_rounded,
                          color: const Color(0xFFFFB300), size: 34)))]),
                  const SizedBox(height: 10),
                  TextField(controller: _commentCtrl, maxLines: 2,
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                    decoration: InputDecoration(hintText: 'Сэтгэгдэл...',
                      hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
                      filled: true, fillColor: AppColors.bgElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none))),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: (_myRating == 0 || _busy) ? null : _submit,
                    child: Container(height: 44, width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: _myRating == 0 ? null : AppColors.accentGradient,
                        color: _myRating == 0 ? AppColors.bgElevated : null,
                        borderRadius: BorderRadius.circular(12)),
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
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      AppAvatar(imageUrl: r['avatar_url'] as String?,
                        initial: (r['username'] as String).replaceAll('@','').isNotEmpty
                          ? (r['username'] as String).replaceAll('@','')[0].toUpperCase() : '?',
                        size: 30),
                      const SizedBox(width: 8),
                      Expanded(child: Text('@${(r['username'] as String).replaceAll('@','')}',
                        style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary))),
                      _stars(r['rating'] as int? ?? 0),
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
