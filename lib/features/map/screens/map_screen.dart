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
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/night_owl_brand.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/premium_surface.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/owl_loading.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../models/venue.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/venue_provider.dart';
import '../services/location_service.dart';
import '../widgets/google_map_view.dart';
import '../widgets/map_controller.dart';
import '../widgets/venue_information_sheet.dart';

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
  static const _light = Color(0xFFF5F5FC), _violet = Color(0xFF7654D6);
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _background => _dark ? AppColors.bgBaseDark : AppColors.bgBaseLight;
  Color get _foreground =>
      _dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
  Color get _muted =>
      _dark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
  Color get _surface =>
      _dark ? AppColors.bgElevatedDark : AppColors.bgElevatedLight;
  Color get _control => _dark ? const Color(0xFF161B2B) : Colors.white;
  Color get _accent => _dark ? AppColors.neonCyanDark : AppColors.neonCyanLight;
  Color get _line => _dark ? const Color(0xFF272C40) : const Color(0xFFD8D4E8);
  final _map = LeafletMapController();
  final _search = TextEditingController();
  String _query = '';
  String? _type;
  String? _selectedId;
  String? _expandedVenueId;
  bool _dismissedSelection = false, _showList = false, _onlySaved = false;
  LatLng? _myLocation;
  bool _locating = false, _saving = false;
  static const _categories = {
    null: 'Бүгд',
    'bars': 'Бар',
    'nightclub': 'Клуб',
    'jazz': 'Live Music',
    'restaurant': 'Хоол',
    'cafe': 'Кафе',
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

  void _select(Venue venue, {bool fromMap = false}) {
    if (ref.read(venuesProvider).hasError ||
        ref.read(venueCatalogStatusProvider).notice != null) {
      _showInformation(venue);
      return;
    }
    if (!venue.hasLocation) {
      _openVenue(venue);
      return;
    }
    setState(() {
      _showList = false;
      if (_selectedId != venue.id) _expandedVenueId = null;
      _selectedId = venue.id;
      _dismissedSelection = false;
    });
    // A pin tap should keep the street and zoom the person is exploring.
    // Only a selection from the list needs to move the map to that venue.
    if (!fromMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.center(venue.lat!, venue.lng!);
      });
    }
  }

  void _openVenue(Venue venue) {
    if (venue.communityEnabled) {
      context.push('/venue/reviews/${Uri.encodeComponent(venue.id)}');
      return;
    }
    _showInformation(venue);
  }

  void _showInformation(Venue venue) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      sheetAnimationStyle: AppMotion.reduced(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppMotion.enter, reverseDuration: AppMotion.exit),
      backgroundColor: _background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: VenueInformationSheet(venue: venue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(venuesProvider);
    final catalogStatus = ref.watch(venueCatalogStatusProvider);
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
    final selected = state.hasError || catalogStatus.notice != null
        ? null
        : located.where((venue) => venue.id == _selectedId).firstOrNull ??
            (!_dismissedSelection ? located.firstOrNull : null);
    return Scaffold(
        backgroundColor: _background,
        body: SafeArea(
            bottom: !widget.embedded,
            child: Column(children: [
              _header(),
              _searchField(),
              _filters(),
              Expanded(
                  child: Stack(fit: StackFit.expand, children: [
                // Retain tiles and camera while browsing the list. Offstage
                // stops painting and TickerMode pauses hidden animations.
                Offstage(
                  offstage: _showList,
                  child: TickerMode(
                    enabled: !_showList,
                    child: RepaintBoundary(
                      child: LayoutBuilder(builder: (context, constraints) {
                        final expanded =
                            selected != null && _expandedVenueId == selected.id;
                        final textGrowth = math.max(0.0,
                            MediaQuery.textScalerOf(context).scale(13) - 13);
                        // Leave streets visible; large text can scroll within
                        // either card without moving or rebuilding the map.
                        final cardHeight = math.min(
                            expanded ? 420.0 : 232.0 + textGrowth * 7,
                            constraints.maxHeight * (expanded ? .82 : .62));
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
                                    if (venue != null) {
                                      _select(venue, fromMap: true);
                                    }
                                  })),
                          if (state.isLoading && !state.hasValue)
                            Center(
                                child: OwlLoading(
                                    message:
                                        'Танд тохирох газруудыг хайж байна…',
                                    onDark: _dark)),
                          if (catalogStatus.notice != null &&
                              !state.hasError &&
                              state.hasValue &&
                              located.isNotEmpty)
                            Positioned(
                              left: 16,
                              right: 16,
                              top: 12,
                              child: _notice(catalogStatus.notice!,
                                  retry: true,
                                  maxHeight:
                                      math.max(0, constraints.maxHeight - 24)),
                            ),
                          if (state.hasError)
                            Positioned(
                                left: 16,
                                right: 74,
                                top: 16,
                                child: _notice(
                                    state.hasValue
                                        ? 'Шинэчилж чадсангүй. Өмнө ачаалсан газруудыг харуулж байна.'
                                        : 'Газрууд ачаалж чадсангүй.',
                                    retry: true,
                                    maxHeight: math.max(
                                        0, constraints.maxHeight - 32))),
                          if (state.hasValue && located.isEmpty)
                            Positioned(
                                left: 16,
                                right: 74,
                                top: 16,
                                child: _notice(
                                    filtered.isEmpty
                                        ? 'Хайлтад тохирох газар алга.'
                                        : 'Эдгээр газрын байршил хараахан бүртгэгдээгүй.',
                                    showList: filtered.isNotEmpty,
                                    maxHeight: math.max(
                                        0, constraints.maxHeight - 32))),
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
                                child: AppEntrance(
                                    key: ValueKey(selected.id),
                                    child: _detail(selected, cardHeight,
                                        bookmarks.contains(selected.id)))),
                        ]);
                      }),
                    ),
                  ),
                ),
                if (_showList) _venueList(filtered, state, bookmarks),
              ])),
            ])));
  }

  Widget _header() => NightOwlAtmosphere(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (!widget.embedded)
                IconButton(
                    tooltip: 'Буцах',
                    color: _foreground,
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.explore),
                    icon: SculptedIcon(Icons.arrow_back_rounded,
                        color: _foreground, onDark: _dark)),
              Expanded(
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: NightOwlBrand(size: 28, onDark: _dark)))),
              IconButton(
                  tooltip: _showList
                      ? 'Газрын зураг харах'
                      : 'Бүх газрыг жагсаалтаар харах',
                  color: _muted,
                  onPressed: () => setState(() => _showList = !_showList),
                  icon: SculptedIcon(
                      _showList
                          ? Icons.map_outlined
                          : Icons.format_list_bulleted_rounded,
                      color: _muted,
                      onDark: _dark)),
            ]),
            const SizedBox(height: 8),
            Text('Өнөө орой',
                style: AppTextStyles.h1.copyWith(
                    color: _foreground,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8)),
            const SizedBox(height: 4),
            Text('Өнөө орой шинэ газруудыг нээ.',
                style: AppTextStyles.bodySm.copyWith(color: _muted)),
          ])));
  Widget _searchField() => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
          controller: _search,
          onChanged: (value) => setState(() {
                _query = value;
                _selectedId = null;
                _expandedVenueId = null;
                _dismissedSelection = false;
              }),
          style: AppTextStyles.bodyMd.copyWith(color: _foreground),
          cursorColor: _accent,
          decoration: InputDecoration(
            hintText: 'Газар, дүүрэг, хаяг хайх…',
            hintStyle: AppTextStyles.bodyMd.copyWith(color: _muted),
            prefixIcon: SculptedIcon(Icons.search_rounded,
                color: _muted, size: 22, onDark: _dark),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Хайлт цэвэрлэх',
                    icon: SculptedIcon(Icons.close,
                        color: _muted, size: 18, onDark: _dark),
                    onPressed: () {
                      _search.clear();
                      setState(() {
                        _query = '';
                        _selectedId = null;
                        _expandedVenueId = null;
                        _dismissedSelection = false;
                      });
                    }),
            filled: true,
            fillColor: _dark ? const Color(0xFF1E1C32) : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: _line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: _line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: _accent)),
          )));
  Widget _filters() => SizedBox(
      height:
          math.max(52, MediaQuery.textScalerOf(context).scale(14) * 1.4 + 26),
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
                            _expandedVenueId = null;
                            _dismissedSelection = false;
                          }))),
            _pill(
                'Хадгалсан',
                _onlySaved,
                () => setState(() {
                      _onlySaved = !_onlySaved;
                      _selectedId = null;
                      _expandedVenueId = null;
                      _dismissedSelection = false;
                    }),
                icon: Icons.bookmark_border_rounded),
          ]));
  Widget _pill(String label, bool selected, VoidCallback onTap,
          {IconData? icon}) =>
      PressFeedback(
          child: AnimatedContainer(
              duration: AppMotion.duration(context, AppMotion.release),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: selected
                        ? const [Color(0xFF9879EC), _violet, Color(0xFF5838A3)]
                        : [_surface, _background]),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: selected
                        ? AppColors.silverNeon.withValues(alpha: .5)
                        : _line),
                boxShadow: selected
                    ? [
                        BoxShadow(
                            color: _violet.withValues(alpha: .22),
                            blurRadius: 12,
                            offset: const Offset(0, 3))
                      ]
                    : [],
              ),
              child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 7),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (icon != null) ...[
                              SculptedIcon(icon,
                                  size: 16,
                                  color: selected ? _light : _muted,
                                  onDark: selected || _dark),
                              const SizedBox(width: 5)
                            ],
                            Text(label,
                                style: AppTextStyles.bodySm.copyWith(
                                    color: selected ? _light : _muted)),
                          ]))))));
  Widget _locationButton() => Material(
      color: _control,
      shape: const CircleBorder(),
      elevation: 4,
      child: IconButton(
          tooltip: 'Миний байршил',
          onPressed: _locating ? null : _locate,
          color: _accent,
          icon: _locating
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: OwlLoading(size: 20, compact: true, onDark: _dark))
              : SculptedIcon(Icons.my_location_rounded,
                  size: 22, color: _accent, active: true, onDark: _dark)));
  Widget _notice(String message,
      {bool retry = false, bool showList = false, double? maxHeight}) {
    final text = Row(children: [
      if (retry) ...[
        const OwlEmotion(mood: OwlMood.patient, size: 32),
        const SizedBox(width: 10),
      ],
      Expanded(
          child: Text(message,
              style: AppTextStyles.bodySm.copyWith(color: _foreground))),
    ]);
    return Material(
        color: _control,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: maxHeight ?? double.infinity),
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (maxHeight != null)
                    Flexible(child: SingleChildScrollView(child: text))
                  else
                    text,
                  if (retry)
                    TextButton(
                        onPressed: ref.read(venuesProvider).isLoading
                            ? null
                            : () => ref.read(refreshVenueCatalogProvider)(),
                        child: const Text('Дахин оролдох')),
                  if (showList)
                    TextButton(
                        onPressed: () => setState(() => _showList = true),
                        child: const Text('Жагсаалт харах')),
                ]))));
  }

  Widget _venueList(List<Venue> venues, AsyncValue<List<Venue>> state,
      Set<String> bookmarks) {
    if (state.isLoading && !state.hasValue) {
      return Center(
          child: OwlLoading(
              message: 'Газрын мэдээлэл уншиж байна…', onDark: _dark));
    }
    if (state.hasError && !state.hasValue) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: _notice('Газрууд ачаалж чадсангүй.', retry: true)));
    }
    return RefreshIndicator(
        onRefresh: () async {
          ref.read(refreshVenueCatalogProvider)();
          try {
            await ref.read(venuesProvider.future);
          } catch (_) {
            // The retained rows and explicit refresh error remain visible.
          }
        },
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text('${venues.length} газар',
                  style: AppTextStyles.h3.copyWith(color: _foreground)),
              const SizedBox(height: 6),
              if (state.hasError)
                _notice(
                    'Шинэчилж чадсангүй. Өмнө ачаалсан газруудыг харуулж байна.',
                    retry: true)
              else if (ref.watch(venueCatalogStatusProvider).notice != null)
                _notice(ref.watch(venueCatalogStatusProvider).notice!,
                    retry: true),
              Text('Танд таалагдсан газраа хадгалаад, мэдээллийг нь нээгээрэй.',
                  style: AppTextStyles.bodyXs.copyWith(color: _muted)),
              const SizedBox(height: 16),
              if (venues.isEmpty) _notice('Хайлтад тохирох газар алга.'),
              for (final venue in venues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                      color: _surface,
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
                                              .copyWith(color: _foreground),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(venue.typeLabel,
                                          style: AppTextStyles.bodySm
                                              .copyWith(color: _muted)),
                                      if (venue.sourceLabel != null)
                                        Text(venue.sourceLabel!,
                                            style: AppTextStyles.bodyXs
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
                                    icon: SculptedIcon(
                                        bookmarks.contains(venue.id)
                                            ? Icons.bookmark_rounded
                                            : Icons.bookmark_border_rounded,
                                        color: _accent,
                                        active: bookmarks.contains(venue.id),
                                        onDark: _dark,
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
        color: _dark ? const Color(0xFF191B30) : const Color(0xFFE8E4F4),
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
    final expanded = _expandedVenueId == venue.id;
    final description = expanded && venue.communityEnabled
        ? ref.watch(_venueDescriptionProvider(venue.id))
        : const AsyncValue<String?>.data(null);
    final text = description.valueOrNull ??
        venue.address ??
        (description.isLoading
            ? 'Мэдээлэл ачаалж байна…'
            : 'Тайлбар хараахан нэмэгдээгүй.');
    final secondary =
        _dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final source = venueWebsiteUrl(venue.sourceUrl ?? venue.locationSourceUrl);
    final website = venueWebsiteUrl(venue.websiteUrl);
    final card = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _dark
                  ? const [Color(0xFF201E35), Color(0xFF111522)]
                  : const [Colors.white, Color(0xFFF4F1FA)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: _dark ? .24 : .08),
                blurRadius: 22,
                offset: const Offset(0, 8))
          ],
        ),
        child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
                key: const ValueKey('selected-venue-card'),
                constraints: BoxConstraints(maxHeight: height),
                child: SingleChildScrollView(
                    key: ValueKey('${venue.id}:$expanded'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: InkWell(
                                        onTap: () => _openVenue(venue),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              _photo(venue, 48),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(venue.name,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: AppTextStyles.h3
                                                            .copyWith(
                                                                color:
                                                                    _foreground,
                                                                fontSize: 17,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                        [
                                                          venue.typeLabel,
                                                          if (venue.district
                                                                  ?.trim()
                                                                  .isNotEmpty ==
                                                              true)
                                                            venue.district!
                                                        ].join(' · '),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: AppTextStyles
                                                            .bodySm
                                                            .copyWith(
                                                                color:
                                                                    secondary)),
                                                    const SizedBox(height: 3),
                                                    Wrap(
                                                        spacing: 4,
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        children: [
                                                          if (venue.rating
                                                                  .isFinite &&
                                                              venue.rating >
                                                                  0 &&
                                                              venue.rating <=
                                                                  5) ...[
                                                            Icon(
                                                                Icons
                                                                    .star_rounded,
                                                                size: 15,
                                                                color: _accent),
                                                            Text(
                                                                venue.rating
                                                                    .toStringAsFixed(
                                                                        1),
                                                                style: AppTextStyles
                                                                    .bodySm
                                                                    .copyWith(
                                                                        color:
                                                                            _foreground)),
                                                          ] else
                                                            Text(
                                                                venue.communityEnabled
                                                                    ? 'Үнэлгээ хараахан алга'
                                                                    : 'Газрын мэдээлэл',
                                                                style: AppTextStyles
                                                                    .bodyXs
                                                                    .copyWith(
                                                                        color:
                                                                            secondary)),
                                                          if (venue.verified)
                                                            Icon(
                                                                Icons
                                                                    .verified_rounded,
                                                                size: 16,
                                                                color: _accent),
                                                        ]),
                                                  ])),
                                            ]))),
                                IconButton(
                                    tooltip: 'Сонголт хаах',
                                    constraints: const BoxConstraints(
                                        minWidth: 44, minHeight: 44),
                                    padding: EdgeInsets.zero,
                                    onPressed: () => setState(() {
                                          _selectedId = null;
                                          _expandedVenueId = null;
                                          _dismissedSelection = true;
                                        }),
                                    icon: Icon(Icons.close_rounded,
                                        size: 19, color: secondary)),
                              ]),
                          const SizedBox(height: 9),
                          Text(
                              source == null
                                  ? 'Байршил баталгаажаагүй · очихын өмнө шалгаарай'
                                  : 'Байршлын эх сурвалжтай · очихын өмнө шалгаарай',
                              style: AppTextStyles.bodyXs
                                  .copyWith(color: secondary, height: 1.4)),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                                child: GradientButton(
                                    label: 'Чиглэл авах',
                                    height: 44,
                                    size: GradientButtonSize.md,
                                    borderRadius: 16,
                                    icon: const Icon(Icons.directions_outlined,
                                        size: 20),
                                    onPressed: () => _directions(venue))),
                            const SizedBox(width: 10),
                            IconButton.filledTonal(
                                tooltip: saved
                                    ? 'Хадгалсан газраас хасах'
                                    : 'Газар хадгалах',
                                onPressed: _saving ? null : () => _save(venue),
                                style: IconButton.styleFrom(
                                    backgroundColor: _surface,
                                    foregroundColor:
                                        saved ? _accent : _foreground,
                                    minimumSize: const Size(48, 48)),
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                            OwlLoading(size: 18, compact: true))
                                    : Icon(
                                        saved
                                            ? Icons.bookmark_rounded
                                            : Icons.bookmark_border_rounded,
                                        size: 23,
                                        color: saved ? _accent : _foreground)),
                          ]),
                          Semantics(
                              value: expanded
                                  ? 'Дэлгэрэнгүй мэдээлэл нээлттэй'
                                  : 'Дэлгэрэнгүй мэдээлэл хураасан',
                              child: TextButton.icon(
                                  onPressed: () => setState(() =>
                                      _expandedVenueId =
                                          expanded ? null : venue.id),
                                  style: TextButton.styleFrom(
                                      foregroundColor: _accent,
                                      minimumSize: const Size(0, 44),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4)),
                                  icon: Icon(
                                      expanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 20),
                                  label: Text(
                                      expanded ? 'Хураах' : 'Дэлгэрэнгүй'))),
                          if (expanded) ...[
                            Divider(color: _line, height: 16),
                            Text(text,
                                style: AppTextStyles.bodySm
                                    .copyWith(color: _foreground, height: 1.5)),
                            if (venue.sourceLabel != null) ...[
                              const SizedBox(height: 6),
                              Text(venue.sourceLabel!,
                                  style: AppTextStyles.bodyXs
                                      .copyWith(color: secondary)),
                            ],
                            const SizedBox(height: 8),
                            TextButton.icon(
                                onPressed: () => _showInformation(venue),
                                style: TextButton.styleFrom(
                                    foregroundColor: _accent),
                                icon: const Icon(Icons.info_outline_rounded,
                                    size: 17),
                                label: const Text(
                                    'Мэдээлэл, Google Maps, холбоос')),
                            if (website != null)
                              TextButton.icon(
                                  onPressed: () => _openExternal(website),
                                  style: TextButton.styleFrom(
                                      foregroundColor: _accent),
                                  icon: const Icon(Icons.language_rounded,
                                      size: 17),
                                  label: const Text('Вэбсайт нээх')),
                            if (source != null)
                              TextButton.icon(
                                  onPressed: () => _openExternal(source),
                                  style: TextButton.styleFrom(
                                      foregroundColor: _accent),
                                  icon: const Icon(Icons.open_in_new_rounded,
                                      size: 15),
                                  label: const Text('Байршлын эх сурвалж')),
                          ],
                        ])))));
    if (AppMotion.reduced(context)) return card;
    return AnimatedSize(
        duration: AppMotion.enter,
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: card);
  }
}
