import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/providers/event_provider.dart';
import '../../events/providers/featured_events_provider.dart';
import '../../events/widgets/events_rail.dart';
import '../providers/admin_console_provider.dart';
import '../services/admin_console_service.dart';

final _scopedSelectionsProvider =
    FutureProvider.autoDispose<List<FeaturedEventSelection>>((ref) async {
  final access = ref.watch(adminConsoleAccessProvider);
  if (access == null) return ref.watch(adminFeaturedEventsProvider.future);
  final rows = await access.service
      .callRpc(access.session, 'get_admin_featured_events', {});
  return (rows as List)
      .map((row) => FeaturedEventSelection(
          eventId: row['event_id'] as String,
          rank: (row['rank'] as num).toInt()))
      .toList();
}, dependencies: [adminConsoleAccessProvider, adminFeaturedEventsProvider]);

/// Only existing Night Owl administrators curate this public selection.
/// The server rechecks the role for every change, including deep links.
class AdminFeaturedEventsScreen extends ConsumerStatefulWidget {
  const AdminFeaturedEventsScreen({super.key});

  @override
  ConsumerState<AdminFeaturedEventsScreen> createState() =>
      _AdminFeaturedEventsState();
}

class _AdminFeaturedEventsState
    extends ConsumerState<AdminFeaturedEventsScreen> {
  String? _saving;
  String? _error;
  String get _owner => ref.read(sessionUserIdProvider) ?? '';

  void _refresh() {
    ref.invalidate(upcomingEventsProvider);
    ref.invalidate(adminFeaturedEventsProvider);
    ref.invalidate(_scopedSelectionsProvider);
    ref.invalidate(featuredEventsProvider);
  }

  Future<void> _setFeatured(String id, bool featured) async {
    final profile = ref.read(currentProfileProvider).asData?.value;
    final access = ref.read(adminConsoleAccessProvider);
    final owner = _owner;
    if (_saving != null ||
        (access != null
            ? !access.session.isCurrent
            : profile?.isAdmin != true || owner != profile?.id)) {
      return;
    }
    setState(() {
      _saving = id;
      _error = null;
    });
    try {
      if (access != null) {
        await access.service.callRpc(access.session, 'set_featured_event', {
          'p_event_id': id,
          'p_featured': featured,
          'p_rank': 0,
        });
      } else {
        await ref
            .read(eventFeatureServiceProvider)
            .setFeatured(id, featured: featured);
      }
      if (!mounted ||
          owner != _owner ||
          (access != null && !access.session.isCurrent)) {
        return;
      }
      ref.invalidate(adminFeaturedEventsProvider);
      ref.invalidate(_scopedSelectionsProvider);
      ref.invalidate(featuredEventsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              featured ? 'Онцгой эвентэд нэмлээ' : 'Онцгой эвентээс хаслаа')));
    } catch (error) {
      if (!mounted || owner != _owner) return;
      setState(() => _error = error is AdminConsoleFailure
          ? error.message
          : error is FeatureEventsUnavailableException
              ? 'Эвент сонгох үйлчилгээ хараахан бэлэн болоогүй байна.'
              : 'Өөрчлөлтийг хадгалж чадсангүй. Эрх болон холболтоо шалгаад дахин оролдоно уу.');
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final access = ref.watch(adminConsoleAccessProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final admin = access?.session.isCurrent == true ||
        profile.asData?.value?.isAdmin == true;
    return Scaffold(
        appBar: AppBar(
            title: const Text('Онцгой эвентүүд'),
            leading: IconButton(
                tooltip: 'Буцах',
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.explore),
                icon: const Icon(Icons.arrow_back_rounded)),
            actions: [
              if (admin)
                IconButton(
                    tooltip: 'Шинэчлэх',
                    onPressed: _saving == null ? _refresh : null,
                    icon: const Icon(Icons.refresh_rounded)),
            ]),
        body: access == null && profile.isLoading
            ? Center(
                child:
                    OwlLoading(message: 'Эрхийг шалгаж байна…', onDark: dark))
            : access == null && profile.hasError
                ? Center(
                    child: TextButton(
                        onPressed: () => ref.invalidate(currentProfileProvider),
                        child: const Text(
                            'Эрхийг шалгаж чадсангүй. Дахин оролдох')))
                : !admin
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Энэ хэсэг зөвхөн Night Owl-ийн админд нээлттэй.',
                                textAlign: TextAlign.center)))
                    : _content(context));
  }

  Widget _content(BuildContext context) {
    final candidates = ref.watch(upcomingEventsProvider);
    final selections = ref.watch(_scopedSelectionsProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if ((candidates.isLoading && !candidates.hasValue) ||
        (selections.isLoading && !selections.hasValue)) {
      return Center(
          child:
              OwlLoading(message: 'Эвентүүдийг ачаалж байна…', onDark: dark));
    }
    if (candidates.hasError || selections.hasError) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    selections.error is FeatureEventsUnavailableException
                        ? 'Эвент сонгох үйлчилгээ хараахан бэлэн болоогүй байна.'
                        : 'Эвентүүдийг ачаалж чадсангүй.',
                    textAlign: TextAlign.center),
                TextButton(
                    onPressed: _refresh, child: const Text('Дахин оролдох')),
              ])));
    }
    final events = candidates.requireValue;
    final selected =
        selections.requireValue.map((entry) => entry.eventId).toSet();
    final unseen = selected.difference(events.map((event) => event.id).toSet());
    final disabled =
        _saving != null || candidates.isLoading || selections.isLoading;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Night Owl-ийн багийн сонголт', style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
          'Онцолсон эвентүүд Газрууд хэсэгт бүх хэрэглэгчид харагдана. Дууссан эвентүүд автоматаар харагдахаа болино.'),
      const SizedBox(height: 16),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!,
                style: TextStyle(color: theme.colorScheme.error))),
      if (events.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text('Удахгүй болох эвент одоогоор алга.')),
      for (final event in events)
        Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                          '${event.venueName ?? "Газар тодорхойгүй"} · ${_date(event.startsAt)}',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        TextButton(
                            onPressed: () =>
                                showEventDetailSheet(context, event),
                            child: const Text('Дэлгэрэнгүй')),
                        FilledButton.tonalIcon(
                            key: ValueKey('feature-event-${event.id}'),
                            onPressed: disabled
                                ? null
                                : () => _setFeatured(
                                    event.id, !selected.contains(event.id)),
                            icon: Icon(selected.contains(event.id)
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded),
                            label: Text(_saving == event.id
                                ? 'Хадгалж байна…'
                                : selected.contains(event.id)
                                    ? 'Онцлохоос хасах'
                                    : 'Онцлох')),
                      ]),
                    ]))),
      if (unseen.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Өмнөх сонголтууд', style: theme.textTheme.titleMedium),
        const Text(
            'Жагсаалтад байхгүй өмнөх эвентүүдийн сонголтыг эндээс цэвэрлэж болно.'),
        for (final id in unseen)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Өмнө сонгосон эвент'),
              trailing: TextButton(
                  key: ValueKey('feature-event-$id'),
                  onPressed: disabled ? null : () => _setFeatured(id, false),
                  child: Text(
                      _saving == id ? 'Хадгалж байна…' : 'Сонголтоос хасах'))),
      ],
    ]);
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
