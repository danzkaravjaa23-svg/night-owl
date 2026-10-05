import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/venue.dart';
import '../../auth/providers/auth_provider.dart';

class _BusinessData {
  final List<Venue> venues;
  final int posts, events, checkins;
  const _BusinessData(this.venues, this.posts, this.events, this.checkins);
}
final _businessDataProvider = FutureProvider<_BusinessData>((ref) async {
  final me = ref.watch(sessionUserIdProvider);
  if (me == null) return const _BusinessData([], 0, 0, 0);
  final client = SupabaseService.client;
  final rows = await client.from('venues').select().eq('owner_id', me).order('name');
  final venues = rows.map((row) => Venue.fromJson(row)).where((v) => !v.isDemo).toList();
  final counts = await Future.wait<int>([
    client.from('posts').count(CountOption.exact).eq('user_id', me),
    client.from('events').count(CountOption.exact).eq('organizer_id', me)
      .gte('starts_at', DateTime.now().toUtc().toIso8601String()),
    venues.isEmpty ? Future.value(0) : client.from('checkins').count(CountOption.exact)
      .inFilter('venue_id', venues.map((v) => v.id).toList())
      .gt('expires_at', DateTime.now().toUtc().toIso8601String()),
  ]);
  return _BusinessData(venues, counts[0], counts[1], counts[2]);
});

class BusinessScreen extends ConsumerStatefulWidget {
  const BusinessScreen({super.key});
  @override
  ConsumerState<BusinessScreen> createState() => _BusinessScreenState();
}
class _BusinessScreenState extends ConsumerState<BusinessScreen> {
  bool _busy = false;
  Future<void> _becomeBusiness() async {
    if (_busy) return;
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client.from('profiles').update({'is_business': true})
        .eq('id', me).select('id').single();
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Идэвхжүүлж чадсангүй. Дахин оролдоно уу'))); }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _editVenue([String? id]) async {
    await context.push(Uri(path: AppRoutes.venueEdit, queryParameters: id == null ? null : {'id': id}).toString());
    if (mounted) ref.invalidate(_businessDataProvider);
  }
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    return Scaffold(backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('Бизнес самбар'), leading: IconButton(
        tooltip: 'Буцах', icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.profile))),
      body: ref.watch(_businessDataProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: TextButton(onPressed: () => ref.invalidate(_businessDataProvider),
          child: const Text('Мэдээлэл ачаалсангүй · Дахин оролдох'))),
        data: (data) => RefreshIndicator(onRefresh: () => ref.refresh(_businessDataProvider.future),
          child: ListView(physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20), children: [
              Text('Таны газрууд. Таны үйл явдал.', style: AppTextStyles.h2),
              const SizedBox(height: 12),
              Text('Өөрийн газрын мэдээлэл, зураг, ажиллах цаг болон эвентээ нэг дор удирдаарай.',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              if (profile.hasValue && profile.value != null && !profile.value!.isBusiness)
                FilledButton.icon(onPressed: _busy ? null : _becomeBusiness,
                  icon: const Icon(Icons.business_center_outlined), label: Text(_busy ? 'Түр хүлээнэ үү' : 'Бизнес хаяг идэвхжүүлэх')),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _stat('Газрууд', data.venues.length), _stat('Пост', data.posts),
                _stat('Удахгүй болох эвент', data.events), _stat('Идэвхтэй check-in', data.checkins),
              ]),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: () async {
                await context.push(AppRoutes.createEvent);
                if (mounted) ref.invalidate(_businessDataProvider);
              }, icon: const Icon(Icons.event_outlined), label: const Text('Эвент нэмэх')),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => _editVenue(),
                icon: const Icon(Icons.storefront_outlined), label: Text(data.venues.isEmpty ? 'Газраа бүртгэх' : 'Газрын мэдээлэл засах')),
              const SizedBox(height: 24),
              for (final venue in data.venues) Card(child: ListTile(
                leading: Text(venue.emoji, style: const TextStyle(fontSize: 26)),
                title: Text(venue.name), subtitle: Text(venue.hasLocation
                  ? venue.district ?? venue.typeLabel : 'Байршлаа бүртгэнэ үү'),
                trailing: const Icon(Icons.edit_outlined), onTap: () => _editVenue(venue.id))),
            ]))),
    );
  }
  Widget _stat(String label, int value) => Container(width: 170, padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.hairline)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$value', style: AppTextStyles.h1), const SizedBox(height: 6),
      Text(label, style: AppTextStyles.bodySm),
    ]));
}
