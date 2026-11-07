import '../../profile/widgets/block_report_sheet.dart';
import '../../../core/widgets/content_review_notice.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/note_service.dart';
import '../../post/services/content_publication.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';

/// Note үүссэн хугацааг "Xм/Xц/Xө өмнө" болгож харуулна
String _noteTimeAgo(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().toUtc().difference(dt.toUtc());
  if (diff.isNegative || diff.inMinutes < 1) return 'дөнгөж сая';
  if (diff.inMinutes < 60) return '${diff.inMinutes}м өмнө';
  if (diff.inHours < 24) return '${diff.inHours}ц өмнө';
  return '${diff.inDays}ө өмнө';
}

double _notesRailHeight(BuildContext context) {
  final scaledLabelSize = MediaQuery.textScalerOf(context).scale(11);
  final extraLabelSize = scaledLabelSize > 11 ? scaledLabelSize - 11 : 0.0;
  // Reserve the same space while loading, including two note lines, a venue,
  // username and timestamp when accessibility text is enlarged.
  return 156 + extraLabelSize * 7;
}

/// Instagram-маягийн Note мөр — DM жагсаалтын дээр. Note нь 24ц богино статус,
/// зөвхөн venue тэмдэглэж болно. Өөрийн bubble дарвал бичих/засах composer нээгдэнэ.
class NotesRow extends StatefulWidget {
  const NotesRow({super.key});
  @override
  State<NotesRow> createState() => NotesRowState();
}

class NotesRowState extends State<NotesRow> {
  List<Map<String, dynamic>> _notes =
      []; // {user_id, username, avatar_url, text, venue_name}
  Map<String, dynamic>? _me; // өөрийн profile
  bool _loaded = false;
  int _loadGeneration = 0;
  String? _observedOwner;
  StreamSubscription<AuthState>? _auth;

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _observedOwner = SupabaseService.currentUser?.id;
    _auth = SupabaseService.authStream.listen((state) {
      final owner = state.session?.user.id;
      if (!mounted || owner == _observedOwner) return;
      _observedOwner = owner;
      setState(() {
        _me = null;
        _notes = [];
        _loaded = false;
      });
      _load();
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final me = _myId;
    bool current() => mounted && generation == _loadGeneration && me == _myId;
    try {
      Map<String, dynamic>? profile;
      // Өөрийн профайл
      if (me.isNotEmpty) {
        profile = await SupabaseService.client
            .from('profiles')
            .select('id, username, avatar_url')
            .eq('id', me)
            .maybeSingle();
        if (!current()) return;
      }
      // Зөвхөн сүүлийн 24 цагийн note (хугацаа дууссаныг харуулахгүй).
      // created_at нь timestamptz (UTC) тул харьцуулалтыг UTC-ээр хийнэ.
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 24))
          .toIso8601String();
      final data = await SupabaseService.client
          .from('notes')
          .select('id, user_id, text, venue_id, created_at, moderation_status')
          .gt('created_at', cutoff)
          .order('created_at', ascending: false)
          .limit(50);
      if (!current()) return;
      final rows = (data as List).cast<Map<String, dynamic>>();

      final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
      final venueIds =
          rows.map((r) => r['venue_id']).whereType<String>().toSet().toList();

      Map<String, Map<String, dynamic>> pmap = {};
      Map<String, String> vmap = {};
      if (userIds.isNotEmpty) {
        final profs = await SupabaseService.client
            .from('profiles')
            .select('id, username, avatar_url')
            .inFilter('id', userIds);
        if (!current()) return;
        pmap = {
          for (final p in (profs as List).cast<Map<String, dynamic>>())
            p['id'] as String: p
        };
      }
      if (venueIds.isNotEmpty) {
        final vs = await SupabaseService.client
            .from('venues')
            .select('id, name')
            .inFilter('id', venueIds);
        if (!current()) return;
        vmap = {
          for (final v in (vs as List).cast<Map<String, dynamic>>())
            v['id'] as String: v['name'] as String
        };
      }

      final list = rows.map((r) {
        final p = pmap[r['user_id']];
        return {
          'id': r['id'],
          'moderation_status': r['moderation_status'],
          'user_id': r['user_id'],
          'username': p?['username'] ?? 'User',
          'avatar_url': p?['avatar_url'],
          'text': r['text'],
          'venue_id': r['venue_id'],
          'venue_name': r['venue_id'] != null ? vmap[r['venue_id']] : null,
          'created_at': r['created_at'],
        };
      }).toList();
      // Өөрийн note-г эхэнд
      list.sort((a, b) =>
          (a['user_id'] == me ? 0 : 1) - (b['user_id'] == me ? 0 : 1));

      if (current()) {
        setState(() {
          _me = profile;
          _notes = list;
          _loaded = true;
        });
      }
    } catch (_) {
      if (current()) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _auth?.cancel();
    super.dispose();
  }

