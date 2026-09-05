import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/services/supabase_service.dart';
import '../widgets/notes_row.dart';
import '../widgets/create_group_sheet.dart';
import '../providers/group_provider.dart';

class DmListScreen extends StatefulWidget {
  const DmListScreen({super.key});
  @override State<DmListScreen> createState() => _DmListScreenState();
}

class _DmListScreenState extends State<DmListScreen> {
  String _search = '';
  bool _searchFocus = false; // хайлтын талбарын focus glow
  List<Map<String, dynamic>> _convos = [];
  List<Map<String, dynamic>> _groups = [];
  bool _loading = true;
  bool _error = false;
  final _notesKey = GlobalKey<NotesRowState>();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // Анхны ачаалалд л skeleton харуулна — refresh үед хуучин жагсаалт хэвээр
    if (_convos.isEmpty && _groups.isEmpty) setState(() => _loading = true);
    // Notes мөрийг зэрэг сэргээнэ
    _notesKey.currentState?.reload();
    try {
      final me = SupabaseService.currentUser?.id;
      if (me == null) { if (mounted) setState(() => _loading = false); return; }

      // RPC байвал (dm_conversations) нэг conversation тутам НЭГ мөр буцаадаг тул
      // хамгийн зөв. Байхгүй/алдаа гарвал доорх messages-fallback руу шилжинэ.
      final rpcConvos = await _loadViaRpc(me);
      if (rpcConvos != null) {
        final groups = await GroupService.myGroups();
        if (!mounted) return;
        setState(() {
          _convos = rpcConvos;
          _groups = groups;
          _loading = false;
          _error = false;
        });
        return;
      }

      // Fallback: сүүлийн мессежүүдээс partner-уудыг гаргаж авна.
      // NOTE: энэ нь идэвхтэй хэрэглэгчийн хувьд бүрэн бус (RPC-г үзнэ үү).
      final data = await SupabaseService.client
          .from('messages')
          .select('*, sender:profiles!sender_id(id,username,avatar_url,last_seen_at), receiver:profiles!receiver_id(id,username,avatar_url,last_seen_at)')
          .or('sender_id.eq.$me,receiver_id.eq.$me')
          .order('created_at', ascending: false)
          .limit(400);
      if (!mounted) return;

      final Map<String, Map<String, dynamic>> seen = {};
      final Map<String, int> unread = {};
      for (final msg in (data as List)) {
        final m = msg as Map<String, dynamic>;
        final senderId   = m['sender_id'] as String;
        final receiverId = m['receiver_id'] as String;
        final partnerId  = senderId == me ? receiverId : senderId;
        // Зөвхөн НАДАД ирсэн уншаагүй мессежийг тоолно (Instagram-маяг)
        if (senderId != me && m['is_read'] == false) {
          unread[partnerId] = (unread[partnerId] ?? 0) + 1;
        }
        if (!seen.containsKey(partnerId)) {
          seen[partnerId] = {
            'partner_id': partnerId,
            'partner': senderId == me ? m['receiver'] : m['sender'],
            'last_msg': m['body'] ?? '',
            'created_at': m['created_at'],
            // Өөрийн илгээсэн мессеж миний талд "уншаагүй" гэж тооцогдохгүй
            'is_read': senderId == me ? true : (m['is_read'] ?? true),
            'is_me': senderId == me,
          };
        }
      }
      // Сүүлийн мессеж минийх ч өмнөх ирсэн мессежүүд уншаагүй бол unread
      for (final e in seen.entries) {
        final c = unread[e.key] ?? 0;
        e.value['unread_count'] = c;
        if (c > 0) e.value['is_read'] = false;
      }
      final groups = await GroupService.myGroups();
      if (!mounted) return;
      setState(() {
        _convos = seen.values.toList();
        _groups = groups;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Хуучин жагсаалтыг хадгална — алдааг мэдэгдэнэ
      setState(() { _loading = false; _error = true; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ачаалж чадсангүй. Дахин оролдоно уу.'),
        backgroundColor: AppColors.error));
    }
  }

  /// dm_conversations RPC-ээр нэг яриа тутам нэг мөр авна (unread count-той).
  /// RPC байхгүй бол null буцааж fallback руу шилжүүлнэ.
  Future<List<Map<String, dynamic>>?> _loadViaRpc(String me) async {
    try {
      final rows = await SupabaseService.client.rpc('dm_conversations');
      final list = (rows as List).cast<Map<String, dynamic>>();
      return [
        for (final r in list)
          {
            'partner_id': r['partner_id'],
            'partner': {
              'id': r['partner_id'],
              'username': r['partner_username'] ?? 'User',
              'avatar_url': r['partner_avatar_url'],
              'last_seen_at': r['partner_last_seen_at'],
            },
            'last_msg': r['last_body'] ?? '',
            'created_at': r['last_at'],
            'is_me': r['last_sender_id'] == me,
            'unread_count': (r['unread_count'] as num?)?.toInt() ?? 0,
            'is_read': ((r['unread_count'] as num?)?.toInt() ?? 0) == 0,
          },
      ];
    } catch (_) {
      // RPC байхгүй эсвэл алдаа — fallback руу
      return null;
    }
  }

  // Хэсгийн гарчиг — sectionLabel + баруун талд neonCyan тоолуур
  Widget _sectionHeader(String t, {String? trailing, double top = 24}) => Padding(
    padding: EdgeInsets.fromLTRB(20, top, 20, 10),
    child: Row(children: [
      Text(t, style: AppTextStyles.sectionLabel),
      const Spacer(),
      if (trailing != null)
        Text(trailing, style: AppTextStyles.labelSm.copyWith(
          color: AppColors.neonCyan)),
    ]));

  Future<void> _newGroup() async {
    // Sheet нь {id, name} буцаана — нэрийг refetch хүлээлгүйгээр шууд дамжуулна
    final res = await showCreateGroupSheet(context);
    if (res != null && mounted) {
      final gid  = res['id'];
      if (gid == null) return;
      final name = res['name'];
      _load();
      context.push('/group/$gid${name != null && name.isNotEmpty ? '?name=${Uri.encodeComponent(name)}' : ''}')
          .then((_) { if (mounted) _load(); });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _convos;
    return _convos.where((c) {
      final partner  = c['partner'] as Map?;
      final username = partner?['username'] as String? ?? '';
      return username.toLowerCase().contains(_search.toLowerCase()) ||
          (c['last_msg'] as String? ?? '').toLowerCase().contains(_search.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _convos.where((c) => c['is_read'] == false).length;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(child: Column(children: [
        // ── Header — том "Чат" гарчиг + шилэн дугуй үйлдлүүд ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Row(children: [
            if (context.canPop()) ...[
              _CircleBtn(
                icon: Icons.chevron_left_rounded, iconSize: 24,
                tooltip: 'Буцах',
                onTap: () => context.pop()),
              const SizedBox(width: 12),
            ],
            Text('Чат', style: AppTextStyles.h1),
            if (unreadCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: AppColors.glowShadow(AppColors.accentStart)),
                child: Text('$unreadCount шинэ',
                  style: const TextStyle(color: Colors.white,
                    fontSize: 11, fontWeight: FontWeight.w700))),
            ],
            const Spacer(),
            _CircleBtn(
              icon: Icons.group_add_outlined,
              tooltip: 'Групп чат үүсгэх',
              onTap: _newGroup),
            const SizedBox(width: 10),
            _CircleBtn(
              icon: Icons.refresh_rounded, iconSize: 19,
              tooltip: 'Дахин ачаалах',
              onTap: _load),
          ]),
        ),

        // ── Search — шилэн pill 48, focus үед cyan glow ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _searchFocus
                  ? AppColors.neonCyan.withValues(alpha: 0.6)
                  : AppColors.hairline),
              boxShadow: _searchFocus
                  ? [
                      BoxShadow(
                        color: AppColors.neonCyan.withValues(alpha: 0.18),
                        blurRadius: 16, spreadRadius: -2),
                    ]
                  : AppColors.shadowCard),
            child: Row(children: [
              const SizedBox(width: 16),
              Icon(Icons.search, size: 19,
                color: _searchFocus
                    ? AppColors.neonCyan : AppColors.textTertiary),
              const SizedBox(width: 10),
              Expanded(child: Focus(
                onFocusChange: (f) => setState(() => _searchFocus = f),
                child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                cursorColor: AppColors.neonCyan,
                decoration: InputDecoration(
                  hintText: 'Мессеж хайх...',
                  hintStyle: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textTertiary),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.zero)))),
              if (_search.isNotEmpty)
                InkResponse(
                  onTap: () => setState(() => _search = ''),
                  radius: 16,
                  child: const Padding(padding: EdgeInsets.only(right: 14),
                    child: Icon(Icons.close,
                      color: AppColors.textTertiary, size: 16))),
            ])),
        ),
        const SizedBox(height: 4),

        // ── Бүх контент НЭГ scroll дотор — notes rail + шилэн section картууд ──
        Expanded(child: RefreshIndicator(
          color: AppColors.accentStart,
          backgroundColor: AppColors.bgElevated,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // Notes / online rail — контенттой хамт гүйлгэгдэнэ (Instagram-маяг)
              _sectionHeader('ШӨНИЙН NOTES', top: 10),
              NotesRow(key: _notesKey),
              if (_loading)
                const _ListSkeleton()
              else if (_error && _convos.isEmpty && _groups.isEmpty)
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: _ErrorState(onRetry: _load))
              else if (_filtered.isEmpty && _groups.isEmpty)
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.45,
                  child: _EmptyState())
              else ...[
                if (_groups.isNotEmpty) ...[
                  _sectionHeader('ГРУПП ЧАТ', trailing: '${_groups.length}'),
                  _SectionCard(children: [
                    for (final g in _groups)
                      _GroupTile(group: g, onChanged: _load),
                  ]),
                ],
                if (_filtered.isNotEmpty) ...[
                  _sectionHeader('МЕССЕЖ', trailing: '${_filtered.length} чат'),
                  _SectionCard(children: [
                    for (final c in _filtered)
                      _ConvoTile(convo: c, onChanged: _load),
                  ]),
                ],
              ],
              const SizedBox(height: 90),
            ]),
        )),
      ])),
    );
  }
}

