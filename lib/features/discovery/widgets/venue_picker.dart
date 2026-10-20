import 'dart:async';
import 'package:flutter/material.dart';
import '../services/discovery_service.dart';

Future<JsonRow?> pickDiscoveryVenue(BuildContext context) =>
    showModalBottomSheet<JsonRow>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const DiscoveryVenuePicker());

class DiscoveryVenuePicker extends StatefulWidget {
  const DiscoveryVenuePicker({super.key});
  @override
  State<DiscoveryVenuePicker> createState() => _DiscoveryVenuePickerState();
}

class _DiscoveryVenuePickerState extends State<DiscoveryVenuePicker> {
  Future<List<JsonRow>>? _results;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _results = DiscoveryService().catalog();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _results = DiscoveryService().catalog(query: q));
      }
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(children: [
        ListTile(
            title: const Text('Газар сонгох'),
            trailing: IconButton(
                tooltip: 'Хаах',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context))),
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                onChanged: _search,
                decoration: const InputDecoration(
                    labelText: 'Газар хайх', prefixIcon: Icon(Icons.search)))),
        Expanded(
            child: FutureBuilder<List<JsonRow>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(discoveryError(snapshot.error!)));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Center(child: Text('Газар олдсонгүй'));
                  }
                  return ListView(children: [
                    for (final row in snapshot.data!)
                      ListTile(
                          title: Text(row['name'] as String),
                          subtitle: Text(row['address'] as String? ??
                              row['venue_type'] as String? ??
                              ''),
                          onTap: () => Navigator.pop(context, row))
                  ]);
                }))
      ]));
}
