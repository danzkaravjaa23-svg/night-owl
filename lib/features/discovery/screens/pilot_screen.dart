import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../admin/providers/admin_console_provider.dart';
import '../services/discovery_service.dart';
import 'discovery_screen.dart';

String cohortPercent(num count, num eligible) => eligible == 0
    ? 'Хугацаа болоогүй'
    : '${(count * 100 / eligible).toStringAsFixed(1)}% ($count/$eligible)';

class PilotScreen extends ConsumerStatefulWidget {
  const PilotScreen({super.key});
  @override
  ConsumerState<PilotScreen> createState() => _PilotScreenState();
}

class _PilotScreenState extends ConsumerState<PilotScreen> {
  final _service = DiscoveryService();
  late Future<JsonRow> _data;
  late Future<List<JsonRow>> _candidates;
  String _kind = 'creator', _query = '';
  bool _busy = false;
  Timer? _debounce;
  AdminConsoleAccess? _access;
  String? _owner;
  bool get _current =>
      mounted &&
      (_access?.session.isCurrent ?? (_owner != null && _owner == _service.me));

  Future<JsonRow> _overview() async {
    final access = _access;
    if (access == null) return _service.pilot();
    return Map<String, dynamic>.from(await access.service
        .callRpc(access.session, 'get_pilot_overview', {}) as Map);
  }

  Future<List<JsonRow>> _searchCandidates() async {
    final access = _access;
    if (access == null) return _service.pilotCandidates(_kind, _query);
    final rows = await access.service.callRpc(access.session,
        'search_pilot_candidates', {'p_kind': _kind, 'p_query': _query});
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _access = ref.read(adminConsoleAccessProvider);
    _owner = _service.me;
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    _data = _overview();
    _candidates = _searchCandidates();
  }

