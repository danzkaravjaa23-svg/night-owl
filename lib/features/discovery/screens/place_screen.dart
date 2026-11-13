import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/network_video.dart';
import '../../../core/widgets/owl_loading.dart';
import '../services/discovery_service.dart';
import 'discovery_screen.dart';
import '../../profile/utils/app_links.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/providers/venue_bookmarks_provider.dart';
import '../../map/widgets/venue_operating_review.dart';

class PlaceScreen extends ConsumerStatefulWidget {
  final String venueRef;
  const PlaceScreen({super.key, required this.venueRef});
  @override
  ConsumerState<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends ConsumerState<PlaceScreen> {
  DiscoveryService get _service => ref.read(discoveryServiceProvider);
  late Future<(JsonRow?, List<JsonRow>)> _data;
  late (String?, String, int) _requestKey;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _requestKey = (
      ref.read(sessionUserIdProvider),
      widget.venueRef,
      ref.read(socialVersionProvider)
    );
    _data = () async {
      final result = await Future.wait<dynamic>([
        _service.venue(widget.venueRef),
        _service.venuePosts(widget.venueRef),
      ]);
      return (
        result[0] as JsonRow?,
        result[1] as List<JsonRow>,
      );
    }();
  }

  Future<void> _open(Uri uri, {bool directions = false}) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (directions) {
          unawaited(_service.activity('directions', target: widget.venueRef));
        }
      } else {
        throw StateError('open');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Холбоос нээж чадсангүй')));
      }
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(
        text:
            '${appOrigin()}/#/place/${Uri.encodeComponent(widget.venueRef)}'));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Холбоос хууллаа')));
    }
  }

  Future<void> _directions(JsonRow venue) => _open(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': venue['lat'] != null && venue['lng'] != null
            ? '${venue['lat']},${venue['lng']}'
            : '${venue['name']}, Улаанбаатар'
      }),
      directions: true);

  /// Saves or unsaves the place; [retry] re-reads a failed bookmark list.
  Future<void> _toggleSaved({required bool retry}) async {
    if (_service.me == null) {
      context.push(
          '/auth?next=${Uri.encodeComponent('/place/${widget.venueRef}')}');
      return;
    }
    if (retry) {
      ref.invalidate(venueBookmarksProvider);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(venueBookmarksProvider.notifier).toggle(widget.venueRef);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(discoveryError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestKey = (
      ref.watch(sessionUserIdProvider),
      widget.venueRef,
      ref.watch(socialVersionProvider)
    );
    if (requestKey != _requestKey) _reload();
    final bookmarks = ref.watch(venueBookmarksProvider);
    final saved = bookmarks.valueOrNull?.contains(widget.venueRef) ?? false;
    return Scaffold(
        appBar: AppHeader.title(
            title: 'Газрын мэдээлэл',
            compact: true,
            fallbackLocation: '/discovery',
            actions: [
              GlassIconButton(
                  icon: AppIcons.share,
                  tooltip: 'Холбоос хуулах',
                  onTap: _copyLink)
            ]),
        body: FutureBuilder<(JsonRow?, List<JsonRow>)>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return DiscoveryProblem(
                    error: snapshot.error!, retry: () => setState(_reload));
              }
              if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData) {
                return const Center(child: OwlLoading());
              }
              final (venue, posts) = snapshot.data!;
              if (venue == null) {
                return const EmptyState(
                    icon: AppIcons.venue, title: 'Газар олдсонгүй');
              }
              return RefreshIndicator(
                  onRefresh: () async {
                    if (_busy) return;
                    setState(_reload);
                    ref.invalidate(venueBookmarksProvider);
                    try {
                      await _data;
                    } catch (_) {
                      // FutureBuilder displays the error and its retry action.
                    }
                  },
                  child: ListView(
                      padding: const EdgeInsets.only(bottom: AppSpacing.x6),
                      children: [
                        if (venue['cover_url'] != null)
                          AspectRatio(
                              aspectRatio: 16 / 10,
                              child: AuthorizedImage(
                                  imageUrl: venue['cover_url'] as String,
                                  fit: BoxFit.cover)),
                        Padding(
                            padding: const EdgeInsets.all(AppSpacing.page),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(venue['name'] as String,
                                      style: AppTextStyles.h1),
                                  const SizedBox(height: AppSpacing.x2),
                                  Text(
                                      venue['address'] as String? ??
                                          'Хаяг нэмэгдээгүй',
                                      style: AppTextStyles.bodyMd.copyWith(
                                          color: AppColors.textSecondary)),
                                  if (venue['hours'] != null)
                                    ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.schedule),
                                        title: Text(venue['hours'] as String),
                                        subtitle: Text(venue['source_label'] ==
                                                'OpenStreetMap'
                                            ? 'OpenStreetMap-д бүртгэсэн цаг'
                                            : 'Бүртгэсэн ажиллах цаг')),
                                  const SizedBox(height: AppSpacing.x3),
                                  VenueOperatingReview(
                                    venueRefs: [
                                      widget.venueRef,
                                      if (venue['source_url'] is String)
                                        venue['source_url'] as String
                                    ],
                                  ),
                                  if (venue['price_min'] != null)
                                    ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading:
                                            const Icon(Icons.payments_outlined),
                                        title: Text(
                                            '${venue['price_min']}–${venue['price_max'] ?? venue['price_min']} ₮')),
                                  Wrap(
                                      spacing: AppSpacing.x2,
                                      runSpacing: AppSpacing.x2,
                                      children: [
                                        for (final vibe
                                            in (venue['vibes'] as List? ?? []))
                                          Chip(label: Text('$vibe'))
                                      ]),
                                  const SizedBox(height: AppSpacing.x4),
                                  Wrap(
                                      spacing: AppSpacing.x2,
                                      runSpacing: AppSpacing.x2,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        GradientButton(
                                            size: GradientButtonSize.md,
                                            fullWidth: false,
                                            icon: const Icon(
                                                Icons.directions_outlined),
                                            label: 'Чиглэл авах',
                                            onPressed: () =>
                                                _directions(venue)),
                                        OutlineButton(
                                            size: GradientButtonSize.md,
                                            fullWidth: false,
                                            icon: Icon(bookmarks.hasError
                                                ? Icons.refresh_rounded
                                                : saved
                                                    ? AppIcons.saveActive
                                                    : AppIcons.save),
                                            label: bookmarks.hasError
                                                ? 'Хадгалалтыг дахин шалгах'
                                                : saved
                                                    ? 'Хадгалсан'
                                                    : 'Хадгалах',
                                            onPressed: _busy ||
                                                    bookmarks.isLoading
                                                ? null
                                                : () => _toggleSaved(
                                                    retry: bookmarks.hasError)),
                                        if (venue['menu_url'] != null)
                                          OutlineButton(
                                              size: GradientButtonSize.md,
                                              fullWidth: false,
                                              icon: const Icon(
                                                  Icons.restaurant_menu),
                                              label: 'Меню',
                                              onPressed: () => _open(Uri.parse(
                                                  venue['menu_url']
                                                      as String))),
                                        if (venue['venue_id'] != null)
                                          TextButton(
                                              onPressed: () => context.push(
                                                  '/venue/reviews/${venue['venue_id']}'),
                                              child:
                                                  const Text('Үнэлгээ, эвент')),
                                      ]),
                                  if (venue['reviewed_at'] != null)
                                    ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                            Icons.fact_check_outlined),
                                        title: const Text(
                                            'Бүртгэлийн мэдээллийг хянасан'),
                                        subtitle: Text('${venue['reviewed_at']}'
                                            .split('T')
                                            .first)),
                                  if (venue['source_url'] != null)
                                    TextButton(
                                        onPressed: () => _open(Uri.parse(
                                            venue['source_url'] as String)),
                                        child: Text(
                                            '${venue['source_label'] ?? 'Мэдээллийн'} эх сурвалж')),
                                  if (venue['source_label'] == 'OpenStreetMap')
                                    TextButton(
                                        onPressed: () => _open(Uri.https(
                                            'www.openstreetmap.org',
                                            '/copyright')),
                                        child: const Text(
                                            '© OpenStreetMap contributors · ODbL')),
                                  const SizedBox(height: AppSpacing.page),
                                  Text('Эндээс хуваалцсан',
                                      style: AppTextStyles.title),
                                ])),
                        if (posts.isEmpty)
                          Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.page,
                                  0,
                                  AppSpacing.page,
                                  AppSpacing.page),
                              child: Text(
                                  'Энэ газартай холбоотой нийтлэл алга',
                                  style: AppTextStyles.bodyMd.copyWith(
                                      color: AppColors.textSecondary))),
                        for (final post in posts)
                          ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.page,
                                  vertical: AppSpacing.x1),
                              leading: DiscoveryThumbnail(
                                  imageUrl: post['media_url'] as String?,
                                  placeholder: Icons.image_outlined,
                                  builder: (url) => isVideoUrl(url)
                                      ? NetworkVideo(url: url, posterOnly: true)
                                      : AuthorizedImage(
                                          imageUrl: url, fit: BoxFit.cover)),
                              title: Text(post['caption'] as String? ?? '',
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '@${(post['profiles'] as Map?)?['username'] ?? ''}'),
                              onTap: () => context.push('/post/${post['id']}')),
                      ]));
            }));
  }
}
