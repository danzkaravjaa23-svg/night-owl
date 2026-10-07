import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/providers/event_provider.dart';
import '../../events/providers/featured_events_provider.dart';
import '../../events/widgets/events_rail.dart';

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
    ref.invalidate(featuredEventsProvider);
  }

  Future<void> _setFeatured(String id, bool featured) async {
    final profile = ref.read(currentProfileProvider).asData?.value;
    final owner = _owner;
    if (_saving != null || profile?.isAdmin != true || owner != profile?.id) {
      return;
    }
    setState(() {
      _saving = id;
      _error = null;
    });
    try {
      await ref
          .read(eventFeatureServiceProvider)
          .setFeatured(id, featured: featured);
      ref.invalidate(adminFeaturedEventsProvider);
      ref.invalidate(featuredEventsProvider);
      if (!mounted || owner != _owner) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              featured ? 'Онцгой эвентэд нэмлээ' : 'Онцгой эвентээс хаслаа')));
    } catch (error) {
      if (!mounted || owner != _owner) return;
      setState(() => _error = error is FeatureEventsUnavailableException
          ? 'Эвент сонгох үйлчилгээ хараахан бэлэн болоогүй байна.'
          : 'Өөрчлөлтийг хадгалж чадсангүй. Эрх болон холболтоо шалгаад дахин оролдоно уу.');
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final admin = profile.asData?.value?.isAdmin == true;
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
        body: profile.isLoading
            ? Center(
                child:
                    OwlLoading(message: 'Эрхийг шалгаж байна…', onDark: dark))
            : profile.hasError
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
    final selections = ref.watch(adminFeaturedEventsProvider);
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