/// Шилэн section карт — мөрүүдийг radius-24 glass блокт багцалж,
/// хооронд нь indent-тэй hairline зураасаар тусгаарлана (Messenger 2025 template)
class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: AppColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.hairline),
      boxShadow: AppColors.shadowCard),
    clipBehavior: Clip.antiAlias,
    child: Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          const Padding(
            padding: EdgeInsets.only(left: 84),
            child: Divider(height: 1, thickness: 1, color: AppColors.hairline)),
        children[i],
      ],
    ]));
}

/// Шилэн дугуй icon товч — header үйлдлүүдэд (hover cursor + tooltip)
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String? tooltip;
  final VoidCallback onTap;
  const _CircleBtn({
    required this.icon, required this.onTap,
    this.iconSize = 21, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgSurface.withValues(alpha: 0.6),
            border: Border.all(color: AppColors.hairline2)),
          child: Icon(icon, size: iconSize, color: AppColors.textPrimary)),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

/// Сүүлийн 2 минутад идэвхтэй байсан бол online гэж үзнэ
bool _isOnline(String? lastSeenIso) {
  if (lastSeenIso == null) return false;
  final t = DateTime.tryParse(lastSeenIso);
  if (t == null) return false;
  return DateTime.now().toUtc().difference(t.toUtc()).inMinutes < 2;
}

