import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/discovery_service.dart';
import '../widgets/discovery_back_button.dart';
import '../widgets/venue_picker.dart';
import 'discovery_screen.dart';
import '../../profile/utils/app_links.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  final String userId;
  final String? collectionId;
  const CollectionsScreen({super.key, required this.userId, this.collectionId});
  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  DiscoveryService get _service => ref.read(discoveryServiceProvider);
  late Future<List<JsonRow>> _data;
  late (String?, String, int) _requestKey;
  bool _busy = false;
  bool get _own =>
      ref.read(sessionUserIdProvider) == widget.userId &&
      _service.me == widget.userId;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _requestKey = (
      ref.read(sessionUserIdProvider),
      widget.userId,
      ref.read(socialVersionProvider)
    );
    _data = _service.collections(widget.userId);
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy || !_own) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(discoveryError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    var value = '';
    final title = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Шинэ цуглуулга'),
                content: TextField(
                    onChanged: (v) => value = v,
                    maxLength: 80,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Нэр')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Болих')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, value.trim()),
                      child: const Text('Үүсгэх'))
                ]));
    if (title != null && title.isNotEmpty) {
      await _change(() async {
        await _service.createCollection(title);
      });
    }
  }

  Future<void> _delete(JsonRow row) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Цуглуулгыг устгах уу?'),
                content: Text(row['title'] as String),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Болих')),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Устгах'))
                ]));
    if (yes == true) {
      await _change(() => _service.deleteCollection(row['id'] as String));
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestKey = (
      ref.watch(sessionUserIdProvider),
      widget.userId,
      ref.watch(socialVersionProvider)
    );
    if (requestKey != _requestKey) _reload();
    return Scaffold(
        appBar: AppBar(
            leading: const DiscoveryBackButton(),
            title: const Text('Газрын цуглуулга'),
            actions: [
              if (_own)
                IconButton(
                    tooltip: 'Цуглуулга нэмэх',
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.add))
            ]),
        body: FutureBuilder<List<JsonRow>>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return DiscoveryProblem(
                    error: snapshot.error!, retry: () => setState(_reload));
              }
              if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!
                  .where((r) =>
                      widget.collectionId == null ||
                      r['id'] == widget.collectionId)
                  .toList();
              if (data.isEmpty) {
                return const Center(child: Text('Цуглуулга алга'));
              }
              return ListView(children: [
                if (_busy) const LinearProgressIndicator(),
                for (final row in data) ...[
                  ListTile(
                      title: Text(row['title'] as String,
                          style: Theme.of(context).textTheme.titleLarge),
                      subtitle: Text(row['is_public'] == true
                          ? 'Нийтийн цуглуулга'
                          : 'Зөвхөн надад'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            tooltip: 'Холбоос хуулах',
                            icon: const Icon(Icons.ios_share),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(
                                  text:
                                      '${appOrigin()}/#/collections/${widget.userId}?list=${row['id']}'));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Холбоос хууллаа')));
                              }
                            }),
                        if (_own)
                          PopupMenuButton<String>(
                              tooltip: 'Цуглуулгын үйлдэл',
                              onSelected: (v) {
                                if (v == 'delete') {
                                  _delete(row);
                                } else {
                                  _change(() => _service.collectionVisibility(
                                      row['id'] as String,
                                      row['is_public'] != true));
                                }
                              },
                              itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'visibility',
                                        child: Text(row['is_public'] == true
                                            ? 'Хувийн болгох'
                                            : 'Нийтийн болгох')),
                                    const PopupMenuItem(
                                        value: 'delete', child: Text('Устгах'))
                                  ])
                      ])),
                  for (final item in (row['collection_places'] as List? ?? []))
                    ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text((item['venue_catalog'] as Map?)?['name']
                                as String? ??
                            'Газар'),
                        subtitle: Text(item['note'] as String? ?? ''),
                        onTap: () => context.push(
                            '/place/${Uri.encodeComponent(item['venue_ref'] as String)}'),
                        trailing: _own
                            ? IconButton(
                                tooltip: 'Цуглуулгаас хасах',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: _busy
                                    ? null
                                    : () => _change(() => _service.removePlace(
                                        row['id'] as String,
                                        item['venue_ref'] as String)))
                            : null),
                  if (_own)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: OutlinedButton.icon(
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text('Газар нэмэх'),
                            onPressed: _busy
                                ? null
                                : () async {
                                    final venue =
                                        await pickDiscoveryVenue(context);
                                    if (venue != null) {
                                      await _change(() => _service.addPlace(
                                          row['id'] as String,
                                          venue['ref'] as String));
                                    }
                                  })),
                  const Divider(height: 32),
                ]
              ]);
            }));
  }
}
