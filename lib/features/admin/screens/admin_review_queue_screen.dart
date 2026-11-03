import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/widgets/network_video.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/services/discovery_service.dart';
import '../providers/admin_console_provider.dart';
import '../services/admin_console_service.dart';
import '../widgets/admin_gate.dart';
import '../widgets/admin_widgets.dart';
import 'admin_records_screen.dart';

const _reviewKinds = {
  'all': 'Бүх төрөл',
  'post': 'Нийтлэл',
  'story': 'Story',
  'comment': 'Сэтгэгдэл',
  'event': 'Эвент',
  'review': 'Газрын үнэлгээ',
  'profile': 'Профайл',
  'note': 'Тэмдэглэл',
  'collection': 'Нийтийн цуглуулга',
  'venue': 'Газар',
};

/// One manual queue for text, photographs, and complete video review.
/// Private conversations are accessible only through a submitted report.
class AdminReviewQueueScreen extends ConsumerStatefulWidget {
  const AdminReviewQueueScreen({super.key});
  @override
  ConsumerState<AdminReviewQueueScreen> createState() =>
      _AdminReviewQueueState();
}

class _AdminReviewQueueState extends ConsumerState<AdminReviewQueueScreen> {
  String _kind = 'all', _status = 'pending';
  List<Map<String, dynamic>> _items = [];
  bool _loading = false, _busy = false, _more = false;
  int _generation = 0;
  AdminConsoleFailure? _error;
  late final StreamSubscription<AdminConsoleFailure> _invalidations;
  AdminConsoleAccess get _access => ref.read(adminConsoleAccessProvider)!;

