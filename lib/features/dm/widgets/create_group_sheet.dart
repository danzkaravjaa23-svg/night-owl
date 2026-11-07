import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/group_provider.dart';
import 'search_field.dart';

/// Групп чат үүсгэх sheet — нэр + гишүүд сонгох.
/// Амжилттай бол {'id': ..., 'name': ...} буцаана (нэрийг refetch хүлээлгүй
/// шууд thread гарчигт харуулахын тулд).
Future<Map<String, String>?> showCreateGroupSheet(BuildContext context) {
  final session = SupabaseService.client.auth.currentSession;
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    backgroundColor: AppColors.bgElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _CreateGroupSheet(session: session),
  );
}

class _CreateGroupSheet extends StatefulWidget {
  final Session? session;
  const _CreateGroupSheet({required this.session});
  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  final Map<String, Map<String, dynamic>> _selected = {};
  bool _busy = false;
  bool _searching = false;
  Timer? _debounce;
  int _reqSeq = 0; // stale-response race-ээс сэргийлэх дараалал

  Session? _allowedSession;
  StreamSubscription<AuthState>? _authSubscription;
  bool _accountChanged = false;
  String get _myId => widget.session?.user.id ?? '';
  bool get _active =>
      mounted &&
      !_accountChanged &&
      _myId.isNotEmpty &&
      SupabaseService.currentUser?.id == _myId &&
      identical(SupabaseService.client.auth.currentSession, _allowedSession);

  void _invalidateAccount() {
    if (!mounted || _accountChanged) return;
    _debounce?.cancel();
    ++_reqSeq;
    _nameCtrl.clear();
    _searchCtrl.clear();
    setState(() {
      _accountChanged = true;
      _results = [];
      _selected.clear();
      _busy = false;
      _searching = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _allowedSession = widget.session;
    var firstEvent = true;
    _authSubscription =
        SupabaseService.client.auth.onAuthStateChange.listen((state) {
      if (firstEvent && identical(state.session, widget.session)) {
        firstEvent = false;
        return;
      }
      firstEvent = false;
      if (!_accountChanged &&
          state.event == AuthChangeEvent.tokenRefreshed &&
          state.session?.user.id == _myId) {
        _allowedSession = state.session;
      } else {
        _invalidateAccount();
      }
    }, onError: (Object _) => _invalidateAccount());
    _search('');
  }

  // Товчлол бүрт бус — 300мс debounce хийж хайна
  void _onSearchChanged(String q) {
    if (!_active) return;
    _debounce?.cancel();
    ++_reqSeq; // Invalidate the previous response during the debounce window.
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (!_active) return;
    final seq = ++_reqSeq;
    setState(() => _searching = true);
    try {
      var query = SupabaseService.client
          .from('profiles')
          .select('id, username, avatar_url')
          .neq('id', _myId);
      if (q.trim().isNotEmpty) query = query.ilike('username', '%$q%');
      final rows = await query.limit(30);
      // Хуучирсан хариуг (шинэ хайлт эхэлсэн бол) алгасна
      if (!_active || seq != _reqSeq) return;
      setState(() {
        _results = (rows as List).cast<Map<String, dynamic>>();
        _searching = false;
      });
    } catch (_) {
      if (!_active || seq != _reqSeq) return;
      setState(() {
        _results = [];
        _searching = false;
      });
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (!_active || name.isEmpty || _selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    final gid = await GroupService.createGroup(name, _selected.keys.toList(),
        isCurrent: () => _active);
    if (!mounted || !_active) return;
    if (gid == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Групп үүсгэж чадсангүй'),
          backgroundColor: AppColors.error));
      return;
    }
    Navigator.of(context).pop({'id': gid, 'name': name});
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _debounce?.cancel();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_accountChanged) {
      return SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Нэвтрэх бүртгэл өөрчлөгдсөн. Групп үүсгэх цонхыг дахин нээнэ үү.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Хаах')),
              ])));
    }
    final canCreate = _active &&
        _nameCtrl.text.trim().isNotEmpty &&
        _selected.isNotEmpty &&
        !_busy;
    // While typing (keyboard up) the decorative header collapses so the
    // member list and create button still fit on short phones.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        // The theme's drag handle (showDragHandle) is the grabber.
        child: Column(children: [
          // ── Header — gradient групп badge + гарчиг + micro тайлбар ──
          if (!keyboardOpen) ...[
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                    boxShadow: AppColors.glowShadow(AppColors.accentStart,
                        blur: 16, offset: const Offset(0, 4))),
                child: const SculptedIcon(Icons.groups_rounded,
                    color: Colors.white, size: 24, onDark: true)),
            const SizedBox(height: 10),
            Text('Групп чат үүсгэх', style: AppTextStyles.h2),
            const SizedBox(height: 3),
            Text('Найзуудаа нэг чатад цуглуул',
                style: AppTextStyles.bodyXs
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
          ],

          // Группийн нэр — шилэн pill талбар
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                hint: 'Группийн нэр...',
                icon: Icons.groups_rounded,
              )),
          const SizedBox(height: 10),

          // Сонгосон гишүүд — avatar pill chips
          if (_selected.isNotEmpty)
            SizedBox(
                height: 48,
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final u in _selected.values)
                        _MemberChip(
                          username: (u['username'] as String? ?? '')
                              .replaceAll('@', ''),
                          avatarUrl: u['avatar_url'] as String?,
                          onRemove: () =>
                              setState(() => _selected.remove(u['id'])),
                        ),
                    ])),

          // Хайлт — шилэн pill талбар
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: SearchField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                hint: 'Гишүүн хайх...',
              )),

          // Хэрэглэгчид
          Expanded(
              child: _searching && _results.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentStart, strokeWidth: 2))
                  : _results.isEmpty
                      ? Center(
                          child: Text('Хэрэглэгч олдсонгүй',
                              style: AppTextStyles.bodyMd
                                  .copyWith(color: AppColors.textSecondary)))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final u = _results[i];
                            final id = u['id'] as String;
                            final uname = (u['username'] as String? ?? 'user')
                                .replaceAll('@', '');
                            final sel = _selected.containsKey(id);
                            return ListTile(
                              onTap: () => setState(() => sel
                                  ? _selected.remove(id)
                                  : _selected[id] = u),
                              leading: AppAvatar(
                                  imageUrl: u['avatar_url'] as String?,
                                  initial: uname.isNotEmpty
                                      ? uname[0].toUpperCase()
                                      : '?',
                                  size: 40),
                              title: Text('@$uname',
                                  style: AppTextStyles.labelMd
                                      .copyWith(color: AppColors.textPrimary)),
                              trailing: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient:
                                          sel ? AppColors.accentGradient : null,
                                      border: sel
                                          ? null
                                          : Border.all(
                                              color: AppColors.hairline2,
                                              width: 1.5)),
                                  child: sel
                                      ? const SculptedIcon(Icons.check,
                                          size: 15,
                                          color: Colors.white,
                                          onDark: true)
                                      : null),
                            );
                          })),

          // Үүсгэх товч
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: _CreateBtn(
                    enabled: canCreate,
                    onTap: canCreate ? _create : null,
                    // Primary товч — pill 52 + gradient glow
                    child: Container(
                        height: 52,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            gradient:
                                canCreate ? AppColors.accentGradient : null,
                            color: canCreate ? null : AppColors.bgSurface,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: canCreate
                                ? AppColors.glowShadow(AppColors.accentStart)
                                : null),
                        alignment: Alignment.center,
                        // _busy үед canCreate=false тул дэвсгэр нь bgSurface —
                        // spinner сэдвийн текст өнгөтэй (цайвар горимд харагдана)
                        child: _busy
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: AppColors.textPrimary,
                                    strokeWidth: 2))
                            : Text(
                                _selected.isEmpty
                                    ? 'Гишүүн сонгоно уу'
                                    : 'Групп үүсгэх (${_selected.length + 1})',
                                style: AppTextStyles.btn.copyWith(
                                    color: canCreate
                                        ? Colors.white
                                        : AppColors.textTertiary))),
                  ))),
        ]),
      ),
    );
  }
}