  /// Гадаад (DM list refresh) дуудлагаас notes мөрийг дахин ачаална
  void reload() => _load();

  Map<String, dynamic>? get _myNote {
    for (final n in _notes) {
      if (n['user_id'] == _myId) return n;
    }
    return null;
  }

  Future<void> _openComposer() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _NoteComposer(existing: _myNote),
    );
    if (saved == true && mounted) _load();
  }

  // Бусдын note-г бүрэн харуулах (текст + venue + Мессеж)
  void _showNoteDetail(Map<String, dynamic> n) {
    final username = (n['username'] as String).replaceAll('@', '');
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      // Scrolls inside the 9/16 sheet cap so a long note or large text never
      // pushes the reply button off screen. The theme draws the grabber.
      builder: (sheetCtx) => SafeArea(
          top: false,
          child: SingleChildScrollView(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    AppAvatar(
                        imageUrl: n['avatar_url'] as String?,
                        initial: username.isNotEmpty
                            ? username[0].toUpperCase()
                            : '?',
                        size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('@$username', style: AppTextStyles.labelLg),
                          if (_noteTimeAgo(n['created_at'] as String?)
                              .isNotEmpty)
                            Text(_noteTimeAgo(n['created_at'] as String?),
                                style: AppTextStyles.bodyXs
                                    .copyWith(color: AppColors.textTertiary)),
                        ])),
                  ]),
                  const SizedBox(height: 14),
                  // Бүрэн текст
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(14)),
                    child: Text(n['text'] as String? ?? '',
                        style: AppTextStyles.bodyLg
                            .copyWith(color: AppColors.textPrimary)),
                  ),
                  if (n['venue_name'] != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      const SculptedIcon(Icons.location_on,
                          size: 16, color: AppColors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(n['venue_name'] as String,
                              style: AppTextStyles.bodyMd
                                  .copyWith(color: AppColors.textPrimary))),
                    ]),
                  ],
                  if (n['id'] is String)
                    TextButton.icon(
                        onPressed: () => showReportSheet(sheetCtx,
                            targetType: 'note', targetId: n['id'] as String),
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Note-г мэдээлэх')),
                  const SizedBox(height: 18),
                  _Pressable(
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      final note = (n['text'] as String? ?? '').trim();
                      final q = note.isEmpty
                          ? ''
                          : '?note=${Uri.encodeComponent(note)}';
                      context.push('/dm/${n['user_id']}$q');
                    },
                    // Primary товч — pill 52 + gradient glow
                    child: Container(
                        height: 52,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            gradient: AppColors.accentGradient,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow:
                                AppColors.glowShadow(AppColors.accentStart)),
                        alignment: Alignment.center,
                        child: Text('Note-д хариулах',
                            style: AppTextStyles.btn
                                .copyWith(color: Colors.white))),
                  ),
                ]),
          ))),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ачааллаж байх үед мөрийн өндрийг хадгалж, skeleton харуулна —
    // ингэснээр search bar / жагсаалт доош "үсрэхгүй".
    if (!_loaded) return const _NotesRowSkeleton();
    final mine = _myNote;
    final others = _notes.where((n) => n['user_id'] != _myId).toList();

    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SizedBox(
        height: _notesRailHeight(context),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            // Өөрийн note (эсвэл "Note үлдээх")
            _NoteBubble(
              avatarUrl: _me?['avatar_url'] as String?,
              username: 'Та',
              noteText: mine?['text'] as String?,
              venueName: mine?['venue_name'] as String?,
              createdAt: mine?['created_at'] as String?,
              isMine: true,
              onTap: _openComposer,
            ),
            for (final n in others)
              _NoteBubble(
                avatarUrl: n['avatar_url'] as String?,
                username: (n['username'] as String).replaceAll('@', ''),
                noteText: n['text'] as String?,
                venueName: n['venue_name'] as String?,
                createdAt: n['created_at'] as String?,
                isMine: false,
                onTap: () => _showNoteDetail(n),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteBubble extends StatelessWidget {
  final String? avatarUrl;
  final String username;
  final String? noteText;
  final String? venueName;
  final String? createdAt;
  final bool isMine;
  final VoidCallback onTap;
  const _NoteBubble({
    required this.avatarUrl,
    required this.username,
    required this.noteText,
    required this.venueName,
    required this.createdAt,
    required this.isMine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final hasNote = noteText != null && (noteText as String).trim().isNotEmpty;
    final bubbleText = hasNote ? noteText! : (isMine ? 'Note үлдээх...' : '');
    return _Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
            width: 104,
            child: Column(children: [
              // Bubble — glass; "Note үлдээх" үед accent border-той
              Container(
                constraints: const BoxConstraints(maxWidth: 104, minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.bgElevated.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: (isMine && !hasNote)
                            ? AppColors.accentStart.withValues(alpha: 0.45)
                            : AppColors.hairline)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(bubbleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyXs.copyWith(
                          color: hasNote
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          height: 1.15)),
                  if (venueName != null)
                    Text('📍${venueName!}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Шар өнгө цайвар бөмбөлөг дээр уншигдахгүй тул гэрэл горимд
                        // бараан алтан; 9px → 11px (уншигдах доод хэмжээ).
                        style: AppTextStyles.bodyXs.copyWith(
                            color: AppColors.isDarkMode
                                ? AppColors.amber
                                : const Color(0xFF8A5A00),
                            fontSize: 11,
                            height: 1.2)),
                ]),
              ),
              const SizedBox(height: 2),
              // Story-rail 64 avatar — note-той бол storyRingGradient ринг
              Stack(clipBehavior: Clip.none, children: [
                if (isMine && !hasNote)
                  // "Note үлдээх" — зөөлөн gradient ринг + "+" badge
                  Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.accentGradientSoft),
                      child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: AppColors.bgBase),
                          child: AppAvatar(
                              imageUrl: avatarUrl, initial: initial, size: 56)))
                else
                  AppAvatar(
                      imageUrl: avatarUrl,
                      initial: initial,
                      size: 64,
                      showRing: hasNote),
                if (isMine && !hasNote)
                  Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.accentGradient,
                              border:
                                  Border.all(color: AppColors.bgBase, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.accentStart
                                        .withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    spreadRadius: -1),
                              ]),
                          child: const SculptedIcon(Icons.add,
                              color: Colors.white, size: 12, onDark: true))),
              ]),
              const SizedBox(height: 2),
              SizedBox(
                  width: 100,
                  child: Text(username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.textSecondary, height: 1.2))),
              if (hasNote && _noteTimeAgo(createdAt).isNotEmpty)
                Text(_noteTimeAgo(createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        height: 1.2)),
            ])),
      ),
    );
  }
}

