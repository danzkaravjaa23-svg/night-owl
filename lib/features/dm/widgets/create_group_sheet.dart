import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/group_provider.dart';

/// Групп чат үүсгэх sheet — нэр + гишүүд сонгох.
/// Амжилттай бол {'id': ..., 'name': ...} буцаана (нэрийг refetch хүлээлгүй
/// шууд thread гарчигт харуулахын тулд).
Future<Map<String, String>?> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    backgroundColor: AppColors.bgElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => const _CreateGroupSheet(),
  );
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet();
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

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _search('');
  }

  // Товчлол бүрт бус — 300мс debounce хийж хайна
  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_reqSeq;
    setState(() => _searching = true);
    try {
      var query = SupabaseService.client.from('profiles')
          .select('id, username, avatar_url')
          .neq('id', _myId);
      if (q.trim().isNotEmpty) query = query.ilike('username', '%$q%');
      final rows = await query.limit(30);
      // Хуучирсан хариуг (шинэ хайлт эхэлсэн бол) алгасна
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _results = (rows as List).cast<Map<String, dynamic>>();
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _reqSeq) return;
      setState(() { _results = []; _searching = false; });
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    final gid = await GroupService.createGroup(name, _selected.keys.toList());
    if (!mounted) return;
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
    _debounce?.cancel();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        _nameCtrl.text.trim().isNotEmpty && _selected.isNotEmpty && !_busy;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppColors.hairline2,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),

          // ── Header — gradient групп badge + гарчиг + micro тайлбар ──
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentGradient,
                boxShadow: AppColors.glowShadow(AppColors.accentStart,
                    blur: 16, offset: const Offset(0, 4))),
            child: const Icon(Icons.groups_rounded,
                color: Colors.white, size: 24)),
          const SizedBox(height: 10),
          Text('Групп чат үүсгэх', style: AppTextStyles.h2),
          const SizedBox(height: 3),
          Text('Найзуудаа нэг чатад цуглуул',
              style: AppTextStyles.bodyXs.copyWith(
                  color: AppColors.textSecondary)),
          const SizedBox(height: 16),

          // Группийн нэр — шилэн pill талбар
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PillField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              hint: 'Группийн нэр...',
              icon: Icons.groups_rounded,
            )),
          const SizedBox(height: 10),

          // Сонгосон гишүүд — avatar pill chips
          if (_selected.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final u in _selected.values)
                    _MemberChip(
                      username: (u['username'] as String? ?? '')
                          .replaceAll('@', ''),
                      avatarUrl: u['avatar_url'] as String?,
                      onRemove: () => setState(
                          () => _selected.remove(u['id'])),
                    ),
                ])),

          // Хайлт — шилэн pill талбар
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: _PillField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              hint: 'Гишүүн хайх...',
              icon: Icons.search,
            )),

          // Хэрэглэгчид
          Expanded(child: _searching && _results.isEmpty
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.accentStart, strokeWidth: 2))
            : _results.isEmpty
              ? Center(child: Text('Хэрэглэгч олдсонгүй',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textSecondary)))
              : ListView.builder(
            itemCount: _results.length,
            itemBuilder: (_, i) {
              final u = _results[i];
              final id = u['id'] as String;
              final uname =
                  (u['username'] as String? ?? 'user').replaceAll('@', '');
              final sel = _selected.containsKey(id);
              return ListTile(
                onTap: () => setState(() =>
                    sel ? _selected.remove(id) : _selected[id] = u),
                leading: AppAvatar(
                    imageUrl: u['avatar_url'] as String?,
                    initial: uname.isNotEmpty
                        ? uname[0].toUpperCase() : '?',
                    size: 40),
                title: Text('@$uname', style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.textPrimary)),
                trailing: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: sel ? AppColors.accentGradient : null,
                    border: sel ? null
                        : Border.all(color: AppColors.hairline2, width: 1.5)),
                  child: sel
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null),
              );
            })),

          // Үүсгэх товч
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: _CreateBtn(
              enabled: canCreate,
              onTap: canCreate ? _create : null,
              // Primary товч — pill 52 + gradient glow
              child: Container(
                height: 52, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: canCreate ? AppColors.accentGradient : null,
                  color: canCreate ? null : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: canCreate
                      ? AppColors.glowShadow(AppColors.accentStart)
                      : null),
                alignment: Alignment.center,
                child: _busy
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
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

/// Шилэн pill input талбар (48) — зүүн icon + хүрээгүй TextField
class _PillField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hint;
  final IconData icon;
  const _PillField({
    required this.controller, required this.hint,
    required this.icon, this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      color: AppColors.bgSurface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.hairline)),
    child: Row(children: [
      const SizedBox(width: 16),
      Icon(icon, size: 19, color: AppColors.textTertiary),
      const SizedBox(width: 10),
      Expanded(child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
        cursorColor: AppColors.neonCyan,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textTertiary),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true, contentPadding: EdgeInsets.zero))),
      const SizedBox(width: 16),
    ]));
}

/// Сонгосон гишүүний avatar pill chip — жижиг avatar + нэр + хасах
class _MemberChip extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final VoidCallback onRemove;
  const _MemberChip({
    required this.username, required this.avatarUrl, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
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
      Text(username, style: AppTextStyles.bodyXs.copyWith(
          color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      const SizedBox(width: 6),
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onRemove,
          behavior: HitTestBehavior.opaque,
          child: const Icon(Icons.close,
              size: 14, color: AppColors.textTertiary))),
    ]));
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
      cursor: widget.enabled
          ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: widget.enabled ? () => setState(() => _down = false) : null,
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
