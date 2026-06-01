import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/image_uploader.dart';
import '../providers/event_provider.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});
  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String? _venueId;
  String? _venueName;
  DateTime? _when;
  Uint8List? _cover;
  bool _busy = false;
  String? _error;

  Future<void> _pickVenue() async {
    final v = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _VenuePick(),
    );
    if (v != null && mounted) {
      setState(() { _venueId = v['id'] as String; _venueName = v['name'] as String; });
    }
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context, initialDate: DateTime.now(),
      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context, initialTime: const TimeOfDay(hour: 21, minute: 0));
    if (t == null || !mounted) return;
    setState(() => _when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _pickCover() async {
    final b = await ImageUploader.pickBytesFromGallery();
    if (b != null && mounted) setState(() => _cover = b);
  }

  Future<void> _save() async {
    final user = SupabaseService.currentUser;
    if (user == null || _busy) return;
    if (_titleCtrl.text.trim().isEmpty || _when == null) {
      setState(() => _error = 'Гарчиг ба огноо шаардлагатай');
      return;
    }
    if (_venueId == null) {
      setState(() => _error = 'Эвент зохиох газраа сонгоно уу (зөвхөн өөрийн venue)');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      String? coverUrl;
      if (_cover != null) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        coverUrl = await ImageUploader.uploadBytes(
          bytes: _cover!, bucket: 'posts', path: '${user.id}/event_$ts.jpg');
      }
      await SupabaseService.client.from('events').insert({
        'organizer_id': user.id,
        'venue_id': _venueId,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'starts_at': _when!.toIso8601String(),
        'price': int.tryParse(_priceCtrl.text.trim()) ?? 0,
        if (coverUrl != null) 'cover_url': coverUrl,
      });
      if (!mounted) return;
      ref.invalidate(upcomingEventsProvider);
      context.pop();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose(); _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final whenStr = _when == null ? 'Огноо · цаг сонгох'
        : '${_when!.year}/${_when!.month}/${_when!.day}  '
          '${_when!.hour.toString().padLeft(2,'0')}:${_when!.minute.toString().padLeft(2,'0')}';
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase, elevation: 0,
        leading: IconButton(onPressed: () => context.pop(),
          icon: const Icon(Icons.close, color: AppColors.textPrimary)),
        title: Text('Эвент нэмэх', style: AppTextStyles.h2),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // Cover
        GestureDetector(
          onTap: _pickCover,
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.bgElevated, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
              image: _cover != null
                ? DecorationImage(image: MemoryImage(_cover!), fit: BoxFit.cover) : null),
            child: _cover == null
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_photo_alternate_outlined, color: AppColors.textTertiary, size: 36),
                  SizedBox(height: 6),
                  Text('Cover зураг', style: TextStyle(color: AppColors.textTertiary)),
                ]))
              : null),
        ),
        const SizedBox(height: 16),
        _field(_titleCtrl, 'Эвентийн нэр'),
        const SizedBox(height: 12),
        _tile(Icons.location_on_outlined, _venueName ?? 'Газар сонгох', _pickVenue),
        const SizedBox(height: 12),
        _tile(Icons.schedule, whenStr, _pickDateTime),
        const SizedBox(height: 12),
        _field(_priceCtrl, 'Тасалбарын үнэ (₮) — 0 = үнэгүй', number: true),
        const SizedBox(height: 12),
        _field(_descCtrl, 'Тайлбар', lines: 3),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.bodyXs.copyWith(color: AppColors.error)),
        ],
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _busy ? null : _save,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: _busy
              ? const SizedBox(width: 22, height: 22, child:
                  CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('Эвент нийтлэх', style: AppTextStyles.btn.copyWith(color: Colors.white))),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String hint, {int lines = 1, bool number = false}) =>
    TextField(
      controller: c, maxLines: lines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
        filled: true, fillColor: AppColors.bgElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)));

  Widget _tile(IconData i, String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline)),
      child: Row(children: [
        Icon(i, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary))),
        const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
      ])));
}

class _VenuePick extends StatefulWidget {
  const _VenuePick();
  @override
  State<_VenuePick> createState() => _VenuePickState();
}

class _VenuePickState extends State<_VenuePick> {
  List<Map<String, dynamic>> _r = [];
  bool _loading = false;
  @override
  void initState() { super.initState(); _search(''); }
  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final me = SupabaseService.currentUser?.id ?? '';
      // Зөвхөн ӨӨРИЙН эзэмшдэг venue (event зөвхөн эзэн нэмнэ)
      var query = SupabaseService.client.from('venues')
          .select('id, name, district').eq('owner_id', me);
      if (q.isNotEmpty) query = query.ilike('name', '%$q%');
      _r = ((await query.limit(30)) as List).cast<Map<String, dynamic>>();
    } catch (_) { _r = []; }
    if (mounted) setState(() => _loading = false);
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Газар сонгох', style: AppTextStyles.labelLg),
      const SizedBox(height: 12),
      TextField(autofocus: true, onChanged: _search,
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: 'Хайх...',
          prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
          filled: true, fillColor: AppColors.bgSurface, isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      const SizedBox(height: 8),
      SizedBox(height: 320, child: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.accentStart, strokeWidth: 2))
        : _r.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20),
              child: Text('Танд эзэмшдэг газар алга.\nЭхлээд "Газраа удирдах"-аас venue үүсгэнэ үү.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary))))
          : ListView.builder(itemCount: _r.length, itemBuilder: (_, i) => ListTile(
            leading: const Icon(Icons.location_on, color: AppColors.accentStart),
            title: Text(_r[i]['name'] as String? ?? '',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary)),
            onTap: () => Navigator.pop(context, _r[i])))),
      const SizedBox(height: 12),
    ]));
}