/// Note бичих/засах — текст + (зөвхөн) venue тэмдэглэх
class _NoteComposer extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  const _NoteComposer({this.existing});
  @override
  ConsumerState<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends ConsumerState<_NoteComposer> {
  late final TextEditingController _ctrl;
  String? _venueId;
  String? _venueName;
  bool _busy = false;
  bool _stale = false;
  late final NoteService _service;
  late final PublicationSession _session;
  StreamSubscription<void>? _auth;
  ModalRoute<dynamic>? _pickerRoute;

  @override
  void initState() {
    super.initState();
    _ctrl =
        TextEditingController(text: widget.existing?['text'] as String? ?? '');
    _venueName = widget.existing?['venue_name'] as String?;
    _venueId = widget.existing?['venue_id'] as String?;
    _service = ref.read(noteServiceProvider);
    _session = _service.captureSession();
    _auth = _service.sessionChanges
        .listen((_) => _checkSession(), onError: (Object _) => _checkSession());
  }

  void _checkSession() {
    scheduleMicrotask(() {
      if (!mounted || _session.isCurrent) return;
      _ctrl.clear();
      final picker = _pickerRoute;
      if (picker?.isActive == true) picker!.navigator?.removeRoute(picker);
      setState(() {
        _stale = true;
        _venueId = null;
        _venueName = null;
      });
    });
  }

  Future<void> _pickVenue() async {
    if (_busy || !_session.isCurrent) return;
    final v = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        _pickerRoute = ModalRoute.of(ctx);
        return const _VenueSearchSheet();
      },
    );
    _pickerRoute = null;
    if (v != null && mounted && _session.isCurrent) {
      setState(() {
        _venueId = v['id'] as String;
        _venueName = v['name'] as String;
      });
    }
  }

  Future<void> _save() => _submit(deleting: false);
  Future<void> _delete() => _submit(deleting: true);

  Future<void> _submit({required bool deleting}) async {
    if (_busy || !_session.isCurrent || _stale) return;
    final text = _ctrl.text.trim();
    if (!deleting && text.isEmpty) return;
    final venue = _venueId;
    setState(() => _busy = true);
    try {
      String? status;
      if (deleting) {
        await _service.delete(_session);
      } else {
        status = await _service.save(_session, text, venue);
      }
      if (mounted && _session.isCurrent) {
        if (!deleting) {
          showPublicationFeedback(context, SavedContentKind.note, status);
        }
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted && _session.isCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Өөрчлөлтийг баталгаажуулж чадсангүй. Дахин оролдоно уу.'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    _session.close();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stale || !_session.isCurrent) {
      // Full width: the M3 sheet's width is loose.
      return const SafeArea(
          child: SizedBox(
              width: double.infinity,
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Нэвтрэх хаяг өөрчлөгдсөн байна. Note-оо дахин нээнэ үү.',
                      textAlign: TextAlign.center))));
    }
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16),
      // The theme's drag handle (showDragHandle) is the grabber.
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Note үлдээх', style: AppTextStyles.labelLg),
            const SizedBox(height: 4),
            Text('Найзууд чинь 24 цаг харна',
                style: AppTextStyles.bodyXs
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            ContentReviewNotice(
                status: widget.existing?['moderation_status'] as String? ??
                    'approved'),
            TextField(
              controller: _ctrl,
              readOnly: _busy,
              autofocus: true,
              maxLength: 100,
              maxLines: 3,
              style:
                  AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                  hintText: 'Юу бодож байна?',
                  hintStyle: AppTextStyles.bodyMd
                      .copyWith(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.bgSurface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none)),
            ),
            const SizedBox(height: 8),
            // Зөвхөн venue тэмдэглэх
            _Pressable(
              onTap: _busy ? null : _pickVenue,
              // The row stays 46pt tall; with a venue set, the clear button's
              // 44pt box replaces the vertical/right padding.
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 46),
                padding:
                    EdgeInsets.fromLTRB(14, 1, _venueName != null ? 2 : 14, 1),
                decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _venueName != null
                            ? AppColors.accentStart
                            : AppColors.hairline)),
                child: Row(children: [
                  SculptedIcon(Icons.location_on_outlined,
                      size: 18,
                      color: _venueName != null
                          ? AppColors.accentStart
                          : AppColors.textSecondary),
                  const SizedBox(width: 8),
                  // Own vertical padding: the row's padding is only 1pt so the
                  // 44pt clear box fits, but wrapped names must not touch the border.
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Text(
                              _venueName ?? 'Газар тэмдэглэх (заавал биш)',
                              style: AppTextStyles.bodyMd.copyWith(
                                  color: _venueName != null
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary)))),
                  if (_venueName != null)
                    _Pressable(
                        onTap: _busy
                            ? null
                            : () => setState(() {
                                  _venueId = null;
                                  _venueName = null;
                                }),
                        child: Semantics(
                            button: true,
                            label: 'Газрыг арилгах',
                            child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                    child: SculptedIcon(Icons.close,
                                        size: 16,
                                        color: AppColors.textTertiary))))),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              if (editing)
                Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _Pressable(
                        onTap: _busy ? null : _delete,
                        child: Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                                color: AppColors.bgSurface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.hairline2)),
                            alignment: Alignment.center,
                            child: const SculptedIcon(Icons.delete_outline,
                                color: AppColors.error)))),
              // Primary товч — pill 52 + gradient glow
              Expanded(
                  child: _Pressable(
                      onTap: _busy ? null : _save,
                      child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                              gradient: AppColors.accentGradient,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow:
                                  AppColors.glowShadow(AppColors.accentStart)),
                          alignment: Alignment.center,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text('Хуваалцах',
                                  style: AppTextStyles.btn
                                      .copyWith(color: Colors.white))))),
            ]),
          ])),
    );
  }
}

