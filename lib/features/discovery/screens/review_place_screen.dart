import 'package:flutter/material.dart';
import '../../../core/utils/image_uploader.dart';
import '../../../core/widgets/authorized_media.dart';
import '../services/discovery_service.dart';
import '../widgets/discovery_back_button.dart';
import 'discovery_screen.dart';

class ReviewPlaceScreen extends StatefulWidget {
  final String venueRef;
  const ReviewPlaceScreen({super.key, required this.venueRef});
  @override
  State<ReviewPlaceScreen> createState() => _ReviewPlaceScreenState();
}

class _ReviewPlaceScreenState extends State<ReviewPlaceScreen> {
  final _service = DiscoveryService();
  final _address = TextEditingController(),
      _hours = TextEditingController(),
      _min = TextEditingController(),
      _max = TextEditingController(),
      _menu = TextEditingController();
  late Future<JsonRow?> _data;
  String? _cover;
  final _vibes = <String>{};
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<JsonRow?> _load() async {
    final row = await _service.venue(widget.venueRef);
    if (row != null) {
      _address.text = row['address'] as String? ?? '';
      _hours.text = row['hours'] as String? ?? '';
      _min.text = '${row['price_min'] ?? ''}';
      _max.text = '${row['price_max'] ?? ''}';
      _menu.text = row['menu_url'] as String? ?? '';
      _cover = row['cover_url'] as String?;
      _vibes.addAll((row['vibes'] as List? ?? []).cast<String>());
    }
    return row;
  }

  @override
  void dispose() {
    for (final c in [_address, _hours, _min, _max, _menu]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _photo() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await ImageUploader.pickBytesFromGallery();
      if (bytes == null) return;
      final user = _service.me;
      if (user == null) throw StateError('auth');
      final url = await ImageUploader.uploadBytes(
          bytes: bytes,
          bucket: 'venues',
          path: '$user/review_${DateTime.now().microsecondsSinceEpoch}.jpg');
      if (url == null) throw StateError('upload');
      if (mounted) setState(() => _cover = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(discoveryError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final low = int.tryParse(_min.text), high = int.tryParse(_max.text);
    if (_address.text.trim().isEmpty ||
        _hours.text.trim().isEmpty ||
        _cover == null ||
        low == null ||
        low < 0 ||
        (high != null && high < low)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Зураг, хаяг, цаг, үнийн хүрээг бүрэн бөглөөрэй')));
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.reviewVenue(widget.venueRef, {
        'address': _address.text.trim(),
        'hours': _hours.text.trim(),
        'cover_url': _cover,
        'price_min': low,
        'price_max': high ?? low,
        'menu_url': _menu.text.trim(),
        'vibes': _vibes.toList()
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(discoveryError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          leading: const DiscoveryBackButton(fallback: '/admin/pilot'),
          title: const Text('Газрын мэдээлэл засах')),
      body: FutureBuilder<JsonRow?>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return DiscoveryProblem(
                  error: snapshot.error!,
                  retry: () => setState(() => _data = _load()));
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data == null) {
              return const Center(child: Text('Газар олдсонгүй'));
            }
            return ListView(padding: const EdgeInsets.all(20), children: [
              Text(snapshot.data!['name'] as String,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              if (_cover != null)
                AspectRatio(
                    aspectRatio: 16 / 10,
                    child:
                        AuthorizedImage(imageUrl: _cover!, fit: BoxFit.cover)),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _photo,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Бодит зураг оруулах')),
              TextField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Хаяг'),
                  maxLines: 2),
              TextField(
                  controller: _hours,
                  decoration: const InputDecoration(labelText: 'Ажиллах цаг'),
                  maxLines: 3),
              TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Нэг хүний төсөв · доод (₮)')),
              TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Нэг хүний төсөв · дээд (₮)')),
              TextField(
                  controller: _menu,
                  keyboardType: TextInputType.url,
                  decoration:
                      const InputDecoration(labelText: 'Меню · HTTPS холбоос')),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: [
                for (final vibe in [
                  'Болзоо',
                  'Найзууд',
                  'Тайван',
                  'Бүжиг',
                  'Live music',
                  'Ажиллах'
                ])
                  FilterChip(
                      label: Text(vibe),
                      selected: _vibes.contains(vibe),
                      onSelected: _busy
                          ? null
                          : (v) => setState(() {
                                if (v) {
                                  _vibes.add(vibe);
                                } else {
                                  _vibes.remove(vibe);
                                }
                              }))
              ]),
              const SizedBox(height: 20),
              FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_busy ? 'Хадгалж байна' : 'Хадгалах')),
            ]);
          }));
}
