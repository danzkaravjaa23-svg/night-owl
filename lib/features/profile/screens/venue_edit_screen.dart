import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/image_uploader.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../map/providers/venue_provider.dart';

/// Газрын төрөл — түлхүүр нь өгөгдлийн санд (venue_type) хэвээр англиар
/// хадгалагдана, харин дэлгэц дээр монголоор харагдана.
const _kVenueTypes = <String, String>{
  'bar':       'Бар',
  'lounge':    'Лаунж',
  'nightclub': 'Шөнийн клуб',
  'pub':       'Паб',
  'rooftop':   'Дээвэр бар',
  'karaoke':   'Караоке',
  'jazz':      'Жазз',
};

class VenueEditScreen extends ConsumerStatefulWidget {
  const VenueEditScreen({super.key});
  @override
  ConsumerState<VenueEditScreen> createState() => _VenueEditScreenState();
}

class _VenueEditScreenState extends ConsumerState<VenueEditScreen> {
  final _nameCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _openCtrl = TextEditingController();
  final _closeCtrl = TextEditingController();
  String _type = 'bar';
  String? _venueId;
  String? _coverUrl;
  Uint8List? _coverBytes;
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false; // ачаалал бүтэлгүйтвэл save-ийг хориглоно (давхар venue үүсэхээс сэргийлнэ)
  String? _error;

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _loadFailed = false; });
    try {
      final data = await SupabaseService.client
          .from('venues').select()
          .eq('owner_id', _myId)
          .limit(1).maybeSingle();
      if (!mounted) return;
      if (data != null) {
        _venueId = data['id'] as String;
        _nameCtrl.text = data['name'] as String? ?? '';
        _districtCtrl.text = data['district'] as String? ?? '';
        _descCtrl.text = data['description'] as String? ?? '';
        _latCtrl.text = (data['lat']?.toString()) ?? '';
        _lngCtrl.text = (data['lng']?.toString()) ?? '';
        _type = data['venue_type'] as String? ?? 'bar';
        _coverUrl = data['cover_url'] as String?;
        _phoneCtrl.text = data['phone'] as String? ?? '';
        _openCtrl.text = data['open_time'] as String? ?? '';
        _closeCtrl.text = data['close_time'] as String? ?? '';
      } else {
        // Шинэ venue — UB төв default координат
        _latCtrl.text = AppConstants.ubLat.toString();
        _lngCtrl.text = AppConstants.ubLng.toString();
      }
    } catch (_) {
      // Ачаалал бүтэлгүйтвэл _venueId null хэвээр — save хийвэл давхар venue үүсэх
      // эрсдэлтэй тул save-ийг хориглож, дахин оролдох сонголт харуулна.
      if (mounted) _loadFailed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickCover() async {
    final b = await ImageUploader.pickBytesFromGallery();
    if (b != null && mounted) setState(() => _coverBytes = b);
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Газрын нэр шаардлагатай');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      String? coverUrl = _coverUrl;
      if (_coverBytes != null) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final uploaded = await ImageUploader.uploadBytes(
          bytes: _coverBytes!, bucket: 'venues', path: '$_myId/cover_$ts.jpg');
        // Upload бүтэлгүйтвэл (null) — хуучин cover-оор чимээгүй хадгалахгүй, алдаа мэдэгдэнэ
        if (uploaded == null) {
          setState(() { _busy = false; _error = 'Зураг илгээж чадсангүй. Дахин оролдоно уу'; });
          return;
        }
        coverUrl = uploaded;
      }
      final row = <String, dynamic>{
        'owner_id': _myId,
        'name': _nameCtrl.text.trim(),
        'venue_type': _type,
        'district': _districtCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'lat': double.tryParse(_latCtrl.text.trim()),
        'lng': double.tryParse(_lngCtrl.text.trim()),
        'phone': _phoneCtrl.text.trim(),
        'open_time': _openCtrl.text.trim(),
        'close_time': _closeCtrl.text.trim(),
        if (coverUrl != null) 'cover_url': coverUrl,
      };
      if (_venueId != null) {
        await SupabaseService.client.from('venues').update(row).eq('id', _venueId!);
      } else {
        await SupabaseService.client.from('venues').insert(row);
      }
      if (!mounted) return;
      ref.invalidate(venuesProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Хадгалагдлаа ✓'), behavior: SnackBarBehavior.floating));
      context.pop();
    } catch (_) {
      if (mounted) {
        setState(() { _busy = false; _error = 'Хадгалж чадсангүй. Дахин оролдоно уу'; });
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _districtCtrl.dispose(); _descCtrl.dispose();
    _latCtrl.dispose(); _lngCtrl.dispose();
    _phoneCtrl.dispose(); _openCtrl.dispose(); _closeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase, elevation: 0,
        leading: IconButton(onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: Text(_venueId != null ? 'Газар засах' : 'Газар үүсгэх',
          style: AppTextStyles.h2),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.accentStart, strokeWidth: 2))
        : _loadFailed
        ? _loadError()
        : ListView(padding: const EdgeInsets.all(20), children: [
            // Cover
            GestureDetector(
              onTap: _pickCover,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: AppColors.bgElevated, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                  image: _coverBytes != null
                    ? DecorationImage(image: MemoryImage(_coverBytes!), fit: BoxFit.cover)
                    : (_coverUrl != null
                        ? DecorationImage(image: NetworkImage(_coverUrl!), fit: BoxFit.cover)
                        : null)),
                child: (_coverBytes == null && _coverUrl == null)
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_photo_alternate_outlined, color: AppColors.textTertiary, size: 36),
                      SizedBox(height: 6),
                      Text('Cover зураг', style: TextStyle(color: AppColors.textTertiary)),
                    ]))
                  : null),
            ),
            const SizedBox(height: 16),
            _field(_nameCtrl, 'Газрын нэр'),
            const SizedBox(height: 14),
            Text('ТӨРӨЛ', style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textSecondary, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _kVenueTypes.entries.map((e) {
              final active = _type == e.key;
              return GestureDetector(
                onTap: () => setState(() => _type = e.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.accentStart : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? AppColors.accentStart : AppColors.hairline)),
                  child: Text(e.value, style: AppTextStyles.bodyXs.copyWith(
                    color: active ? Colors.white : AppColors.textSecondary,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
              );
            }).toList()),
            const SizedBox(height: 14),
            _field(_districtCtrl, 'Дүүрэг'),
            const SizedBox(height: 14),
            _field(_descCtrl, 'Тайлбар', lines: 3),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _field(_latCtrl, 'Өргөрөг (lat)', number: true)),
              const SizedBox(width: 12),
              Expanded(child: _field(_lngCtrl, 'Уртраг (lng)', number: true)),
            ]),
            const SizedBox(height: 14),
            _field(_phoneCtrl, 'Холбоо барих утас', number: true),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _field(_openCtrl, 'Нээх цаг (ж: 18:00)')),
              const SizedBox(width: 12),
              Expanded(child: _field(_closeCtrl, 'Хаах цаг (ж: 03:00)')),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.bodyXs.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: 22),
            GradientButton(
              label: 'Хадгалах',
              busy: _busy,
              onPressed: _save,
            ),
          ]),
    );
  }

  // Ачаалал бүтэлгүйтсэн үед — форм харуулахгүй (давхар venue үүсэхээс сэргийлнэ)
  Widget _loadError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined,
        color: AppColors.textTertiary, size: 48),
      const SizedBox(height: 14),
      Text('Ачаалж чадсангүй', style: AppTextStyles.h3),
      const SizedBox(height: 6),
      Text('Дахин оролдоно уу', style: AppTextStyles.bodySm.copyWith(
        color: AppColors.textTertiary)),
      const SizedBox(height: 18),
      GestureDetector(
        onTap: _load,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
              borderRadius: BorderRadius.circular(12)),
            child: Text('Дахин оролдох',
              style: AppTextStyles.btn.copyWith(color: Colors.white)),
          ),
        ),
      ),
    ]),
  );

  Widget _field(TextEditingController c, String hint, {int lines = 1, bool number = false}) =>
    TextField(
      controller: c, maxLines: lines,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
      // Дүрс/хүрээ/дүүргэлтийг апп даяарх InputDecorationTheme-ээс өвлөнө
      decoration: InputDecoration(hintText: hint));
}
