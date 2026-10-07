import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/featured_events_provider.dart';
import 'events_rail.dart';

class FeaturedEventsSection extends ConsumerWidget {
  const FeaturedEventsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final state = ref.watch(featuredEventsProvider);
    final admin =
        ref.watch(currentProfileProvider).asData?.value?.isAdmin == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF9879EC)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Онцгой эвентүүд',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Night Owl-ийн багийн сонголт',
                      style: theme.textTheme.bodySmall),
                ])),
            if (admin)
              IconButton(
                  tooltip: 'Онцгой эвентүүд удирдах',
                  onPressed: () => context.push(AppRoutes.adminFeaturedEvents),
                  icon: const Icon(Icons.tune_rounded)),
          ])),
      if (state.isLoading && !state.hasValue)
        Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
                child: OwlLoading(
                    message: 'Онцгой эвентүүдийг хайж байна…', onDark: dark)))
      else if (state.hasError)
        _notice(context, 'Онцгой эвентүүдийг ачаалж чадсангүй.',
            action: TextButton.icon(
                onPressed: () => ref.invalidate(featuredEventsProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Дахин оролдох')))
      else if (state.valueOrNull?.isNotEmpty != true)
        _notice(context,
            'Шинэ сонголтууд удахгүй. Энд манай багийн онцолсон эвентүүд гарна.')
      else
        SizedBox(
            height: 200,
            child: ListView.separated(
                key: const PageStorageKey('featured-event-rail'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: state.requireValue.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, index) =>
                    EventPosterCard(event: state.requireValue[index]))),
      const SizedBox(height: 16),
    ]);
  }

  Widget _notice(BuildContext context, String text, {Widget? action}) =>
      Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x337654D6))),
          child: Column(children: [
            Row(children: [
              const NightOwlMark(size: 36),
              const SizedBox(width: 14),
              Expanded(
                  child: Text(text,
                      style: Theme.of(context).textTheme.bodyMedium)),
            ]),
            if (action != null) action,
          ]));
}
