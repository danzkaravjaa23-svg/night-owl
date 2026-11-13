import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/widgets/settings_rows.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/providers/event_provider.dart';
import '../../events/providers/featured_events_provider.dart';
import '../../events/widgets/events_rail.dart';
import '../providers/admin_console_provider.dart';
import '../services/admin_console_service.dart';
import '../widgets/admin_widgets.dart';

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
        backgroundColor: AppColors.bgBase,
        appBar: AppHeader.title(
            title: 'Онцгой эвентүүд',
            compact: true,
            fallbackLocation: AppRoutes.explore,
            actions: [
              if (admin)
                GlassIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Шинэчлэх',
                    onTap: _saving == null ? _refresh : null),
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
                    ? const EmptyState(
                        icon: Icons.lock_outline_rounded,
                        title:
                            'Энэ хэсэг зөвхөн Night Owl-ийн админд нээлттэй.')
                    : _content(context));
  }

  Widget _content(BuildContext context) {
    final candidates = ref.watch(upcomingEventsProvider);
    final selections = ref.watch(_scopedSelectionsProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    if ((candidates.isLoading && !candidates.hasValue) ||
        (selections.isLoading && !selections.hasValue)) {
      return Center(
          child:
              OwlLoading(message: 'Эвентүүдийг ачаалж байна…', onDark: dark));
    }
    if (candidates.hasError || selections.hasError) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x6),
              child: OwlLoading(
                  state: OwlLoadingState.error,
                  onDark: dark,
                  message: selections.error
                          is FeatureEventsUnavailableException
                      ? 'Эвент сонгох үйлчилгээ хараахан бэлэн болоогүй байна.'
                      : 'Эвентүүдийг ачаалж чадсангүй.',
                  onRetry: _refresh)));
    }
    final events = candidates.requireValue;
    final selected =
        selections.requireValue.map((entry) => entry.eventId).toSet();
    final unseen = selected.difference(events.map((event) => event.id).toSet());
    final disabled =
        _saving != null || candidates.isLoading || selections.isLoading;
    return ListView(padding: const EdgeInsets.all(AppSpacing.page), children: [
      const AdminIntro(
          title: 'Night Owl-ийн багийн сонголт',
          subtitle:
              'Онцолсон эвентүүд Газрууд хэсэгт бүх хэрэглэгчид харагдана. Дууссан эвентүүд автоматаар харагдахаа болино.'),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x3),
            child: Text(_error!,
                style: AppTextStyles.bodySm.copyWith(color: AppColors.danger))),
      if (events.isEmpty)
        const EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'Удахгүй болох эвент одоогоор алга.'),
      for (final event in events)
        Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x3),
            child: Card(
                child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title, style: AppTextStyles.title),
                          const SizedBox(height: 6),
                          Text(
                              '${event.venueName ?? "Газар тодорхойгүй"} · ${_date(event.startsAt)}',
                              style: AppTextStyles.caption),
                          const SizedBox(height: AppSpacing.x3),
                          Wrap(
                              spacing: AppSpacing.x2,
                              runSpacing: AppSpacing.x2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton(
                                    onPressed: () =>
                                        showEventDetailSheet(context, event),
                                    child: const Text('Дэлгэрэнгүй')),
                                _featureButton(event.id,
                                    featured: selected.contains(event.id),
                                    disabled: disabled),
                              ]),
                        ])))),
      if (unseen.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.x4),
        const SettingsSectionLabel('Өмнөх сонголтууд'),
        const SizedBox(height: AppSpacing.x1),
        Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
                'Жагсаалтад байхгүй өмнөх эвентүүдийн сонголтыг эндээс цэвэрлэж болно.',
                style: AppTextStyles.caption)),
        const SizedBox(height: AppSpacing.x3),
        SettingsCard(children: [
          for (final id in unseen) ...[
            if (id != unseen.first) const SettingsDivider(),
            // The text button gets its own line: as a row trailing it never
            // wraps, so large text pushed the title to zero width.
            const SettingsRow(
                icon: Icons.event_outlined, title: 'Өмнө сонгосон эвент'),
            Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                    key: ValueKey('feature-event-$id'),
                    onPressed: disabled ? null : () => _setFeatured(id, false),
                    child: Text(_saving == id
                        ? 'Хадгалж байна…'
                        : 'Сонголтоос хасах'))),
          ],
        ]),
      ],
    ]);
  }

  /// Row action of an event card (DS-03, sm pill with a 44 px target):
  /// "Онцлох" is the card's primary action; "Онцлохоос хасах" on an already
  /// featured event is secondary.
  Widget _featureButton(String id,
      {required bool featured, required bool disabled}) {
    final key = ValueKey('feature-event-$id');
    final saving = _saving == id;
    final VoidCallback? onPressed =
        disabled ? null : () => _setFeatured(id, !featured);
    if (featured) {
      return OutlineButton(
          key: key,
          size: GradientButtonSize.sm,
          fullWidth: false,
          icon: const Icon(Icons.star_rounded),
          label: saving ? 'Хадгалж байна…' : 'Онцлохоос хасах',
          onPressed: onPressed);
    }
    return GradientButton(
        key: key,
        size: GradientButtonSize.sm,
        fullWidth: false,
        icon: const Icon(Icons.star_outline_rounded),
        label: saving ? 'Хадгалж байна…' : 'Онцлох',
        busy: saving,
        onPressed: onPressed);
  }

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
