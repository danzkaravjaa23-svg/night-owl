import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';

/// Instagram-маягийн Note мөр — DM жагсаалтын дээр. Note нь 24ц богино статус,
/// зөвхөн venue таглаж болно. Өөрийн bubble дарвал бичих/засах composer нээгдэнэ.
class NotesRow extends StatefulWidget {
  const NotesRow({super.key});
  @override
  State<NotesRow> createState() => _NotesRowState();
}

class _NotesRowState extends State<NotesRow> {
  List<Map<String, dynamic>> _notes = []; // {user_id, username, avatar_url, text, venue_name}
  Map<String, dynamic>? _me;              // өөрийн profile
  bool _loaded = false;

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = _myId;
      // Өөрийн профайл
      if (me.isNotEmpty) {
        _me = await SupabaseService.client.from('profiles')
            .select('id, username, avatar_url').eq('id', me).maybeSingle();
      }
      final data = await SupabaseService.client.from('notes')
          .select('user_id, text, venue_id, created_at')
          .order('created_at', ascending: false).limit(50);
      final rows = (data as List).cast<Map<String, dynamic>>();

      final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
      final venueIds = rows.map((r) => r['venue_id']).whereType<String>().toSet().toList();

      Map<String, Map<String, dynamic>> pmap = {};
      Map<String, String> vmap = {};
      if (userIds.isNotEmpty) {
        final profs = await SupabaseService.client.from('profiles')
            .select('id, username, avatar_url').inFilter('id', userIds);
        pmap = { for (final p in (profs as List).cast<Map<String, dynamic>>())
          p['id'] as String: p };
      }
      if (venueIds.isNotEmpty) {
        final vs = await SupabaseService.client.from('venues')
            .select('id, name').inFilter('id', venueIds);
        vmap = { for (final v in (vs as List).cast<Map<String, dynamic>>())
          v['id'] as String: v['name'] as String };
      }

      final list = rows.map((r) {
        final p = pmap[r['user_id']];
        return {
          'user_id': r['user_id'],
          'username': p?['username'] ?? 'User',
          'avatar_url': p?['avatar_url'],
          'text': r['text'],
          'venue_name': r['venue_id'] != null ? vmap[r['venue_id']] : null,
        };
      }).toList();
      // Өөрийн note-г эхэнд
      list.sort((a, b) => (a['user_id'] == me ? 0 : 1) - (b['user_id'] == me ? 0 : 1));

      if (mounted) setState(() { _notes = list; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Map<String, dynamic>? get _myNote {
    for (final n in _notes) { if (n['user_id'] == _myId) return n; }
    return null;
  }

  Future<void> _openComposer() async {
    final saved = await showModalBottomSheet<bool>(
      context: context, backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NoteComposer(existing: _myNote),
    );
    if (saved == true) _load();
  }

  // Бусдын note-г бүрэн харуулах (текст + venue + Мессеж)
  void _showNoteDetail(Map<String, dynamic> n) {
    final username = (n['username'] as String).replaceAll('@', '');
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppColors.hairline, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              AppAvatar(imageUrl: n['avatar_url'] as String?,
                initial: username.isNotEmpty ? username[0].toUpperCase() : '?', size: 40),
              const SizedBox(width: 10),
              Text('@$username', style: AppTextStyles.labelLg),
            ]),
            const SizedBox(height: 14),
            // Бүрэн текст
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgSurface, borderRadius: BorderRadius.circular(14)),
              child: Text(n['text'] as String? ?? '',
                style: AppTextStyles.bodyLg.copyWith(color: AppColors.textPrimary)),
            ),
            if (n['venue_name'] != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.location_on, size: 16, color: Color(0xFFFF9500)),
                const SizedBox(width: 6),
                Expanded(child: Text(n['venue_name'] as String,
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary))),
              ]),
            ],
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () {
                Navigator.pop(sheetCtx);
                context.push('/dm/${n['user_id']}');
              },
              child: Container(
                height: 48, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text('Мессеж бичих', style: AppTextStyles.btn.copyWith(color: Colors.white))),
            ),
          ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 0);
    final mine = _myNote;
    final others = _notes.where((n) => n['user_id'] != _myId).toList();

    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SizedBox(
        height: 128,
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
              isMine: true,
              onTap: _openComposer,
            ),
            for (final n in others)
              _NoteBubble(
                avatarUrl: n['avatar_url'] as String?,
                username: (n['username'] as String).replaceAll('@', ''),
                noteText: n['text'] as String?,
                venueName: n['venue_name'] as String?,
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
  final bool isMine;
  final VoidCallback onTap;
  const _NoteBubble({
    required this.avatarUrl, required this.username, required this.noteText,
    required this.venueName, required this.isMine, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final hasNote = noteText != null && (noteText as String).trim().isNotEmpty;
    final bubbleText = hasNote ? noteText! : (isMine ? 'Note үлдээх...' : '');
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(width: 104, child: Column(children: [
          // Bubble
          Container(
            constraints: const BoxConstraints(maxWidth: 104, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(bubbleText, maxLines: 3, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyXs.copyWith(
                  color: hasNote ? AppColors.textPrimary : AppColors.textTertiary,
                  height: 1.15)),
              if (venueName != null)
                Text('📍${venueName!}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFFF9500), fontSize: 9)),
            ]),
          ),
          const SizedBox(height: 2),
          Stack(clipBehavior: Clip.none, children: [
            AppAvatar(imageUrl: avatarUrl, initial: initial, size: 46),
            if (isMine && !hasNote)
              Positioned(right: -2, bottom: -2, child: Container(
                width: 18, height: 18, decoration: BoxDecoration(
                  shape: BoxShape.circle, gradient: AppColors.accentGradient,
                  border: Border.all(color: AppColors.bgBase, width: 2)),
                child: const Icon(Icons.add, color: Colors.white, size: 11))),
          ]),
          const SizedBox(height: 2),
          SizedBox(width: 100, child: Text(username,
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))),
        ])),
      ),
    );
  }
}