class _ConvoTile extends StatelessWidget {
  final Map<String, dynamic> convo;
  final VoidCallback onChanged;
  const _ConvoTile({required this.convo, required this.onChanged});

  String get _myId => SupabaseService.currentUser?.id ?? '';

  // Партнёроос ирсэн мессежийг уншсан/уншаагүй болгоно
  Future<void> _setRead(BuildContext context, String partnerId, bool read) async {
    final me = _myId;
    if (me.isEmpty) return;
    try {
      await SupabaseService.client
          .from('messages')
          .update({'is_read': read})
          .eq('sender_id', partnerId)
          .eq('receiver_id', me);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Амжилтгүй боллоо. Дахин оролдоно уу.'),
          backgroundColor: AppColors.error));
      }
    }
  }

  void _showOptions(BuildContext context, String partnerId,
      String username, bool isRead) {
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetCtx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: AppColors.hairline, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text(username.replaceAll('@', ''), style: AppTextStyles.labelLg),
            ])),
          const SizedBox(height: 8),
          if (!isRead)
            _OptTile(icon: Icons.mark_chat_read_outlined, label: 'Уншсан болгох',
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _setRead(context, partnerId, true);
                onChanged();
              })
          else
            _OptTile(icon: Icons.mark_chat_unread_outlined, label: 'Уншаагүй болгох',
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _setRead(context, partnerId, false);
                onChanged();
              }),
          _OptTile(icon: Icons.chat_bubble_outline, label: 'Чат нээх',
            onTap: () {
              Navigator.pop(sheetCtx);
              context.push('/dm/$partnerId').then((_) => onChanged());
            }),
          _OptTile(icon: Icons.person_outline, label: 'Профайл харах',
            onTap: () {
              Navigator.pop(sheetCtx);
              context.push('/creator/$partnerId');
            }),
          const SizedBox(height: 12),
        ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partner    = convo['partner'] as Map?;
    final username   = partner?['username'] as String? ?? 'Unknown';
    final avatarUrl  = partner?['avatar_url'] as String?;
    final initial    = username.replaceAll('@','').isNotEmpty
        ? username.replaceAll('@','')[0].toUpperCase() : '?';
    final lastMsg    = convo['last_msg'] as String? ?? '';
    final isMe       = convo['is_me'] as bool? ?? false;
    final isRead     = convo['is_read'] as bool? ?? true;
    final unreadCnt  = convo['unread_count'] as int? ?? 0;
    final partnerId  = convo['partner_id'] as String;
    final time       = _ago(convo['created_at'] as String?);

    // Messenger-маягийн мөр: avatar 54 · нэр+сүүлийн мессеж · баруун талд цаг+badge
    return InkWell(
      onTap: () => context.push('/dm/$partnerId').then((_) => onChanged()),
      onLongPress: () => _showOptions(context, partnerId, username, isRead),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          Stack(children: [
            AppAvatar(imageUrl: avatarUrl, initial: initial, size: 54),
            // Online/offline цэг — online үед lime glow-той
            Positioned(bottom: 2, right: 2,
              child: Builder(builder: (_) {
                final online = _isOnline(partner?['last_seen_at'] as String?);
                return Container(width: 13, height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online
                        ? AppColors.success
                        : const Color(0xFF6E6E78),
                    // Карт дотор тул хүрээ нь elevated дэвсгэртэй нийлнэ
                    border: Border.all(color: AppColors.bgElevated, width: 2),
                    boxShadow: online
                        ? [
                            BoxShadow(
                              color: AppColors.success.withValues(alpha: 0.55),
                              blurRadius: 8),
                          ]
                        : null));
              })),
          ]),
          const SizedBox(width: 14),
          // Нэр + сүүлийн мессеж (1 мөр)
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(username, style: AppTextStyles.labelMd.copyWith(
                fontWeight: isRead ? FontWeight.w600 : FontWeight.w700)),
              const SizedBox(height: 3),
              Text('${isMe ? 'Та: ' : ''}$lastMsg',
                maxLines: 1,
                style: AppTextStyles.bodySm.copyWith(
                  color: isRead ? AppColors.textSecondary : AppColors.textPrimary,
                  fontWeight: isRead ? FontWeight.w400 : FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            ])),
          const SizedBox(width: 10),
          // Баруун багана: цаг (micro) + unread gradient badge 20
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: AppTextStyles.bodyXs.copyWith(
                color: isRead ? AppColors.textTertiary : AppColors.accentStart,
                fontWeight: isRead ? FontWeight.w400 : FontWeight.w600)),
              const SizedBox(height: 5),
              if (!isRead)
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                    boxShadow: AppColors.glowShadow(AppColors.accentStart,
                        blur: 10, offset: const Offset(0, 2))),
                  alignment: Alignment.center,
                  child: Text(
                    unreadCnt > 9 ? '9+' : '${unreadCnt > 0 ? unreadCnt : 1}',
                    style: const TextStyle(color: Colors.white,
                      fontSize: 10, fontWeight: FontWeight.w700)))
              else
                const SizedBox(height: 20),
            ]),
        ]),
      ),
    );
  }

  // Монгол товч хугацаа — notes_row-ийн хэв маягтай нийцүүлэв
  String _ago(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 1)  return 'сая';
    if (d.inMinutes < 60) return '${d.inMinutes}м';
    if (d.inHours < 24)   return '${d.inHours}ц';
    if (d.inDays < 7)     return '${d.inDays}ө';
    return '${(d.inDays/7).floor()}дх';
  }
}

