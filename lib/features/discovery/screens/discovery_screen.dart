import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/constants/app_constants.dart';
import '../services/discovery_service.dart';

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
          appBar: const AppHeader.title(
              title: 'Нээх',
              compact: true,
              fallbackLocation: '/feed',
              bottom: TabBar(
                  tabs: [Tab(text: 'Хүмүүс'), Tab(text: 'Газрууд')])),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.x4, AppSpacing.page, AppSpacing.x3),
                child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                        labelText: 'Хүн, газар хайх',
                        prefixIcon: Icon(AppIcons.search)),
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
                        return const Center(child: OwlLoading());
                      }
                      return TabBarView(children: [
                        Column(children: [
                          Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.page),
                              child: DropdownButtonFormField<String>(
                                  initialValue: _interest,
                                  isExpanded: true,
                                  // Popup цэс шиг: bgElevated, 14 px булан.
                                  borderRadius: AppRadii.mdR,
                                  dropdownColor: AppColors.bgElevated,
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
                          const SizedBox(height: AppSpacing.x2),
                          Expanded(
                              child: snapshot.data![0].isEmpty
                                  ? const EmptyState(
                                      icon: Icons.person_search_outlined,
                                      title: 'Одоогоор илэрц алга')
                                  : ListView(children: [
                                      for (final row in snapshot.data![0])
                                        ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.page,
                                                    vertical: AppSpacing.x2),
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
                                            trailing:
                                                const Icon(AppIcons.forward),
                                            onTap: () => context.push('/creator/${row['id']}'))
                                    ]))
                        ]),
                        Column(children: [
                          SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.page),
                              title: const Text('Шалгасан газрууд'),
                              value: _reviewed,
                              onChanged: (v) => setState(() {
                                    _reviewed = v;
                                    _reload();
                                  })),
                          Expanded(
                              child: snapshot.data![1].isEmpty
                                  ? const EmptyState(
                                      icon: AppIcons.venue,
                                      title: 'Одоогоор илэрц алга')
                                  : ListView(children: [
                                      for (final row in snapshot.data![1])
                                        ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: AppSpacing.page,
                                                    vertical: AppSpacing.x2),
                                            leading: DiscoveryThumbnail(
                                                imageUrl:
                                                    row['cover_url'] as String?,
                                                placeholder:
                                                    AppIcons.venueType(
                                                        row['venue_type']
                                                            as String?)),
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
                                                const Icon(AppIcons.forward),
                                            onTap: () => context.push(
                                                '/place/${Uri.encodeComponent(row['ref'] as String)}'))
                                    ]))
                        ])
                      ]);
                    }))
          ])));
}

/// Square list thumbnail (64 px, `AppRadii.md`) for discovery rows: the
/// image when there is one, otherwise [placeholder] on the surface colour.
class DiscoveryThumbnail extends StatelessWidget {
  final String? imageUrl;
  final IconData placeholder;
  final Widget Function(String url)? builder;
  const DiscoveryThumbnail(
      {super.key, this.imageUrl, required this.placeholder, this.builder});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ClipRRect(
        borderRadius: AppRadii.mdR,
        child: SizedBox(
            width: 64,
            height: 64,
            child: url == null
                ? ColoredBox(
                    color: AppColors.bgSurface,
                    child: Icon(placeholder, color: AppColors.textSecondary))
                : builder?.call(url) ??
                    AuthorizedImage(imageUrl: url, fit: BoxFit.cover)));
  }
}

/// Failed load with a retry, shared by the discovery screens: the app's owl
/// error state (same as feed, messages and profile).
class DiscoveryProblem extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const DiscoveryProblem({super.key, required this.error, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: OwlLoading(
              size: 48,
              state: OwlLoadingState.error,
              message: discoveryError(error),
              onRetry: retry)));
}