  Future<void> _set(String id, bool value) async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    try {
      final access = _access;
      if (access == null) {
        await _service.pilotEntry(_kind, id, value);
      } else {
        await access.service.callRpc(access.session, 'set_pilot_entry',
            {'p_kind': _kind, 'p_id': id, 'p_enabled': value});
      }
      if (_current) setState(_reload);
    } catch (e) {
      if (mounted && _current) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(discoveryError(e))));
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppHeader.title(
          title: 'Эхний туршилт',
          compact: true,
          fallbackLocation: '/admin',
          actions: [
            GlassIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Шинэчлэх',
                onTap: () => setState(_reload))
          ]),
      body: FutureBuilder<JsonRow>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return DiscoveryProblem(
                  error: snapshot.error!, retry: () => setState(_reload));
            }
            if (!snapshot.hasData) {
              return const Center(child: OwlLoading());
            }
            final data = snapshot.data!;
            final entries = (data[{
                  'creator': 'creators',
                  'participant': 'participants',
                  'venue': 'places',
                  'content': 'posts'
                }[_kind]] as List? ??
                []);
            Widget count(Object? value) =>
                Text('$value', style: AppTextStyles.h3);
            return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.x2, AppSpacing.page, AppSpacing.x8),
                children: [
                  if (_busy)
                    const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.x3),
                        child: LinearProgressIndicator()),
                  Text('Бодит оролцогчид', style: AppTextStyles.title),
                  const SizedBox(height: AppSpacing.x3),
                  Card(
                      child: Column(children: [
                    ListTile(
                        title: const Text('Creator · зорилт 10–15'),
                        trailing: count(data['creator_count'])),
                    ListTile(
                        title: const Text('Шалгасан газар · зорилт 20–30'),
                        trailing: count(data['venues'])),
                    ListTile(
                        title: const Text('Шалгасан контент · зорилт 60–100'),
                        trailing: count(data['content'])),
                  ])),
                  const SizedBox(height: AppSpacing.x6),
                  Text('Элссэнээс хойших үр дүн', style: AppTextStyles.title),
                  const SizedBox(height: AppSpacing.x3),
                  Card(
                      child: Column(children: [
                    ListTile(
                        title: const Text(
                            'Эхний 24 цагт дагасан / газар хадгалсан'),
                        subtitle: Text(cohortPercent(data['activated'] as num,
                            data['activation_eligible'] as num))),
                    ListTile(
                        title: const Text('Эхний 24 цагт хүн дагасан'),
                        subtitle: Text(cohortPercent(
                            data['first_day_followed'] as num,
                            data['activation_eligible'] as num))),
                    ListTile(
                        title: const Text('Эхний 24 цагт газар хадгалсан'),
                        subtitle: Text(cohortPercent(
                            data['first_day_saved'] as num,
                            data['activation_eligible'] as num))),
                    ListTile(
                        title: const Text('7 дахь хоногт эргэн ирсэн'),
                        subtitle: Text(cohortPercent(data['d7_returned'] as num,
                            data['d7_eligible'] as num))),
                    ListTile(
                        title:
                            const Text('Өөр өдрүүдэд дахин нийтэлсэн creator'),
                        trailing: count(data['repeat_creators'])),
                    ListTile(
                        title: const Text('Чиглэл авалт · хүн/газар/өдрөөр'),
                        trailing: count(data['directions'])),
                  ])),
                  const SizedBox(height: AppSpacing.x6),
                  DropdownButtonFormField<String>(
                      initialValue: _kind,
                      // Popup цэс шиг: bgElevated, 14 px булан.
                      borderRadius: AppRadii.mdR,
                      dropdownColor: AppColors.bgElevated,
                      decoration: const InputDecoration(labelText: 'Бүртгэл'),
                      items: const [
                        DropdownMenuItem(
                            value: 'creator', child: Text('Creator-ууд')),
                        DropdownMenuItem(
                            value: 'participant', child: Text('Туршигчид')),
                        DropdownMenuItem(
                            value: 'venue', child: Text('Шалгасан газрууд')),
                        DropdownMenuItem(
                            value: 'content', child: Text('Шалгасан контент'))
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _kind = v;
                            _reload();
                          });
                        }
                      }),
                  for (final row in entries)
                    ListTile(
                        title: Text('${row['label']}'),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          if (_kind == 'venue')
                            IconButton(
                                tooltip: 'Газрын мэдээлэл засах',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  await context.push(
                                      '/admin/place-review/${Uri.encodeComponent(row['id'] as String)}');
                                  if (mounted) setState(_reload);
                                }),
                          IconButton(
                              tooltip: 'Туршилтаас хасах',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _busy
                                  ? null
                                  : () => _set('${row['id']}', false))
                        ])),
                  const SizedBox(height: AppSpacing.x3),
                  TextField(
                      decoration: const InputDecoration(
                          labelText: 'Бүртгэлээс хайх',
                          prefixIcon: Icon(AppIcons.search)),
                      onChanged: (v) {
                        _query = v;
                        _debounce?.cancel();
                        _debounce =
                            Timer(const Duration(milliseconds: 300), () {
                          if (_current) {
                            setState(() => _candidates = _searchCandidates());
                          }
                        });
                      }),
                  FutureBuilder<List<JsonRow>>(
                      future: _candidates,
                      builder: (context, candidates) {
                        if (candidates.hasError) {
                          return DiscoveryProblem(
                              error: candidates.error!,
                              retry: () => setState(_reload));
                        }
                        if (!candidates.hasData) {
                          return const LinearProgressIndicator();
                        }
                        if (candidates.data!.isEmpty) {
                          return const ListTile(title: Text('Илэрц алга'));
                        }
                        return Column(children: [
                          for (final row in candidates.data!)
                            ListTile(
                                title: Text('${row['label']}'),
                                trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_kind == 'venue')
                                        IconButton(
                                            tooltip: 'Мэдээлэл бэлтгэх',
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                            onPressed: () async {
                                              await context.push(
                                                  '/admin/place-review/${Uri.encodeComponent(row['id'] as String)}');
                                              if (mounted) setState(_reload);
                                            }),
                                      IconButton(
                                          tooltip: 'Туршилтад оруулах',
                                          icon: const Icon(
                                              Icons.add_circle_outline),
                                          onPressed: _busy ||
                                                  entries.any((e) =>
                                                      e['id'] == row['id'])
                                              ? null
                                              : () =>
                                                  _set('${row['id']}', true))
                                    ]))
                        ]);
                      }),
                ]);
          }));
}
