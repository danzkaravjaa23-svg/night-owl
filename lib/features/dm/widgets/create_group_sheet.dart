import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/group_provider.dart';
import 'search_field.dart';

/// Групп чат үүсгэх sheet — нэр + гишүүд сонгох.
/// Амжилттай бол {'id': ..., 'name': ...} буцаана (нэрийг refetch хүлээлгүй
/// шууд thread гарчигт харуулахын тулд).
Future<Map<String, String>?> showCreateGroupSheet(BuildContext context) {
  final session = SupabaseService.client.auth.currentSession;
  // showAppSheet (DS-02): root navigator дээр нээгдэж dock-ийг бүрхэнэ;
  // өнгө, радиус, бариулыг bottomSheetTheme өгнө.
  return showAppSheet<Map<String, String>>(
    context: context,
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

  /// Үүсгэж чадаагүй үеийн алдаа — sheet дотор, товчны дээр харуулна
  /// (root sheet нээлттэй үед SnackBar sheet-ийн ДООР зурагддаг).
  /// Дахин оролдоход арилна.
  String? _error;
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
      _error = null;
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
    setState(() {
      _busy = true;
      _error = null;
    });
    final gid = await GroupService.createGroup(name, _selected.keys.toList(),
        isCurrent: () => _active);
    if (!mounted || !_active) return;
    if (gid == null) {
      setState(() {
        _busy = false;
        _error = 'Групп үүсгэж чадсангүй';
      });
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
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(children: [
          // ── Header — sheet-ийн нэгдсэн гарчгийн мөр (DS-02) ──
          const AppSheetHeader(
              title: 'Групп чат үүсгэх',
              subtitle: 'Найзуудаа нэг чатад цуглуул'),
          const SizedBox(height: 8),

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
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentText, strokeWidth: 2))
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

          // Үүсгэх товч — нэгдсэн primary GradientButton (DS-03). Алдааг
          // sheet дотор, товчны дээр харуулна; дахин дарахад арилна.
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Semantics(
                              liveRegion: true,
                              child: Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodySm
                                      .copyWith(color: AppColors.danger)))),
                    GradientButton(
                      label: _selected.isEmpty
                          ? 'Гишүүн сонгоно уу'
                          : 'Групп үүсгэх (${_selected.length + 1})',
                      busy: _busy,
                      onPressed: canCreate ? _create : null,
                    ),
                  ]))),
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
                    child: SculptedIcon(AppIcons.close,
                        size: 14, color: AppColors.textTertiary))),
          ),
        ),
      );
}
