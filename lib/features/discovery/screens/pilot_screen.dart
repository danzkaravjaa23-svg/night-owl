import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/discovery_service.dart';
import '../widgets/discovery_back_button.dart';
import 'discovery_screen.dart';

String cohortPercent(num count, num eligible) => eligible == 0
    ? 'Хугацаа болоогүй'
    : '${(count * 100 / eligible).toStringAsFixed(1)}% ($count/$eligible)';

class PilotScreen extends StatefulWidget {
  const PilotScreen({super.key});
  @override
  State<PilotScreen> createState() => _PilotScreenState();
}

class _PilotScreenState extends State<PilotScreen> {
  final _service = DiscoveryService();
  late Future<JsonRow> _data;
  late Future<List<JsonRow>> _candidates;
  String _kind = 'creator', _query = '';
  bool _busy = false;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() {
    _data = _service.pilot();
    _candidates = _service.pilotCandidates(_kind, _query);
  }

  Future<void> _set(String id, bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.pilotEntry(_kind, id, value);
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

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          leading: const DiscoveryBackButton(fallback: '/admin'),
          title: const Text('Эхний туршилт'),
          actions: [
            IconButton(
                tooltip: 'Шинэчлэх',
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh))
          ]),
      body: FutureBuilder<JsonRow>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return DiscoveryProblem(
                  error: snapshot.error!, retry: () => setState(_reload));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final entries = (data[{
                  'creator': 'creators',
                  'participant': 'participants',
                  'venue': 'places',
                  'content': 'posts'
                }[_kind]] as List? ??
                []);
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) const LinearProgressIndicator(),
              Text('Бодит оролцогчид',
                  style: Theme.of(context).textTheme.titleLarge),
              ListTile(
                  title: const Text('Creator · зорилт 10–15'),
                  trailing: Text('${data['creator_count']}')),
              ListTile(
                  title: const Text('Шалгасан газар · зорилт 20–30'),
                  trailing: Text('${data['venues']}')),
              ListTile(
                  title: const Text('Шалгасан контент · зорилт 60–100'),
                  trailing: Text('${data['content']}')),
              const Divider(),
              const ListTile(title: Text('Элссэнээс хойших үр дүн')),
              ListTile(
                  title: const Text('Эхний 24 цагт дагасан / газар хадгалсан'),
                  subtitle: Text(cohortPercent(data['activated'] as num,
                      data['activation_eligible'] as num))),
              ListTile(
                  title: const Text('Эхний 24 цагт хүн дагасан'),
                  subtitle: Text(cohortPercent(
                      data['first_day_followed'] as num,
                      data['activation_eligible'] as num))),
              ListTile(
                  title: const Text('Эхний 24 цагт газар хадгалсан'),
                  subtitle: Text(cohortPercent(data['first_day_saved'] as num,
                      data['activation_eligible'] as num))),
              ListTile(
                  title: const Text('7 дахь хоногт эргэн ирсэн'),
                  subtitle: Text(cohortPercent(
                      data['d7_returned'] as num, data['d7_eligible'] as num))),
              ListTile(
                  title: const Text('Өөр өдрүүдэд дахин нийтэлсэн creator'),
                  trailing: Text('${data['repeat_creators']}')),
              ListTile(
                  title: const Text('Чиглэл авалт · хүн/газар/өдрөөр'),
                  trailing: Text('${data['directions']}')),
              const Divider(),
              DropdownButtonFormField<String>(
                  initialValue: _kind,
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
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_kind == 'venue')
                        IconButton(
                            tooltip: 'Газрын мэдээлэл засах',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              await context.push(
                                  '/place-review/${Uri.encodeComponent(row['id'] as String)}');
                              if (mounted) setState(_reload);
                            }),
                      IconButton(
                          tooltip: 'Туршилтаас хасах',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed:
                              _busy ? null : () => _set('${row['id']}', false))
                    ])),
              const SizedBox(height: 12),
              TextField(
                  decoration: const InputDecoration(
                      labelText: 'Бүртгэлээс хайх',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) {
                    _query = v;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) {
                        setState(() => _candidates =
                            _service.pilotCandidates(_kind, _query));
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
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_kind == 'venue')
                                IconButton(
                                    tooltip: 'Мэдээлэл бэлтгэх',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      await context.push(
                                          '/place-review/${Uri.encodeComponent(row['id'] as String)}');
                                      if (mounted) setState(_reload);
                                    }),
                              IconButton(
                                  tooltip: 'Туршилтад оруулах',
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: _busy ||
                                          entries
                                              .any((e) => e['id'] == row['id'])
                                      ? null
                                      : () => _set('${row['id']}', true))
                            ]))
                    ]);
                  }),
            ]);
          }));
}