/// Note бичих/засах — текст + (зөвхөн) venue таглах
class _NoteComposer extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _NoteComposer({this.existing});
  @override
  State<_NoteComposer> createState() => _NoteComposerState();
}

class _NoteComposerState extends State<_NoteComposer> {
  late final TextEditingController _ctrl;
  String? _venueId;
  String? _venueName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existing?['text'] as String? ?? '');
    _venueName = widget.existing?['venue_name'] as String?;
    // existing venue_id-г мэдэхгүй (зөвхөн нэр) — дахин сонгоход шинэчлэгдэнэ
  }

  Future<void> _pickVenue() async {
    final v = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _VenueSearchSheet(),
    );
    if (v != null && mounted) {
      setState(() { _venueId = v['id'] as String; _venueName = v['name'] as String; });
    }
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    final me = SupabaseService.currentUser?.id;
    if (text.isEmpty || me == null || _busy) return;
    setState(() => _busy = true);
    try {
      await SupabaseService.client.from('notes').upsert({
        'user_id': me,
        'text': text,
        if (_venueId != null) 'venue_id': _venueId,
        'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final me = SupabaseService.currentUser?.id;
    if (me == null) return;
    try {
      await SupabaseService.client.from('notes').delete().eq('user_id', me);
    } catch (_) {}
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16, right: 16, top: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: AppColors.hairline, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Text('Note үлдээх', style: AppTextStyles.labelLg),
        const SizedBox(height: 4),
        Text('Найзууд чинь 24 цаг харна',
          style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        TextField(
          controller: _ctrl, autofocus: true, maxLength: 100, maxLines: 3,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Юу бодож байна?',
            hintStyle: AppTextStyles.bodyMd.copyWith(color: AppColors.textTertiary),
            filled: true, fillColor: AppColors.bgSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 8),
        // Зөвхөн venue таглах
        GestureDetector(
          onTap: _pickVenue,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bgSurface, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _venueName != null
                  ? AppColors.accentStart : AppColors.hairline)),
            child: Row(children: [
              Icon(Icons.location_on_outlined, size: 18,
                color: _venueName != null ? AppColors.accentStart : AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(_venueName ?? 'Газар таглах (заавал биш)',
                style: AppTextStyles.bodyMd.copyWith(
                  color: _venueName != null ? AppColors.textPrimary : AppColors.textSecondary))),
              if (_venueName != null)
                GestureDetector(
                  onTap: () => setState(() { _venueId = null; _venueName = null; }),
                  child: const Icon(Icons.close, size: 16, color: AppColors.textTertiary)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          if (editing)
            Padding(padding: const EdgeInsets.only(right: 10), child: GestureDetector(
              onTap: _delete,
              child: Container(
                height: 48, padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: const Icon(Icons.delete_outline, color: AppColors.error)))),
          Expanded(child: GestureDetector(
            onTap: _busy ? null : _save,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: _busy
                ? const SizedBox(width: 20, height: 20, child:
                    CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Хуваалцах', style: AppTextStyles.btn.copyWith(color: Colors.white))))),
        ]),
      ]),
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

  @override
  void initState() { super.initState(); _search(''); }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      var query = SupabaseService.client.from('venues').select('id, name, district');
      if (q.isNotEmpty) query = query.ilike('name', '%$q%');
      final data = await query.limit(30);
      _results = (data as List).cast<Map<String, dynamic>>();
    } catch (_) { _results = []; }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: AppColors.hairline, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Text('Газар сонгох', style: AppTextStyles.labelLg),
        const SizedBox(height: 12),
        TextField(
          autofocus: true, onChanged: _search,
          style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Газар хайх...',
            prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
            filled: true, fillColor: AppColors.bgSurface, isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 320, child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accentStart, strokeWidth: 2))
          : _results.isEmpty
            ? Center(child: Text('Газар олдсонгүй',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)))
            : ListView.builder(itemCount: _results.length, itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  leading: const Icon(Icons.location_on, color: AppColors.accentStart),
                  title: Text(r['name'] as String? ?? '',
                      style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary)),
                  subtitle: r['district'] != null
                      ? Text(r['district'] as String,
                          style: AppTextStyles.bodyXs.copyWith(color: AppColors.textSecondary))
                      : null,
                  onTap: () => Navigator.pop(context, r),
                );
              })),
        const SizedBox(height: 12),
      ]),
    );
  }
}
