import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/discovery_service.dart';
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
                  // Destructive confirmation (DS-03): white on dangerFill.
                  FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.dangerFill,
                          foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Устгах'))
                ]));
    if (yes == true) {
      await _change(() => _service.deleteCollection(row['id'] as String));
    }
  }

  Future<void> _copyLink(JsonRow row) async {
    await Clipboard.setData(ClipboardData(
        text: '${appOrigin()}/#/collections/${widget.userId}?list=${row['id']}'));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Холбоос хууллаа')));
    }
  }

  Future<void> _addPlace(JsonRow row) async {
    final venue = await pickDiscoveryVenue(context);
    if (venue != null) {
      await _change(
          () => _service.addPlace(row['id'] as String, venue['ref'] as String));
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
        appBar: AppHeader.title(
            title: 'Газрын цуглуулга',
            compact: true,
            fallbackLocation: '/discovery',
            actions: [
              if (_own)
                GlassIconButton(
                    icon: AppIcons.add,
                    tooltip: 'Цуглуулга нэмэх',
                    onTap: _busy ? null : _create)
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
                return const Center(child: OwlLoading());
              }
              final data = snapshot.data!
                  .where((r) =>
                      widget.collectionId == null ||
                      r['id'] == widget.collectionId)
                  .toList();
              if (data.isEmpty) {
                return const EmptyState(
                    icon: Icons.bookmarks_outlined, title: 'Цуглуулга алга');
              }
              return ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                      AppSpacing.x2, AppSpacing.page, AppSpacing.x8),
                  children: [
                    if (_busy)
                      const Padding(
                          padding: EdgeInsets.only(bottom: AppSpacing.x3),
                          child: LinearProgressIndicator()),
                    for (final row in data)
                      Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.x4),
                          child: _collection(row)),
                  ]);
            }));
  }

  /// One collection on the shared card surface: title row, its places and,
  /// for the owner, "Газар нэмэх".
  Widget _collection(JsonRow row) => Card(
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x2),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                    title: Text(row['title'] as String,
                        style: AppTextStyles.title),
                    subtitle: Text(row['is_public'] == true
                        ? 'Нийтийн цуглуулга'
                        : 'Зөвхөн надад'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Холбоос хуулах',
                          icon: Icon(AppIcons.share),
                          onPressed: () => _copyLink(row)),
                      if (_own)
                        PopupMenuButton<String>(
                            tooltip: 'Цуглуулгын үйлдэл',
                            icon: const Icon(AppIcons.more),
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
                      leading: const Icon(AppIcons.venue),
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
                      padding: const EdgeInsets.fromLTRB(AppSpacing.x4,
                          AppSpacing.x1, AppSpacing.x4, AppSpacing.x2),
                      child: OutlineButton(
                          size: GradientButtonSize.md,
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: 'Газар нэмэх',
                          onPressed: _busy ? null : () => _addPlace(row))),
              ])));
}