/// Сонгосон гишүүний avatar pill chip — жижиг avatar + нэр + хасах
class _MemberChip extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final VoidCallback onRemove;
  const _MemberChip(
      {required this.username,
      required this.avatarUrl,
      required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(right: 8),
      // Өндрийг хасах товчны 44×44 хүрэх талбар тодорхойлно (rail 48)
      padding: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline2)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppAvatar(
            imageUrl: avatarUrl,
            initial: username.isNotEmpty ? username[0].toUpperCase() : '?',
            size: 26),
        const SizedBox(width: 6),
        Text(username,
            style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        // Хасах — глиф 14 хэвээр, хүрэх талбар 44×44
        _RemoveBtn(onTap: onRemove),
      ]));
}

/// Гишүүнийг хасах ✕ — 44×44 хүрэх талбар, ripple-гүй агших press идиом
class _RemoveBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _RemoveBtn({required this.onTap});
  @override
  State<_RemoveBtn> createState() => _RemoveBtnState();
}

class _RemoveBtnState extends State<_RemoveBtn> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _down ? 0.9 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                    child: SculptedIcon(Icons.close,
                        size: 14, color: AppColors.textTertiary))),
          ),
        ),
      );
}

/// Үүсгэх товч — web hover cursor + дарахад агших feedback (локал)
class _CreateBtn extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback? onTap;
  const _CreateBtn({required this.child, required this.enabled, this.onTap});
  @override
  State<_CreateBtn> createState() => _CreateBtnState();
}

class _CreateBtnState extends State<_CreateBtn> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel:
            widget.enabled ? () => setState(() => _down = false) : null,
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