  @override
  void initState() {
    super.initState();
    _invalidations = _access.session.invalidations.listen((failure) {
      if (!mounted) return;
      _generation++;
      setState(() {
        _items = [];
        _more = false;
        _loading = false;
        _error = failure;
      });
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_invalidations.cancel());
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy || (more && (_loading || !_more))) return;
    final access = _access;
    final generation = ++_generation;
    final offset = more ? _items.length : 0;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _items = [];
        _more = false;
      }
    });
    try {
      final page = await access.service.reviewQueue(access.session,
          kind: _kind, status: _status, offset: offset);
      if (!mounted || generation != _generation || !access.session.isCurrent) {
        return;
      }
      setState(() {
        _items = [..._items, ...page.items];
        _more = page.hasMore;
      });
    } catch (error) {
      if (!mounted || generation != _generation || !access.session.isCurrent) {
        return;
      }
      setState(() => _error = error is AdminConsoleFailure
          ? error
          : const AdminConsoleFailure('network'));
    } finally {
      if (mounted && generation == _generation && access.session.isCurrent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _decide(Map<String, dynamic> item, String decision) async {
    if (_busy || _loading) return;
    final access = _access;
    setState(() => _busy = true);
    final reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ReviewReasonDialog(
            access: access, approve: decision == 'approved'));
    if (!mounted || !access.session.isCurrent) return;
    if (reason == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      await access.service.review(access.session,
          item: item, decision: decision, reason: reason);
      if (!mounted || !access.session.isCurrent) return;
      ref.read(postsVersionProvider.notifier).state++;
      ref.read(socialVersionProvider.notifier).state++;
      ref.invalidate(currentProfileProvider);
      setState(() {
        _busy = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Шийдвэр болон аудитын баримтыг хадгаллаа.')));
      await _load();
    } catch (error) {
      if (!mounted || !access.session.isCurrent) return;
      setState(() {
        _busy = false;
        _error = error is AdminConsoleFailure
            ? error
            : const AdminConsoleFailure('action_uncertain');
      });
    }
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
        title: 'Нийтлэхийн өмнөх шалгалт',
        onRefresh: _loading || _busy ? null : () => _load(),
        child: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const AdminIntro(
                  title: 'Контентыг бүрэн шалгаарай',
                  subtitle:
                      'Бүх зураг, видеог бүтнээр нь үзэж, текст болон байршлыг шалгаад шийдвэр гаргана. '
                      'Хүлээгдэж буй контент бусдад харагдахгүй. Хувийн мессежийн түүх энэ жагсаалтад орохгүй.'),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                        initialValue: _kind,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Контентын төрөл'),
                        items: [
                          for (final entry in _reviewKinds.entries)
                            DropdownMenuItem(
                                value: entry.key, child: Text(entry.value))
                        ],
                        onChanged: _busy || _loading
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _kind = value);
                                  _load();
                                }
                              })),
                SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Шалгалтын төлөв'),
                        items: const [
                          DropdownMenuItem(
                              value: 'pending', child: Text('Хүлээгдэж буй')),
                          DropdownMenuItem(
                              value: 'approved', child: Text('Баталсан')),
                          DropdownMenuItem(
                              value: 'rejected', child: Text('Татгалзсан'))
                        ],
                        onChanged: _busy || _loading
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _status = value);
                                  _load();
                                }
                              })),
              ]),
              const SizedBox(height: 12),
              TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const AdminGate(
                                  child: AdminRecordsScreen(kind: 'post')))),
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Нийтлэл, сэтгэгдлийн бусад удирдлага')),
              if (_error != null)
                AdminMessage(
                    icon: Icons.error_outline,
                    title: 'Дахин шалгах шаардлагатай',
                    message: _error!.message,
                    onRetry: _loading || _busy ? null : () => _load()),
              if (_loading && _items.isEmpty) const AdminLoading(),
              if (!_loading && _error == null && _items.isEmpty)
                const AdminMessage(
                    icon: Icons.task_alt,
                    title: 'Энэ төлөвт контент алга',
                    message: 'Өөр төлөв сонгох эсвэл жагсаалтыг шинэчилнэ үү.'),
              for (final item in _items)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AdminCard(
                        key: ValueKey('review-${item['kind']}-${item['id']}'),
                        child: _record(item))),
              if (_more)
                OutlinedButton.icon(
                    onPressed:
                        _loading || _busy ? null : () => _load(more: true),
                    icon: const Icon(Icons.expand_more),
                    label: Text(_loading ? 'Уншиж байна…' : 'Цааш үзэх')),
              const SizedBox(height: 24),
            ])),
      );

  Widget _record(Map<String, dynamic> item) {
    final content = item['content'] as Map<String, dynamic>;
    final media = <String>{};
    for (final key in ['media_url', 'cover_url', 'avatar_url', 'music_url']) {
      final value = content[key];
      if (value is String && Uri.tryParse(value)?.scheme == 'https') {
        media.add(value);
      }
    }
    for (final key in ['media_urls', 'photos']) {
      final values = content[key];
      if (values is List) {
        media.addAll(values
            .whereType<String>()
            .where((value) => Uri.tryParse(value)?.scheme == 'https'));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_reviewKinds[item['kind']] ?? 'Контент',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 5),
      Text(
          'Илгээсэн: ${adminDate(item['submitted_at'] ?? item['created_at'])}'),
      const SizedBox(height: 12),
      SelectableText(const JsonEncoder.withIndent('  ').convert(content)),
      for (final url in media)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: url == content['music_url'] ||
                    isVideoUrl(url) ||
                    (content['media_type'] == 'video' &&
                        url == content['media_url'])
                ? NetworkVideo(
                    key: ValueKey('${item['review_version']}:$url'),
                    url: url,
                    height: url == content['music_url'] ? 96 : 250,
                    autoplay: false,
                    cover: false,
                    showControls: true)
                : AuthorizedImage(
                    imageUrl: url,
                    width: double.infinity,
                    height: 240,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) => const SizedBox(
                        height: 80,
                        child: Center(
                            child: Text(
                                'Медиа нээгдсэнгүй. Нээж үзтэл батлахгүй.'))))),
      const SizedBox(height: 12),
      SelectableText('ID: ${item['id']}'),
      if (item['status'] != 'rejected')
        Wrap(spacing: 10, runSpacing: 8, children: [
          if (item['status'] == 'pending')
            FilledButton.icon(
                onPressed:
                    _busy || _loading ? null : () => _decide(item, 'approved'),
                icon: const Icon(Icons.check),
                label: const Text('Шалгаад зөвшөөрөх')),
          OutlinedButton.icon(
              onPressed:
                  _busy || _loading ? null : () => _decide(item, 'rejected'),
              icon: const Icon(Icons.block),
              label: Text(item['status'] == 'approved'
                  ? 'Харагдахыг зогсоох'
                  : 'Татгалзах')),
        ]),
    ]);
  }
}

class _ReviewReasonDialog extends StatefulWidget {
  final AdminConsoleAccess access;
  final bool approve;
  const _ReviewReasonDialog({required this.access, required this.approve});
  @override
  State<_ReviewReasonDialog> createState() => _ReviewReasonState();
}

class _ReviewReasonState extends State<_ReviewReasonDialog> {
  final _reason = TextEditingController();
  bool _checked = false;
  late final StreamSubscription<AdminConsoleFailure> _invalidations;
  @override
  void initState() {
    super.initState();
    _invalidations = widget.access.session.invalidations.listen((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    unawaited(_invalidations.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(
            widget.approve ? 'Нийтлэхийг зөвшөөрөх' : 'Контентыг хязгаарлах'),
        content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _checked,
                  onChanged: (value) =>
                      setState(() => _checked = value ?? false),
                  title: const Text(
                      'Бүх текст, зураг, видеог бүрэн үзэж шалгасан.')),
              TextField(
                  controller: _reason,
                  maxLength: 1000,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Шалтгаан')),
              const Text('Хувийн мэдээлэл оруулахгүй. Аудитад хадгална.'),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Болих')),
          FilledButton(
              onPressed: _checked &&
                      _reason.text.trim().runes.length >= 3 &&
                      widget.access.session.isCurrent
                  ? () => Navigator.pop(context, _reason.text.trim())
                  : null,
              child: const Text('Баталгаажуулах'))
        ],
      );
}
