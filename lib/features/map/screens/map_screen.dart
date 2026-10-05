import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../models/venue.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/venue_provider.dart';
import '../services/location_service.dart';
import '../widgets/google_map_view.dart';
import '../widgets/map_controller.dart';

/// Bookmarks belong to this device and account. No server table is assumed.
class VenueBookmarksNotifier extends StateNotifier<AsyncValue<Set<String>>> {
  final String? userId;
  late final Future<void> ready;
  bool _saving = false;
  VenueBookmarksNotifier(this.userId) : super(const AsyncValue.loading()) {
    ready = _load();
  }
  String get storageKey => 'venue_bookmarks.${userId ?? 'guest'}';
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(storageKey) ?? <String>[];
      if (mounted) state = AsyncValue.data(ids.toSet());
    } catch (error, stack) {
      if (mounted) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> toggle(String venueId) async {
    await ready;
    if (!mounted) return;
    if (!state.hasValue) {
      await _load();
      if (!mounted) return;
      if (!state.hasValue) {
        throw StateError('Stored venue bookmarks could not be read');
      }
    }
    if (_saving) throw StateError('A venue save is already in progress');
    _saving = true;
    try {
      final next = {...?state.valueOrNull};
      if (!next.remove(venueId)) next.add(venueId);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(storageKey, next.toList()..sort())) {
        throw StateError('Venue bookmark was not saved');
      }
      if (mounted) state = AsyncValue.data(next);
    } finally {
      _saving = false;
    }
  }
}

final venueBookmarksProvider = StateNotifierProvider.autoDispose<
    VenueBookmarksNotifier, AsyncValue<Set<String>>>((ref) {
  return VenueBookmarksNotifier(ref.watch(sessionUserIdProvider));
});
final _venueDescriptionProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, id) async {
  final row = await SupabaseService.client
      .from('venues')
      .select('description')
      .eq('id', id)
      .maybeSingle();
  final description = row?['description']?.toString().trim();
  return description == null || description.isEmpty ? null : description;
});

class MapScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const MapScreen({super.key, this.embedded = false});
  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _navy = Color(0xFF0B0D17),
      _light = Color(0xFFF5F5FC),
      _muted = Color(0xFF8993AE),
      _violet = Color(0xFF7654D6),
      _sheet = Color(0xFFF3F1FB),
      _ink = Color(0xFF19172B);
  final _map = LeafletMapController();
  final _search = TextEditingController();
  String _query = '';
  String? _type;
  String? _selectedId;
  bool _dismissedSelection = false, _showList = false, _onlySaved = false;
  LatLng? _myLocation;
  bool _locating = false, _saving = false;
  static const _categories = {
    null: 'Бүгд',
    'bars': 'Бар',
    'nightclub': 'Клуб',
    'jazz': 'Live Music',
    'restaurant': 'Хоол',
    'karaoke': 'Караоке'
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesType(Venue venue) =>
      _type == null ||
      (_type == 'bars'
          ? const {'bar', 'pub', 'lounge', 'rooftop'}.contains(venue.type)
          : venue.type == _type);
  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await LocationService.current();
      if (!mounted) return;
      setState(
          () => _myLocation = LatLng(position.latitude, position.longitude));
      _map.center(position.latitude, position.longitude);
    } on LocationFailure catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Байршил авч чадсангүй. Дахин оролдоно уу.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        _message('Холбоос нээж чадсангүй. Дахин оролдоно уу.');
      }
    } catch (_) {
      if (mounted) _message('Холбоос нээж чадсангүй.');
    }
  }

  Future<void> _directions(Venue venue) async {
    if (!venue.hasLocation) return;
    await _openExternal(Uri.https('www.google.com', '/maps/dir/',
        {'api': '1', 'destination': '${venue.lat},${venue.lng}'}));
  }

  Future<void> _save(Venue venue) async {
    if (_saving) return;
    final notifier = ref.read(venueBookmarksProvider.notifier);
    final owner = notifier.userId;
    setState(() => _saving = true);
    try {
      await notifier.toggle(venue.id);
      if (!mounted || ref.read(sessionUserIdProvider) != owner) return;
      final saved =
          ref.read(venueBookmarksProvider).valueOrNull?.contains(venue.id) ??
              false;
      _message(
          saved ? 'Энэ төхөөрөмж дээр хадгаллаа' : 'Хадгалсан газраас хаслаа');
    } catch (_) {
      if (mounted) _message('Газар хадгалж чадсангүй. Дахин оролдоно уу.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _select(Venue venue) {
    if (!venue.hasLocation) {
      context.push('/venue/reviews/${Uri.encodeComponent(venue.id)}');
      return;
    }
    setState(() {
      _showList = false;
      _selectedId = venue.id;
      _dismissedSelection = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _map.center(venue.lat!, venue.lng!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(venuesProvider);
    final bookmarks =
        ref.watch(venueBookmarksProvider).valueOrNull ?? <String>{};
    final all = state.valueOrNull ?? <Venue>[];
    final query = _query.trim().toLowerCase();
    final filtered = all
        .where((venue) =>
            _matchesType(venue) &&
            (!_onlySaved || bookmarks.contains(venue.id)) &&
            (query.isEmpty ||
                '${venue.name} ${venue.district ?? ''} ${venue.address ?? ''}'
                    .toLowerCase()
                    .contains(query)))
        .toList();
    final located = filtered.where((venue) => venue.hasLocation).toList();
    final selected =
        located.where((venue) => venue.id == _selectedId).firstOrNull ??
            (!_dismissedSelection ? located.firstOrNull : null);
    return Scaffold(
        backgroundColor: _navy,
        body: SafeArea(
            bottom: !widget.embedded,
            child: Column(children: [
              _header(),
              _searchField(),
              _filters(),
              Expanded(
                  child: _showList
                      ? _venueList(filtered, state, bookmarks)
                      : LayoutBuilder(builder: (context, constraints) {
                          final cardHeight =
                              math.min(280.0, constraints.maxHeight * .68);
                          final attributionGap = 12 +
                              MediaQuery.textScalerOf(context).scale(10) * 1.4;
                          return Stack(children: [
                            Positioned.fill(
                                child: GoogleMapView(
                                    lat: AppConstants.ubLat,
                                    lng: AppConstants.ubLng,
                                    zoom: 14,
                                    controller: _map,
                                    selectedId: selected?.id,
                                    userLocation: _myLocation,
                                    bottomInset: selected == null
                                        ? 0
                                        : cardHeight + attributionGap,
                                    markersJson: jsonEncode([
                                      for (final venue in located)
                                        {
                                          'id': venue.id,
                                          'name': venue.name,
                                          'lat': venue.lat,
                                          'lng': venue.lng,
                                          'type': venue.type
                                        }
                                    ]),
                                    onVenueTap: (id) {
                                      final venue = located
                                          .where((venue) => venue.id == id)
                                          .firstOrNull;
                                      if (venue != null) _select(venue);
                                    })),
                            if (state.isLoading && !state.hasValue)
                              const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFB6A4FF))),
                            if (state.hasError && !state.hasValue)
                              Positioned(
                                  left: 16,
                                  right: 74,
                                  top: 16,
                                  child: _notice('Газрууд ачаалж чадсангүй.',
                                      retry: true)),
                            if (state.hasValue && located.isEmpty)
                              Positioned(
                                  left: 16,
                                  right: 74,
                                  top: 16,
                                  child: _notice(
                                      filtered.isEmpty
                                          ? 'Хайлтад тохирох газар алга.'
                                          : 'Эдгээр газрын байршил хараахан бүртгэгдээгүй.',
                                      showList: filtered.isNotEmpty)),
                            Positioned(
                                right: 16,
                                bottom: selected == null
                                    ? 48
                                    : cardHeight + attributionGap + 8,
                                child: _locationButton()),
                            if (selected != null)
                              Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: attributionGap,
                                  child: _detail(selected, cardHeight,
                                      bookmarks.contains(selected.id))),
                          ]);
                        })),
            ])));
  }

  Widget _header() => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (!widget.embedded)
            IconButton(
                tooltip: 'Буцах',
                color: _light,
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.explore),
                icon: const Icon(Icons.arrow_back_rounded)),
          const Expanded(
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: NightOwlBrand(size: 28, onDark: true)))),
          IconButton(
              tooltip: _showList
                  ? 'Газрын зураг харах'
                  : 'Бүх газрыг жагсаалтаар харах',
              color: _muted,
              onPressed: () => setState(() => _showList = !_showList),
              icon: Icon(_showList
                  ? Icons.map_outlined
                  : Icons.format_list_bulleted_rounded)),
        ]),
        const SizedBox(height: 8),
        Text('Explore',
            style: AppTextStyles.h1.copyWith(color: _light, fontSize: 28)),
        const SizedBox(height: 4),
        Text('Өнөө орой шинэ газруудыг нээ.',
            style: AppTextStyles.bodySm.copyWith(color: _muted)),
      ]));
  Widget _searchField() => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
          controller: _search,
          onChanged: (value) => setState(() {
                _query = value;
                _selectedId = null;
                _dismissedSelection = false;
              }),
          style: AppTextStyles.bodyMd.copyWith(color: _light),
          cursorColor: const Color(0xFFB6A4FF),
          decoration: InputDecoration(
            hintText: 'Газар, дүүрэг, хаяг хайх…',
            hintStyle: AppTextStyles.bodyMd.copyWith(color: _muted),
            prefixIcon:
                const Icon(Icons.search_rounded, color: _muted, size: 22),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Хайлт цэвэрлэх',
                    icon: const Icon(Icons.close, color: _muted, size: 18),
                    onPressed: () {
                      _search.clear();
                      setState(() {
                        _query = '';
                        _selectedId = null;
                        _dismissedSelection = false;
                      });
                    }),
            filled: true,
            fillColor: const Color(0xFF202433),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: const BorderSide(color: Color(0xFFB6A4FF))),
          )));
  Widget _filters() => SizedBox(
      height: 52,
      child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
          children: [
            for (final entry in _categories.entries)
              Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _pill(
                      entry.value,
                      _type == entry.key,
                      () => setState(() {
                            _type = entry.key;
                            _selectedId = null;
                            _dismissedSelection = false;
                          }))),
            _pill(
                'Хадгалсан',
                _onlySaved,
                () => setState(() {
                      _onlySaved = !_onlySaved;
                      _selectedId = null;
                      _dismissedSelection = false;
                    }),
                icon: Icons.bookmark_border_rounded),
          ]));
  Widget _pill(String label, bool selected, VoidCallback onTap,
          {IconData? icon}) =>
      Material(
          color: selected ? _violet : _navy,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                  color: selected ? _violet : const Color(0xFF272C40))),
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: selected ? _light : _muted),
                      const SizedBox(width: 5)
                    ],
                    Text(label,
                        style: AppTextStyles.bodySm
                            .copyWith(color: selected ? _light : _muted)),
                  ]))));
  Widget _locationButton() => Material(
      color: const Color(0xFF161B2B),
      shape: const CircleBorder(),
      elevation: 4,
      child: IconButton(
          tooltip: 'Миний байршил',
          onPressed: _locating ? null : _locate,
          color: const Color(0xFFB6A4FF),
          icon: _locating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFB6A4FF)))
              : const Icon(Icons.my_location_rounded, size: 22)));
  Widget _notice(String message, {bool retry = false, bool showList = false}) =>
      Material(
          color: const Color(0xFF161B2B),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(message,
                    style: AppTextStyles.bodySm.copyWith(color: _light)),
                if (retry)
                  TextButton(
                      onPressed: () => ref.invalidate(venuesProvider),
                      child: const Text('Дахин оролдох')),
                if (showList)
                  TextButton(
                      onPressed: () => setState(() => _showList = true),
                      child: const Text('Жагсаалт харах')),
              ])));
  Widget _venueList(List<Venue> venues, AsyncValue<List<Venue>> state,
      Set<String> bookmarks) {
    if (state.isLoading && !state.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.hasError && !state.hasValue) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: _notice('Газрууд ачаалж чадсангүй.', retry: true)));
    }
    return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(venuesProvider);
          await ref.read(venuesProvider.future);
        },
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text('${venues.length} газар',
                  style: AppTextStyles.h3.copyWith(color: _light)),
              const SizedBox(height: 6),
              Text('Байршил нэмэгдээгүй газрууд энд мөн харагдана.',
                  style: AppTextStyles.bodyXs.copyWith(color: _muted)),
              const SizedBox(height: 16),
              if (venues.isEmpty) _notice('Хайлтад тохирох газар алга.'),
              for (final venue in venues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                      color: const Color(0xFF121625),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                          onTap: () => _select(venue),
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                _photo(venue, 60),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(venue.name,
                                          style: AppTextStyles.h3
                                              .copyWith(color: _light),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(venue.typeLabel,
                                          style: AppTextStyles.bodySm
                                              .copyWith(color: _muted)),
                                      if (!venue.hasLocation)
                                        Text('Байршил нэмэгдээгүй',
                                            style: AppTextStyles.bodyXs
                                                .copyWith(color: _muted)),
                                    ])),
                                IconButton(
                                    tooltip: bookmarks.contains(venue.id)
                                        ? 'Хадгалсан газраас хасах'
                                        : 'Газар хадгалах',
                                    onPressed:
                                        _saving ? null : () => _save(venue),
                                    icon: Icon(
                                        bookmarks.contains(venue.id)
                                            ? Icons.bookmark_rounded
                                            : Icons.bookmark_border_rounded,
                                        color: const Color(0xFFB6A4FF),
                                        size: 22)),
                              ])))),
                ),
            ]));
  }

  Widget _photo(Venue venue, double size) {
    final url = venue.coverUrl?.trim().isNotEmpty == true
        ? venue.coverUrl!
        : venue.photos.where((photo) => photo.trim().isNotEmpty).firstOrNull;
    Widget fallback() => Container(
        color: const Color(0xFF191B30),
        alignment: Alignment.center,
        child: NightOwlMark(size: size * .55));
    return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
            width: size,
            height: size,
            child: url == null
                ? fallback()
                : Image.network(url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => fallback())));
  }

  Widget _detail(Venue venue, double height, bool saved) {
    final description = ref.watch(_venueDescriptionProvider(venue.id));
    final text = description.valueOrNull ??
        venue.address ??
        (description.isLoading
            ? 'Мэдээлэл ачаалж байна…'
            : 'Тайлбар хараахан нэмэгдээгүй.');
    return Material(
        color: _sheet,
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFC5C3D9),
                                  borderRadius: BorderRadius.circular(8)))),
                      const SizedBox(height: 10),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                                onTap: () => context.push(
                                    '/venue/reviews/${Uri.encodeComponent(venue.id)}'),
                                child: _photo(venue, 72)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: GestureDetector(
                                                onTap: () => context.push(
                                                    '/venue/reviews/${Uri.encodeComponent(venue.id)}'),
                                                child: Text(venue.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: AppTextStyles.h3
                                                        .copyWith(
                                                            color: _ink,
                                                            fontSize: 18,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)))),
                                        IconButton(
                                            tooltip: 'Сонголт хаах',
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                                minWidth: 36, minHeight: 36),
                                            padding: EdgeInsets.zero,
                                            onPressed: () => setState(() {
                                                  _selectedId = null;
                                                  _dismissedSelection = true;
                                                }),
                                            icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                                color: Color(0xFF68677F))),
                                      ]),
                                  Text(
                                      [
                                        venue.typeLabel,
                                        if (venue.district?.trim().isNotEmpty ==
                                            true)
                                          venue.district!
                                      ].join(' · '),
                                      style: AppTextStyles.bodySm.copyWith(
                                          color: const Color(0xFF68677F))),
                                  const SizedBox(height: 4),
                                  Wrap(
                                      spacing: 5,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        if (venue.rating.isFinite &&
                                            venue.rating > 0 &&
                                            venue.rating <= 5) ...[
                                          const Icon(Icons.star_rounded,
                                              size: 16, color: _ink),
                                          Text(venue.rating.toStringAsFixed(1),
                                              style: AppTextStyles.bodySm
                                                  .copyWith(color: _ink)),
                                        ] else
                                          Text('Үнэлгээ хараахан алга',
                                              style: AppTextStyles.bodyXs
                                                  .copyWith(
                                                      color: const Color(
                                                          0xFF68677F))),
                                        if (venue.verified)
                                          const Icon(Icons.verified_rounded,
                                              size: 16, color: _violet),
                                      ]),
                                ])),
                          ]),
                      const SizedBox(height: 12),
                      Text(text,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySm
                              .copyWith(color: _ink, height: 1.4)),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                            child: FilledButton(
                                onPressed: () => _directions(venue),
                                style: FilledButton.styleFrom(
                                    backgroundColor: _violet,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 48),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(28))),
                                child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.directions_outlined, size: 20),
                                      SizedBox(width: 8),
                                      Flexible(
                                          child: Text('Чиглэл авах',
                                              overflow: TextOverflow.ellipsis)),
                                    ]))),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                            tooltip: saved
                                ? 'Хадгалсан газраас хасах'
                                : 'Газар хадгалах',
                            onPressed: _saving ? null : () => _save(venue),
                            style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFE5E3F0),
                                foregroundColor: saved ? _violet : _ink,
                                minimumSize: const Size(48, 48)),
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Icon(
                                    saved
                                        ? Icons.bookmark_rounded
                                        : Icons.bookmark_border_rounded,
                                    size: 23)),
                      ]),
                      if (venue.locationSourceUrl != null)
                        TextButton.icon(
                            onPressed: () => _openExternal(
                                Uri.parse(venue.locationSourceUrl!)),
                            style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6550AD),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact),
                            icon:
                                const Icon(Icons.open_in_new_rounded, size: 13),
                            label: const Text('Байршлын эх сурвалж'))
                      else
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                                'Байршил баталгаажаагүй · очихын өмнө шалгаарай',
                                style: AppTextStyles.bodyXs
                                    .copyWith(color: const Color(0xFF68677F)))),
                    ]))));
  }
}