class _OptTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _OptTile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.textSecondary, size: 22),
    title: Text(label, style: AppTextStyles.bodyMd.copyWith(
      color: AppColors.textPrimary)),
    onTap: onTap,
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const EmptyState(
    illustration: 'assets/images/illustrations/empty_dm.svg',
    title: 'Мессеж алга байна',
    subtitle: 'Хүмүүсийн profile-д орж мессеж илгээ.',
  );
}

/// Сүлжээний алдааны төлөв — retry товчтой
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, color: AppColors.textTertiary, size: 44),
      const SizedBox(height: 12),
      Text('Ачаалж чадсангүй', style: AppTextStyles.bodyMd.copyWith(
        color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(14)),
          child: Text('Дахин оролдох', style: AppTextStyles.btn.copyWith(
            color: Colors.white)))),
    ]));
}

/// Ачааллах skeleton — шилэн карт дотор avatar + 2 мөр бүхий 6 tile
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();
  @override
  Widget build(BuildContext context) => _Pulse(child: Container(
    margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    decoration: BoxDecoration(
      color: AppColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.hairline)),
    child: Column(
      children: [for (var i = 0; i < 6; i++) const _SkeletonTile()])));
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Container(width: 52, height: 52, decoration: const BoxDecoration(
        shape: BoxShape.circle, color: AppColors.bgSurface)),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 12, width: 130, decoration: BoxDecoration(
            color: AppColors.bgSurface, borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 8),
          Container(height: 10, decoration: BoxDecoration(
            color: AppColors.bgSurface, borderRadius: BorderRadius.circular(5))),
        ])),
    ]));
}

