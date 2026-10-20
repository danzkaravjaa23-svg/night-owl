import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/constants/app_constants.dart';
import '../services/discovery_service.dart';
import '../widgets/discovery_back_button.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _service = DiscoveryService();
  final _query = TextEditingController();
  Timer? _debounce;
  String? _interest;
  bool _reviewed = true;
  late Future<List<List<JsonRow>>> _data;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = Future.wait([
      _service.creators(interest: _interest, query: _query.text),
      _service.catalog(query: _query.text, reviewed: _reviewed)
    ]);
  }

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Scaffold(
          appBar: AppBar(
              leading: const DiscoveryBackButton(fallback: '/feed'),
              title: const Text('Нээх'),
              bottom: const TabBar(
                  tabs: [Tab(text: 'Хүмүүс'), Tab(text: 'Газрууд')])),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                        labelText: 'Хүн, газар хайх',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        if (mounted) setState(_reload);
                      });
                    })),
            Expanded(
                child: FutureBuilder<List<List<JsonRow>>>(
                    future: _data,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return DiscoveryProblem(
                            error: snapshot.error!,
                            retry: () => setState(_reload));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return TabBarView(children: [
                        Column(children: [
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: DropdownButtonFormField<String>(
                                  initialValue: _interest,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Сонирхол'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: null,
                                        child: Text('Бүх сонирхол')),
                                    for (final interest
                                        in AppConstants.interestOptions)
                                      DropdownMenuItem(
                                          value: interest,
                                          child: Text(interest))
                                  ],
                                  onChanged: (v) => setState(() {
                                        _interest = v;
                                        _reload();
                                      }))),
                          Expanded(
                              child: snapshot.data![0].isEmpty
                                  ? const Center(
                                      child: Text('Одоогоор илэрц алга'))
                                  : ListView(children: [
                                      for (final row in snapshot.data![0])
                                        ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10),
                                            leading: AppAvatar(
                                                imageUrl: row['avatar_url']
                                                    as String?,
                                                initial: (row['username']
                                                                as String? ??
                                                            '')
                                                        .isEmpty
                                                    ? '?'
                                                    : (row['username'] as String)
                                                        .characters
                                                        .first,
                                                size: 52),
                                            title: Text(row['full_name']
                                                    as String? ??
                                                row['username'] as String? ??
                                                'Хэрэглэгч'),
                                            subtitle: Text(
                                                '@${row['username'] ?? ''}\n${row['bio'] ?? ''}',
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis),
                                            trailing: const Icon(Icons.chevron_right),
                                            onTap: () => context.push('/creator/${row['id']}'))
                                    ]))
                        ]),
                        Column(children: [
                          SwitchListTile(
                              title: const Text('Шалгасан газрууд'),
                              value: _reviewed,
                              onChanged: (v) => setState(() {
                                    _reviewed = v;
                                    _reload();
                                  })),
                          Expanded(
                              child: snapshot.data![1].isEmpty
                                  ? const Center(
                                      child: Text('Одоогоор илэрц алга'))
                                  : ListView(children: [
                                      for (final row in snapshot.data![1])
                                        ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8),
                                            leading: SizedBox(
                                                width: 64,
                                                height: 64,
                                                child: row['cover_url'] == null
                                                    ? const Icon(Icons
                                                        .storefront_outlined)
                                                    : AuthorizedImage(
                                                        imageUrl:
                                                            row['cover_url']
                                                                as String,
                                                        fit: BoxFit.cover)),
                                            title: Text(row['name'] as String),
                                            subtitle: Text(
                                                [
                                                  row['address'],
                                                  if (row['price_min'] != null)
                                                    '${row['price_min']}–${row['price_max'] ?? row['price_min']} ₮'
                                                ]
                                                    .whereType<String>()
                                                    .join('\n'),
                                                maxLines: 3,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                            trailing:
                                                const Icon(Icons.chevron_right),
                                            onTap: () => context.push(
                                                '/place/${Uri.encodeComponent(row['ref'] as String)}'))
                                    ]))
                        ])
                      ]);
                    }))
          ])));
}

class DiscoveryProblem extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const DiscoveryProblem({super.key, required this.error, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(discoveryError(error), textAlign: TextAlign.center),
            TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Дахин оролдох'))
          ])));
}
