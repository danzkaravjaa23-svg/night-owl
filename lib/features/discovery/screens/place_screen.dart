import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/authorized_media.dart';
import '../../../core/widgets/network_video.dart';
import '../services/discovery_service.dart';
import '../widgets/discovery_back_button.dart';
import 'discovery_screen.dart';
import '../../profile/utils/app_links.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/providers/venue_bookmarks_provider.dart';

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
        appBar: AppBar(
            leading: const DiscoveryBackButton(),
            title: const Text('Газрын мэдээлэл'),
            actions: [
              IconButton(
                  tooltip: 'Холбоос хуулах',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(
                        text:
                            '${appOrigin()}/#/place/${Uri.encodeComponent(widget.venueRef)}'));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Холбоос хууллаа')));
                    }
                  })
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
                return const Center(child: CircularProgressIndicator());
              }
              final (venue, posts) = snapshot.data!;
              if (venue == null) {
                return const Center(child: Text('Газар олдсонгүй'));
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
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (venue['cover_url'] != null)
                          AspectRatio(
                              aspectRatio: 16 / 10,
                              child: AuthorizedImage(
                                  imageUrl: venue['cover_url'] as String,
                                  fit: BoxFit.cover)),
                        Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(venue['name'] as String,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  const SizedBox(height: 8),
                                  Text(venue['address'] as String? ??
                                      'Хаяг нэмэгдээгүй'),
                                  if (venue['hours'] != null)
                                    ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.schedule),
                                        title: Text(venue['hours'] as String)),
                                  if (venue['price_min'] != null)
                                    ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading:
                                            const Icon(Icons.payments_outlined),
                                        title: Text(
                                            '${venue['price_min']}–${venue['price_max'] ?? venue['price_min']} ₮')),
                                  Wrap(spacing: 8, children: [
                                    for (final vibe
                                        in (venue['vibes'] as List? ?? []))
                                      Chip(label: Text('$vibe'))
                                  ]),
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 10, runSpacing: 10, children: [
                                    FilledButton.icon(
                                        icon: const Icon(
                                            Icons.directions_outlined),
                                        label: const Text('Чиглэл авах'),
                                        onPressed: () => _open(
                                            Uri.https('www.google.com',
                                                '/maps/dir/', {
                                              'api': '1',
                                              'destination': venue['lat'] !=
                                                          null &&
                                                      venue['lng'] != null
                                                  ? '${venue['lat']},${venue['lng']}'
                                                  : '${venue['name']}, Улаанбаатар'
                                            }),
                                            directions: true)),
                                    OutlinedButton.icon(
                                        icon: Icon(bookmarks.hasError
                                            ? Icons.refresh
                                            : saved
                                                ? Icons.bookmark
                                                : Icons.bookmark_border),
                                        label: Text(bookmarks.hasError
                                            ? 'Хадгалалтыг дахин шалгах'
                                            : saved
                                                ? 'Хадгалсан'
                                                : 'Хадгалах'),
                                        onPressed: _busy || bookmarks.isLoading
                                            ? null
                                            : () async {
                                                if (_service.me == null) {
                                                  context.push(
                                                      '/auth?next=${Uri.encodeComponent('/place/${widget.venueRef}')}');
                                                  return;
                                                }
                                                if (bookmarks.hasError) {
                                                  ref.invalidate(
                                                      venueBookmarksProvider);
                                                  return;
                                                }
                                                setState(() => _busy = true);
                                                try {
                                                  await ref
                                                      .read(
                                                          venueBookmarksProvider
                                                              .notifier)
                                                      .toggle(widget.venueRef);
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(SnackBar(
                                                            content: Text(
                                                                discoveryError(
                                                                    e))));
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(
                                                        () => _busy = false);
                                                  }
                                                }
                                              }),
                                    if (venue['menu_url'] != null)
                                      OutlinedButton.icon(
                                          icon:
                                              const Icon(Icons.restaurant_menu),
                                          label: const Text('Меню'),
                                          onPressed: () => _open(Uri.parse(
                                              venue['menu_url'] as String))),
                                    if (venue['venue_id'] != null)
                                      TextButton(
                                          onPressed: () => context.push(
                                              '/venue/reviews/${venue['venue_id']}'),
                                          child: const Text('Үнэлгээ, эвент')),
                                  ]),
                                  if (venue['reviewed_at'] != null)
                                    ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                            Icons.fact_check_outlined),
                                        title: const Text('Night Owl шалгасан'),
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
                                  const SizedBox(height: 20),
                                  Text('Эндээс хуваалцсан',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                ])),
                        if (posts.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(20),
                              child:
                                  Text('Энэ газартай холбоотой нийтлэл алга')),
                        for (final post in posts)
                          ListTile(
                              leading: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: post['media_url'] == null
                                      ? const Icon(Icons.image_outlined)
                                      : isVideoUrl(post['media_url'] as String)
                                          ? NetworkVideo(
                                              url: post['media_url'] as String,
                                              posterOnly: true)
                                          : AuthorizedImage(
                                              imageUrl:
                                                  post['media_url'] as String,
                                              fit: BoxFit.cover)),
                              title: Text(post['caption'] as String? ?? '',
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '@${(post['profiles'] as Map?)?['username'] ?? ''}'),
                              onTap: () => context.push('/post/${post['id']}')),
                      ]));
            }));
  }
}
