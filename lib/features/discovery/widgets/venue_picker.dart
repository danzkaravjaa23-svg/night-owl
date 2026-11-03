import 'dart:async';
import 'package:flutter/material.dart';
import '../services/discovery_service.dart';

typedef VenueCatalogLoader = Future<List<JsonRow>> Function({
  required String query,
  required int offset,
  required int limit,
});

Future<JsonRow?> pickDiscoveryVenue(
  BuildContext context, {
  String? selectedRef,
  String title = 'Газар сонгох',
  String? helperText,
  VenueCatalogLoader? loader,
}) =>
    showModalBottomSheet<JsonRow>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DiscoveryVenuePicker(
            selectedRef: selectedRef,
            title: title,
            helperText: helperText,
            loader: loader));

/// Only server catalog rows may be attached to content. Bundled map records
/// alone do not establish a valid venue_ref foreign key.
class DiscoveryVenuePicker extends StatefulWidget {
  final String? selectedRef;
  final String title;
  final String? helperText;
  final VenueCatalogLoader? loader;
  const DiscoveryVenuePicker({
    super.key,
    this.selectedRef,
    this.title = 'Газар сонгох',
    this.helperText,
    this.loader,
  });
  @override
  State<DiscoveryVenuePicker> createState() => _DiscoveryVenuePickerState();
}

class _DiscoveryVenuePickerState extends State<DiscoveryVenuePicker> {
  static const _pageSize = 60;
  final _searchController = TextEditingController();
  final _rows = <JsonRow>[];
  Timer? _timer;
  String _query = '';
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadPage(sequence: ++_requestId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPage({int? sequence, bool more = false}) async {
    if (more && _loadingMore) return;
    final request = sequence ?? ++_requestId;
    final query = _query;
    final offset = more ? _nextOffset : 0;
    if (sequence == null) {
      setState(() {
        _error = null;
        _loading = !more;
        _loadingMore = more;
      });
    }
    try {
      final loader = widget.loader ??
          ({required String query, required int offset, required int limit}) =>
              DiscoveryService()
                  .catalog(query: query, offset: offset, limit: limit);
      final page = await loader(query: query, offset: offset, limit: _pageSize)
          .timeout(const Duration(seconds: 15));
      if (!mounted || request != _requestId) return;
      setState(() {
        if (!more) _rows.clear();
        final seen = _rows.map((row) => row['ref']).toSet();
        for (final row in page) {
          final ref = row['ref'];
          final name = row['name'];
          if (ref is String &&
              ref.trim().isNotEmpty &&
              name is String &&
              name.trim().isNotEmpty &&
              seen.add(ref)) {
            _rows.add(row);
          }
        }
        _nextOffset = offset + page.length;
        _hasMore = page.length == _pageSize;
        _error = null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _search(String query) {
    _timer?.cancel();
    final sequence = ++_requestId;
    // Hide old choices immediately, including during the debounce. An older
    // request must never replace the current search or be selectable as it runs.
    setState(() {
      _query = query.trim();
      _rows.clear();
      _error = null;
      _loading = true;
      _loadingMore = false;
      _hasMore = false;
      _nextOffset = 0;
    });
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadPage(sequence: sequence);
    });
  }

  Widget _retry({bool more = false}) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(discoveryError(_error!), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        TextButton.icon(
            onPressed: () => _loadPage(more: more),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Дахин оролдох')),
      ]));

  Widget _results() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      if (_error != null) return Center(child: _retry());
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Газар олдсонгүй. Өөр нэрээр хайгаарай.',
                  textAlign: TextAlign.center)));
    }
    return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: _rows.length + (_hasMore || _error != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _rows.length) {
            if (_error != null) return _retry(more: true);
            return Padding(
                padding: const EdgeInsets.all(12),
                child: _loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : TextButton.icon(
                        onPressed: () => _loadPage(more: true),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Илүү олон газар')));
          }
          final row = _rows[index];
          final selected = row['ref'] == widget.selectedRef;
          final address = (row['address'] as String?)?.trim();
          final description = address?.isNotEmpty == true
              ? address!
              : (row['district'] as String?)?.trim() ??
                  (row['venue_type'] as String?)?.trim() ??
                  '';
          return ListTile(
              selected: selected,
              leading: Icon(selected
                  ? Icons.check_circle_rounded
                  : Icons.location_on_outlined),
              title: Text(row['name'] as String,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: !selected && description.isEmpty
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          if (selected)
                            const Text('Сонгосон',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          if (description.isNotEmpty)
                            Text(description,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
              onTap: () => Navigator.pop(context, row));
        });
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(children: [
            ListTile(
                title: Text(widget.title),
                trailing: IconButton(
                    tooltip: 'Хаах',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context))),
            if (widget.helperText != null &&
                MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(widget.helperText!,
                      style: Theme.of(context).textTheme.bodySmall)),
            Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                    controller: _searchController,
                    onChanged: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                        labelText: 'Газар хайх',
                        hintText: 'Газрын нэрээр хайх',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Хайлтыг цэвэрлэх',
                                onPressed: () {
                                  _searchController.clear();
                                  _search('');
                                },
                                icon: const Icon(Icons.close_rounded))))),
            Expanded(child: _results()),
          ])));
}