/// Venue хайх sheet (note-д зориулсан)
class _VenueSearchSheet extends StatefulWidget {
  const _VenueSearchSheet();
  @override
  State<_VenueSearchSheet> createState() => _VenueSearchSheetState();
}

class _VenueSearchSheetState extends State<_VenueSearchSheet> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final generation = ++_searchGeneration;
    setState(() => _loading = true);
    List<Map<String, dynamic>> results;
    try {
      var query =
          SupabaseService.client.from('venues').select('id, name, district');
      if (q.isNotEmpty) query = query.ilike('name', '%$q%');
      final data = await query.limit(30);
      results = (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      results = [];
    }
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      // The theme's drag handle (showDragHandle) is the grabber.
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Газар сонгох', style: AppTextStyles.labelLg),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: _search,
              style:
                  AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
              decoration: InputDecoration(
                  hintText: 'Газар хайх...',
                  prefixIcon:
                      SculptedIcon(Icons.search, color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.bgSurface,
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none)),
            ),
            const SizedBox(height: 8),
            // Shrinks to the space left above the keyboard on short phones.
            Flexible(
                child: SizedBox(
                    height: 320,
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.accentStart, strokeWidth: 2))
                        : _results.isEmpty
                            ? Center(
                                child: Text('Газар олдсонгүй',
                                    style: AppTextStyles.bodyMd.copyWith(
                                        color: AppColors.textSecondary)))
                            : ListView.builder(
                                itemCount: _results.length,
                                itemBuilder: (_, i) {
                                  final r = _results[i];
                                  return ListTile(
                                    leading: const SculptedIcon(
                                        Icons.location_on,
                                        color: AppColors.accentStart),
                                    title: Text(r['name'] as String? ?? '',
                                        style: AppTextStyles.bodyMd.copyWith(
                                            color: AppColors.textPrimary)),
                                    subtitle: r['district'] != null
                                        ? Text(r['district'] as String,
                                            style: AppTextStyles.bodyXs
                                                .copyWith(
                                                    color: AppColors
                                                        .textSecondary))
                                        : null,
                                    onTap: () => Navigator.pop(context, r),
                                  );
                                }))),
            const SizedBox(height: 12),
          ])),
    );
  }
}

/// Web дээр hover cursor + дарахад бага зэрэг агших мэдрэмжтэй wrapper.
/// (Локал — гадны area-д хамааралгүй.)
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Notes мөрийн skeleton — үсгийн хэмжээнд таарсан өндрийг хадгална.
class _NotesRowSkeleton extends StatefulWidget {
  const _NotesRowSkeleton();
  @override
  State<_NotesRowSkeleton> createState() => _NotesRowSkeletonState();
}

class _NotesRowSkeletonState extends State<_NotesRowSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.4,
      upperBound: 1.0)
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SizedBox(
        height: _notesRailHeight(context),
        child: FadeTransition(
          opacity: _c,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [for (var i = 0; i < 5; i++) const _NoteSkeletonCell()],
          ),
        ),
      ),
    );
  }
}

class _NoteSkeletonCell extends StatelessWidget {
  const _NoteSkeletonCell();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
            width: 104,
            child: Column(children: [
              Container(
                  height: 40,
                  width: 104,
                  decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(12))),
              const SizedBox(height: 6),
              Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.bgSurface)),
              const SizedBox(height: 8),
              Container(
                  height: 9,
                  width: 60,
                  decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(5))),
            ])),
      );
}