/// Зөөлөн анивчих (pulse) эффект
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});
  @override State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 400),
    lowerBound: 0.45, upperBound: 1.0)..repeat(reverse: true);
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _c, child: widget.child);
}

/// Групп чатын мөр
class _GroupTile extends StatelessWidget {
  final Map<String, dynamic> group;
  final VoidCallback onChanged;
  const _GroupTile({required this.group, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final name = group['name'] as String? ?? 'Групп';
    final last = group['last_msg'] as String?;
    // Convo мөртэй ижил бүтэц — ДАВХАРЛАСАН групп avatar (stacked) + chevron
    return InkWell(
      onTap: () => context.push(
          '/group/${group['id']}?name=${Uri.encodeComponent(name)}')
          .then((_) => onChanged()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(children: [
          // Stacked avatar — ард гишүүний дугуй, урд gradient групп дугуй
          SizedBox(
            width: 54, height: 54,
            child: Stack(children: [
              Positioned(top: 0, right: 0,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgSurface,
                    border: Border.all(color: AppColors.hairline2)),
                  child: const Icon(Icons.person,
                      size: 17, color: AppColors.textTertiary))),
              Positioned(bottom: 0, left: 0,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                    border: Border.all(color: AppColors.bgElevated, width: 2),
                    boxShadow: AppColors.glowShadow(AppColors.accentStart,
                        blur: 12, offset: const Offset(0, 3))),
                  child: const Icon(Icons.groups_rounded,
                      color: Colors.white, size: 19))),
            ])),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppTextStyles.labelMd.copyWith(
                  fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(last ?? 'Группийн яриа эхлүүлээрэй',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textSecondary)),
            ])),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right,
              color: AppColors.textTertiary, size: 20),
        ]),
      ),
    );
  }
}
