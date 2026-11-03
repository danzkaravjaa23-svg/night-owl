import '../../profile/widgets/block_report_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/sculpted_icon.dart';
import '../../../core/widgets/theme_toggle_button.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/services/supabase_service.dart';
import '../providers/group_provider.dart';
import '../widgets/chat_tokens.dart';
import '../widgets/search_field.dart';

/// Групп чатын дэлгэц — realtime мессеж + гишүүд
class GroupThreadScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;
  const GroupThreadScreen({super.key, required this.groupId, this.groupName});

  @override
  State<GroupThreadScreen> createState() => _GroupThreadScopeState();
}

class _GroupThreadScopeState extends State<GroupThreadScreen> {
  Session? _session;
  StreamSubscription<AuthState>? _auth;
  int _generation = 0;
  String? _routeNameOwner;

  @override
  void initState() {
    super.initState();
    _session = SupabaseService.client.auth.currentSession;
    _routeNameOwner = _session?.user.id;
    final initial = _session;
    var first = true;
    _auth = SupabaseService.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (first && identical(state.session, initial)) {
        first = false;
        return;
      }
      first = false;
      final sameLogin = state.session?.user.id == _session?.user.id &&
          (state.event == AuthChangeEvent.tokenRefreshed ||
              state.event == AuthChangeEvent.userUpdated);
      setState(() {
        _session = state.session;
        if (!sameLogin) ++_generation;
      });
    }, onError: (Object _) {
      if (mounted) {
        setState(() {
          _session = null;
          ++_generation;
        });
      }
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = _session?.user.id;
    final generation = _generation;
    final group = widget.groupId;
    if (owner == null) {
      return const Scaffold(
          body: Center(child: Text('Мессеж үзэхийн тулд нэвтэрнэ үү.')));
    }
    return _ScopedGroupThread(
        key: ValueKey((owner, group, generation)),
        accountId: owner,
        groupId: group,
        groupName: owner == _routeNameOwner ? widget.groupName : null,
        isCurrent: () =>
            mounted &&
            generation == _generation &&
            group == widget.groupId &&
            owner == SupabaseService.currentUser?.id &&
            identical(_session, SupabaseService.client.auth.currentSession));
  }
}

class _ScopedGroupThread extends StatefulWidget {
  final String accountId, groupId;
  final String? groupName;
  final bool Function() isCurrent;
  const _ScopedGroupThread(
      {super.key,
      required this.accountId,
      required this.groupId,
      this.groupName,
      required this.isCurrent});
  @override
  State<_ScopedGroupThread> createState() => _GroupThreadScreenState();
}

class _GroupThreadScreenState extends State<_ScopedGroupThread> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  /// Илгээх товчны идэвх — товчлуур бүрт мессежийн жагсаалтыг дахин зурахгүйн
  /// тулд зөвхөн send FAB энэ notifier-ийг сонсоно.
  final _canSend = ValueNotifier<bool>(false);
  List<Map<String, dynamic>> _msgs = [];
  Map<String, Map<String, dynamic>> _profiles = {}; // sender_id → profile
  bool _loading = true;
  bool _sending = false;
  bool _streamError = false; // realtime stream алдаа
  String? _name; // группийн нэр (query байхгүй бол refetch хийнэ)
  StreamSubscription? _sub;
  int _subscriptionVersion = 0;
  bool _memberActionBusy = false;

  String get _myId => widget.accountId;
  bool get _isCurrent => mounted && widget.isCurrent();
  void _back() => context.canPop() ? context.pop() : context.go('/dm');

  @override
  void initState() {
    super.initState();
    _name = widget.groupName;
    _fetchName();
    _ctrl.addListener(_syncCanSend);
    _loadMembers();
    _subscribe();
  }

  // Composer хоосон эсэхээс илгээх товчны төлөв хамаарна
  void _syncCanSend() =>
      _canSend.value = _isCurrent && _ctrl.text.trim().isNotEmpty;

  // Deep-link / reload үед name query байхгүй тул DB-ээс авна
  Future<void> _fetchName() async {
    final n = await GroupService.groupName(widget.groupId);
    if (_isCurrent && n != null) setState(() => _name = n);
  }

  Future<void> _loadMembers() async {
    final members = await GroupService.members(widget.groupId);
    if (_isCurrent) {
      setState(() {
        _profiles = {for (final m in members) m['id'] as String: m};
      });
    }
  }

  void _subscribe() {
    if (!mounted || !_isCurrent) return;
    final version = ++_subscriptionVersion;
    _sub = SupabaseService.client
        .from('group_messages')
        .stream(primaryKey: ['id'])
        .eq('group_id', widget.groupId)
        .order('created_at')
        .listen((data) {
          if (!_isCurrent || version != _subscriptionVersion) return;
          final msgs = data.cast<Map<String, dynamic>>().toList()
            ..sort((a, b) => (a['created_at'] as String? ?? '')
                .compareTo(b['created_at'] as String? ?? ''));
          final grew = msgs.length > _msgs.length;
          final wasNearBottom = _isNearBottom();
          setState(() {
            _msgs = msgs;
            _loading = false;
            _streamError = false;
          });
          // Дээшээ гүйлгэж уншиж байвал татахгүй — зөвхөн шинэ мессежид гүйлгэнэ
          if (grew && wasNearBottom) _scrollToBottom();
        }, onError: (e) {
          // Stream алдаа — мөнхийн spinner-ээс сэргийлж error төлөв рүү
          if (_isCurrent && version == _subscriptionVersion) {
            setState(() {
              _loading = false;
              _streamError = true;
            });
          }
        });
  }

  void _retrySubscribe() {
    if (!mounted || !_isCurrent) return;
    _sub?.cancel();
    setState(() {
      _loading = true;
      _streamError = false;
    });
    _subscribe();
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 120;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (!_isCurrent || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await GroupService.sendMessage(widget.groupId, text)
        .then<bool?>((result) => result)
        .timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (!mounted || !_isCurrent) return;
    if (ok == true) {
      _ctrl.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok == null
              ? 'Илгээсэн эсэхийг баталж чадсангүй. Давтан илгээхээс өмнө яриагаа шалгаарай.'
              : 'Илгээж чадсангүй. Дахин оролдоно уу.'),
          backgroundColor: AppColors.error));
    }
    setState(() => _sending = false);
  }

  // Гишүүдийн жагсаалт — нэмэх / гарах үйлдэлтэй
  void _showMembers() {
    if (!_isCurrent || _memberActionBusy) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetCtx) => StreamBuilder<AuthState>(
          stream: SupabaseService.client.auth.onAuthStateChange,
          builder: (_, __) => !_isCurrent
              ? const SafeArea(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Нэвтрэх хаяг өөрчлөгдсөн байна.')))
              : SafeArea(
                  child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 10),
                    Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.hairline,
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 14),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(children: [
                          Text('Гишүүд (${_profiles.length})',
                              style: AppTextStyles.labelLg),
                        ])),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.42),
                        child: ListView(shrinkWrap: true, children: [
                          for (final m in _profiles.values) _memberTile(m),
                        ])),
                    Divider(height: 1, color: AppColors.hairline),
                    ListTile(
                        leading: const SculptedIcon(
                            Icons.person_add_alt_1_outlined,
                            color: AppColors.accentStart,
                            size: 22),
                        title: Text('Гишүүн нэмэх',
                            style: AppTextStyles.bodyMd
                                .copyWith(color: AppColors.textPrimary)),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _addMembers();
                        }),
                    ListTile(
                        leading: const SculptedIcon(Icons.logout_rounded,
                            color: AppColors.error, size: 22),
                        title: Text('Группээс гарах',
                            style: AppTextStyles.bodyMd
                                .copyWith(color: AppColors.error)),
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _leaveGroup();
                        }),
                    const SizedBox(height: 8),
                  ]),
                ))),
    );
  }

  Widget _memberTile(Map<String, dynamic> m) {
    final uname = ((m['username'] as String?) ?? 'user').replaceAll('@', '');
    final isMe = m['id'] == _myId;
    return ListTile(
      leading: AppAvatar(
          imageUrl: m['avatar_url'] as String?,
          initial: uname.isNotEmpty ? uname[0].toUpperCase() : '?',
          size: 38),
      title: Text('@$uname',
          style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
      trailing: isMe
          ? Text('Та',
              style:
                  AppTextStyles.bodyXs.copyWith(color: AppColors.textTertiary))
          : null,
    );
  }

  Future<void> _addMembers() async {
    if (!_isCurrent || _memberActionBusy) return;
    setState(() => _memberActionBusy = true);
    final existing = _profiles.keys.toSet();
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _AddMemberSheet(
          existingIds: existing, ownerId: _myId, isCurrent: () => _isCurrent),
    );
    if (!mounted || !_isCurrent) return;
    if (picked == null || picked.isEmpty) {
      setState(() => _memberActionBusy = false);
      return;
    }
    final ok = await GroupService.addMembers(widget.groupId, picked)
        .then<bool?>((result) => result)
        .timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (!mounted || !_isCurrent) return;
    setState(() => _memberActionBusy = false);
    if (ok == true) {
      _loadMembers();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Гишүүн нэмэгдлээ'),
          backgroundColor: AppColors.bgElevated));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok == null
              ? 'Нэмэгдсэн эсэхийг баталж чадсангүй. Гишүүдийн жагсаалтаа дахин шалгаарай.'
              : 'Нэмж чадсангүй. Дахин оролдоно уу.'),
          backgroundColor: AppColors.error));
    }
  }

  Future<void> _leaveGroup() async {
    if (!_isCurrent || _memberActionBusy) return;
    setState(() => _memberActionBusy = true);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: Text('Группээс гарах уу?', style: AppTextStyles.labelLg),
        content: Text('Та энэ группээс гарна.',
            style:
                AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Болих',
                  style: AppTextStyles.btn
                      .copyWith(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Гарах',
                  style: AppTextStyles.btn.copyWith(color: AppColors.error))),
        ],
      ),
    );
    if (!mounted || !_isCurrent) return;
    if (confirm != true) {
      setState(() => _memberActionBusy = false);
      return;
    }
    final ok = await GroupService.leaveGroup(widget.groupId)
        .then<bool?>((result) => result)
        .timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (!mounted || !_isCurrent) return;
    setState(() => _memberActionBusy = false);
    if (ok == true) {
      _back();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok == null
              ? 'Группээс гарсан эсэхийг баталж чадсангүй. Жагсаалтаа дахин нээгээрэй.'
              : 'Гарч чадсангүй. Дахин оролдоно уу.'),
          backgroundColor: AppColors.error));
    }
  }

  @override
  void dispose() {
    ++_subscriptionVersion;
    _sub?.cancel();
    _ctrl.removeListener(_syncCanSend);
    _ctrl.dispose();
    _canSend.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBodyBehindAppBar: true,
      // DM thread-тэй ижил найрлага — доод булан 22 шилэн app bar
      appBar: _GroupGlassAppBar(
        height: chatToolbarHeight(context),
        name: _name ?? 'Групп',
        memberCount: _profiles.length,
        onBack: _back,
        onTapHeader: _showMembers,
      ),
      body: Stack(children: [
        // ── Aurora glow backdrop ──
        const Positioned.fill(child: _AuroraBackdrop()),
        Column(children: [
          Expanded(
              child: _loading
                  ? const _GroupSkeleton()
                  : _streamError
                      ? _GroupErrorState(onRetry: _retrySubscribe)
                      : _msgs.isEmpty
                          // Хоосон төлөв — апп даяарх нэгдсэн EmptyState (icon хувилбар)
                          ? const EmptyState(
                              icon: Icons.groups_rounded,
                              title: 'Мессеж алга байна',
                              subtitle: 'Группийн яриа эхлүүлээрэй!')
                          : ListView.builder(
                              controller: _scroll,
                              // Glass app bar-ын доороос эхэлж, гүйлгэхэд арын шилээр орно
                              padding: EdgeInsets.fromLTRB(
                                  20,
                                  MediaQuery.of(context).padding.top +
                                      chatToolbarHeight(context) +
                                      12,
                                  20,
                                  12),
                              itemCount: _msgs.length,
                              itemBuilder: (_, i) {
                                final m = _msgs[i];
                                final isMe = m['sender_id'] == _myId;
                                final sender = _profiles[m['sender_id']];
                                final uname =
                                    ((sender?['username'] as String?) ?? '...')
                                        .replaceAll('@', '');
                                final time = m['created_at'] as String?;
                                // Огнооны pill — өдөр солигдох мөрөнд
                                final showDate = i == 0 ||
                                    !_sameDay(time,
                                        _msgs[i - 1]['created_at'] as String?);
                                // Bubble GROUP — дараалсан ижил илгээгчийг нягт багцална
                                final nextSameDay = i < _msgs.length - 1 &&
                                    _sameDay(
                                        _msgs[i + 1]['created_at'] as String?,
                                        time);
                                final prevSame = !showDate &&
                                    _msgs[i - 1]['sender_id'] == m['sender_id'];
                                final nextSame = nextSameDay &&
                                    _msgs[i + 1]['sender_id'] == m['sender_id'];
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (showDate)
                                        Center(
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 12),
                                                child: _DateChip(
                                                    label: _dateLabel(time)))),
                                      Tooltip(
                                          message: isMe
                                              ? ''
                                              : 'Удаан дараад мессежийг мэдээлэх',
                                          child: Semantics(
                                              customSemanticsActions: isMe
                                                  ? null
                                                  : {
                                                      const CustomSemanticsAction(
                                                              label:
                                                                  'Мессежийг мэдээлэх'):
                                                          () => showReportSheet(
                                                              context,
                                                              targetType:
                                                                  'group_message',
                                                              targetId: m['id']
                                                                  as String),
                                                    },
                                              child: GestureDetector(
                                                  onLongPress: isMe
                                                      ? null
                                                      : () => showReportSheet(
                                                          context,
                                                          targetType:
                                                              'group_message',
                                                          targetId: m['id']
                                                              as String),
                                                  child: _GroupBubble(
                                                    text:
                                                        m['body'] as String? ??
                                                            '',
                                                    isMe: isMe,
                                                    // Нэр — зөвхөн группийн ЭХНИЙ bubble дээр
                                                    senderName:
                                                        (!isMe && !prevSame)
                                                            ? uname
                                                            : null,
                                                    senderInitial: uname
                                                            .isNotEmpty
                                                        ? uname[0].toUpperCase()
                                                        : '?',
                                                    avatarUrl:
                                                        sender?['avatar_url']
                                                            as String?,
                                                    isFirstInGroup: !prevSame,
                                                    isLastInGroup: !nextSame,
                                                    time: _timeStr(time),
                                                  )))),
                                    ]);
                              })),

          // ── Composer dock — дээд булан 28 шилэн панел: pill 52 + gradient FAB 44 ──
          Container(
              decoration: BoxDecoration(
                  color: AppColors.bgElevated.withValues(alpha: 0.9),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(top: BorderSide(color: AppColors.hairline2)),
                  boxShadow: AppColors.shadowDock),
              child: SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Шилэн pill — текст сунадаг, хүрээгүй TextField
                            Expanded(
                                child: Container(
                                    constraints:
                                        const BoxConstraints(minHeight: 52),
                                    decoration: BoxDecoration(
                                        color: AppColors.bgSurface
                                            .withValues(alpha: 0.7),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                            color: AppColors.hairline)),
                                    child: Row(children: [
                                      const SizedBox(width: 18),
                                      Expanded(
                                          child: TextField(
                                              controller: _ctrl,
                                              enabled: !_sending,
                                              maxLength: 4000,
                                              style: AppTextStyles.bodyMd
                                                  .copyWith(
                                                      color: AppColors
                                                          .textPrimary),
                                              textInputAction: TextInputAction
                                                  .send,
                                              cursorColor: AppColors.neonCyan,
                                              onSubmitted: (_) => _send(),
                                              decoration: InputDecoration(
                                                  counterText: '',
                                                  hintText: 'Мессеж бичих...',
                                                  hintStyle: AppTextStyles
                                                      .bodyMd
                                                      .copyWith(
                                                          color: AppColors
                                                              .textTertiary),
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 4,
                                                          vertical: 15),
                                                  isDense: true,
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none))),
                                      const SizedBox(width: 14),
                                    ]))),
                            const SizedBox(width: 10),
                            // SEND — gradient circle FAB 44 + glow.
                            // Composer хоосон үед: glow-гүй, бүдэг дүүргэлт, дарагдахгүй.
                            ValueListenableBuilder<bool>(
                                valueListenable: _canSend,
                                builder: (_, canSend, __) {
                                  final lit = canSend || _sending;
                                  return Semantics(
                                      button: true,
                                      enabled: canSend && !_sending,
                                      label: 'Мессеж илгээх',
                                      child: Tooltip(
                                          message: 'Мессеж илгээх',
                                          child: _ScaleTap(
                                            onTap: (canSend && !_sending)
                                                ? _send
                                                : null,
                                            child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 180),
                                                curve: Curves.easeOut,
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: lit
                                                        ? AppColors
                                                            .accentGradient
                                                        : null,
                                                    color: lit
                                                        ? null
                                                        : AppColors.bgSurface
                                                            .withValues(
                                                                alpha: 0.7),
                                                    border: lit
                                                        ? null
                                                        : Border.all(
                                                            color: AppColors
                                                                .hairline),
                                                    boxShadow: lit
                                                        ? AppColors.glowShadow(AppColors.accentStart,
                                                            alpha: 0.45,
                                                            blur: 18,
                                                            offset:
                                                                const Offset(
                                                                    0, 8))
                                                        : null),
                                                child: _sending
                                                    ? const Padding(
                                                        padding: EdgeInsets.all(12),
                                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                                    : SculptedIcon(Icons.send_rounded, color: lit ? Colors.white : AppColors.textTertiary, size: 19, active: lit, onDark: lit)),
                                          )));
                                }),
                          ])))),
        ]),
      ]),
    );
  }

  // created_at нь UTC — орон нутгийн огноогоор бүлэглэнэ
  bool _sameDay(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.parse(a).toLocal();
    final db = DateTime.parse(b).toLocal();
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  String _dateLabel(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    bool sameLocal(DateTime x, DateTime y) =>
        x.year == y.year && x.month == y.month && x.day == y.day;
    if (sameLocal(d, now)) return 'Өнөөдөр';
    if (sameLocal(d, now.subtract(const Duration(days: 1)))) return 'Өчигдөр';
    return '${d.month}/${d.day}';
  }

  String _timeStr(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _GroupBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String? senderName; // зөвхөн бүлгийн эхний мессежид
  final String senderInitial;
  final String? avatarUrl;
  // Bubble GROUP байрлал — radius, зай, avatar, цаг эндээс шалтгаална
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final String time;
  const _GroupBubble({
    required this.text,
    required this.isMe,
    required this.time,
    this.senderName,
    this.senderInitial = '?',
    this.avatarUrl,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
  });

  // Группийн байрлалаас хамаарсан radius — зөвхөн сүүлийнх нь "сүүл"-тэй
  BorderRadius get _radius {
    const r = Radius.circular(18);
    const mid = Radius.circular(6);
    const tail = Radius.circular(4);
    if (isMe) {
      return BorderRadius.only(
          topLeft: r,
          bottomLeft: r,
          topRight: isFirstInGroup ? r : mid,
          bottomRight: isLastInGroup ? tail : mid);
    }
    return BorderRadius.only(
        topRight: r,
        bottomRight: r,
        topLeft: isFirstInGroup ? r : mid,
        bottomLeft: isLastInGroup ? tail : mid);
  }

  @override
  Widget build(BuildContext context) {
    // Минийх — accent gradient (зөөлөн ~0.9) + glow; тэднийх — glass surface
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * kBubbleMaxWidthFactor),
      decoration: BoxDecoration(
          gradient: isMe ? AppColors.accentGradient.scale(0.9) : null,
          color: isMe ? null : AppColors.bgElevated.withValues(alpha: 0.8),
          border: isMe ? null : Border.all(color: AppColors.hairline),
          boxShadow: isMe
              ? [
                  BoxShadow(
                      color: AppColors.accentEnd.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: -2,
                      offset: const Offset(0, 6)),
                ]
              : null,
          borderRadius: _radius),
      child: Text(text,
          style: AppTextStyles.bodyMd
              .copyWith(color: isMe ? Colors.white : AppColors.textPrimary)),
    );

    // Партнёрын мөр: группийн СҮҮЛИЙН bubble дээр л avatar 28 харагдана
    final row = isMe
        ? Align(alignment: Alignment.centerRight, child: bubble)
        : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (isLastInGroup)
              AppAvatar(imageUrl: avatarUrl, initial: senderInitial, size: 28)
            else
              const SizedBox(width: 28),
            const SizedBox(width: 8),
            Flexible(
                child: Align(alignment: Alignment.centerLeft, child: bubble)),
          ]);

    return Padding(
      // Ижил илгээгчийн дараалсан bubble-ууд 2px-ээр нягтарна
      padding: EdgeInsets.only(bottom: isLastInGroup ? 10 : 2),
      child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (senderName != null)
              Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 3),
                  // Илгээгчийн нэр — группийн ЭХНИЙ bubble дээр (cyan micro)
                  child: Text('@$senderName',
                      style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.neonCyan,
                          fontWeight: FontWeight.w700))),
            row,
            // Цаг (micro) — зөвхөн группийн сүүлийн bubble дор
            if (isLastInGroup)
              Padding(
                  padding: EdgeInsets.only(
                      top: 3, left: isMe ? 0 : 42, right: isMe ? 6 : 0),
                  child: Text(time,
                      style: AppTextStyles.bodyXs
                          .copyWith(color: AppColors.textSecondary))),
          ]),
    );
  }
}

// ── Огнооны шилэн pill (Өнөөдөр / Өчигдөр / M/D) ──
class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip({required this.label});
  @override
  Widget build(BuildContext context) {
    // Web perf — BackdropFilter-гүй glass chip
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
          color: AppColors.bgElevated.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline)),
      child: Text(label,
          style:
              AppTextStyles.labelSm.copyWith(color: AppColors.textSecondary)),
    );
  }
}

// ── Шилэн групп app bar — back circle · gradient групп avatar 42 · нэр + гишүүд micro ──
class _GroupGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final double height;
  final String name;
  final int memberCount;
  final VoidCallback onBack;
  final VoidCallback onTapHeader;
  const _GroupGlassAppBar(
      {required this.height,
      required this.name,
      required this.memberCount,
      required this.onBack,
      required this.onTapHeader});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    // Web perf — BackdropFilter-гүй glass (өндөр alpha-аар)
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
      child: Container(
          padding: EdgeInsets.fromLTRB(12, topPad + 6, 10, 8),
          decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.92),
              border: Border(bottom: BorderSide(color: AppColors.hairline2))),
          child: Row(children: [
            // Буцах — апп даяар нэг л хэлбэр (GlassIconButton)
            GlassIconButton(
                icon: Icons.chevron_left_rounded,
                iconSize: 24,
                tooltip: 'Буцах',
                onTap: onBack),
            const SizedBox(width: 6),
            Expanded(
                child: _HeaderTap(
                    onTap: onTapHeader,
                    child: Row(children: [
                      Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.accentGradient,
                              boxShadow: AppColors.glowShadow(
                                  AppColors.accentStart,
                                  blur: 12,
                                  offset: const Offset(0, 3))),
                          child: const SculptedIcon(Icons.groups_rounded,
                              color: Colors.white, size: 21, onDark: true)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.h2.copyWith(height: 1.2)),
                            const SizedBox(height: 2),
                            Text('$memberCount гишүүн · харах',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyXs.copyWith(
                                    color: AppColors.textTertiary,
                                    height: 1.2,
                                    fontWeight: FontWeight.w600)),
                          ])),
                    ]))),
            const SizedBox(width: 4),
            const ThemeToggleButton(),
            const SizedBox(width: 4),
            GlassIconButton(
                icon: Icons.people_alt_outlined,
                iconSize: 19,
                tooltip: 'Гишүүд',
                onTap: onTapHeader),
          ])),
    );
  }
}

// ── Aurora glow backdrop (radial cyan/magenta wash on void) ──
class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.bgBase),
      child: Stack(children: [
        Positioned(
            top: -40,
            right: -30,
            child: _glow(220, AppColors.accentPurple.withValues(alpha: 0.18))),
        Positioned(
            bottom: -60,
            left: -40,
            child: _glow(240, AppColors.neonCyan.withValues(alpha: 0.10))),
      ]),
    );
  }

  Widget _glow(double size, Color c) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, Colors.transparent]),
        ),
      );
}

// ── App bar гарчиг дээр hover cursor нэмэх wrapper ──
class _HeaderTap extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _HeaderTap({required this.child, required this.onTap});
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
            onTap: onTap, behavior: HitTestBehavior.opaque, child: child),
      );
}

// ── Web hover + дарахад агших tap wrapper (локал) ──
class _ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _ScaleTap({required this.child, this.onTap});
  @override
  State<_ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<_ScaleTap> {
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
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Групп ачааллах skeleton ──
class _GroupSkeleton extends StatefulWidget {
  const _GroupSkeleton();
  @override
  State<_GroupSkeleton> createState() => _GroupSkeletonState();
}

class _GroupSkeletonState extends State<_GroupSkeleton>
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
    final w = MediaQuery.of(context).size.width;
    return FadeTransition(
      opacity: _c,
      child: ListView(
        // Glass app bar-ын доороос эхэлнэ
        padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top +
                chatToolbarHeight(context) +
                16,
            20,
            12),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 7; i++)
            Align(
                alignment:
                    i.isEven ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 38,
                  width: w * (0.32 + (i % 3) * 0.12),
                  decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(16)),
                )),
        ],
      ),
    );
  }
}

// ── Realtime stream алдаа — retry ──
class _GroupErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _GroupErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        SculptedIcon(Icons.wifi_off_rounded,
            color: AppColors.textTertiary, size: 44),
        const SizedBox(height: 12),
        Text('Мессеж ачаалж чадсангүй',
            style:
                AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        // Нэгдсэн primary CTA — GradientButton (md)
        GradientButton(
            label: 'Дахин оролдох',
            onPressed: onRetry,
            size: GradientButtonSize.md,
            fullWidth: false),
      ]));
}

/// Группд гишүүн нэмэх sheet — debounce хайлт + сонголт → id жагсаалт буцаана
class _AddMemberSheet extends StatefulWidget {
  final Set<String> existingIds;
  final String ownerId;
  final bool Function() isCurrent;
  const _AddMemberSheet(
      {required this.existingIds,
      required this.ownerId,
      required this.isCurrent});
  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  final Map<String, Map<String, dynamic>> _selected = {};
  bool _loading = false;
  bool _failed = false;
  Timer? _debounce;
  int _reqSeq = 0; // stale-response race-ээс сэргийлэх дараалал

  String get _myId => widget.ownerId;
  bool get _active => mounted && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _search('');
  }

  void _onChanged(String q) {
    if (!_active) return;
    _debounce?.cancel();
    ++_reqSeq;
    setState(() {
      _results = [];
      _loading = true;
      _failed = false;
    });
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (!_active) return;
    final seq = ++_reqSeq;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      var query = SupabaseService.client
          .from('profiles')
          .select('id, username, avatar_url')
          .neq('id', _myId);
      final term = q
          .trim()
          .replaceAll(RegExp(r'[%*]'), '')
          .replaceAll(r'\', r'\\')
          .replaceAll('_', r'\_');
      if (q.trim().isNotEmpty && term.isEmpty) {
        setState(() {
          _results = [];
          _loading = false;
        });
        return;
      }
      if (term.isNotEmpty) query = query.ilike('username', '%$term%');
      final rows = await query.limit(30).timeout(const Duration(seconds: 15));
      if (!_active || seq != _reqSeq) return;
      setState(() {
        _results = (rows as List)
            .cast<Map<String, dynamic>>()
            .where((u) => !widget.existingIds.contains(u['id']))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!_active || seq != _reqSeq) return;
      setState(() {
        _results = [];
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
        stream: SupabaseService.client.auth.onAuthStateChange,
        builder: (_, __) => !_active
            ? const SafeArea(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Нэвтрэх хаяг өөрчлөгдсөн байна.')))
            : Padding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: Column(children: [
                    const SizedBox(height: 12),
                    Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.hairline2,
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 14),
                    Text('Гишүүн нэмэх', style: AppTextStyles.h2),
                    const SizedBox(height: 12),
                    // Хайлт — апп даяарх нэгдсэн шилэн pill талбар (48)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: SearchField(
                            controller: _searchCtrl,
                            onChanged: _onChanged,
                            hint: 'Хэрэглэгч хайх...')),
                    Expanded(
                        child: _loading && _results.isEmpty
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.accentStart,
                                    strokeWidth: 2))
                            : _failed
                                ? Center(
                                    child: TextButton(
                                        onPressed: () =>
                                            _search(_searchCtrl.text),
                                        child: const Text(
                                            'Хайж чадсангүй. Дахин оролдох')))
                                : _results.isEmpty
                                    ? Center(
                                        child: Text('Хэрэглэгч олдсонгүй',
                                            style: AppTextStyles.bodyMd
                                                .copyWith(
                                                    color: AppColors
                                                        .textSecondary)))
                                    : ListView.builder(
                                        itemCount: _results.length,
                                        itemBuilder: (_, i) {
                                          final u = _results[i];
                                          final id = u['id'] as String;
                                          final uname =
                                              (u['username'] as String? ??
                                                      'user')
                                                  .replaceAll('@', '');
                                          final sel = _selected.containsKey(id);
                                          return ListTile(
                                            onTap: () {
                                              if (!_active) return;
                                              setState(() => sel
                                                  ? _selected.remove(id)
                                                  : _selected[id] = u);
                                            },
                                            leading: AppAvatar(
                                                imageUrl:
                                                    u['avatar_url'] as String?,
                                                initial: uname.isNotEmpty
                                                    ? uname[0].toUpperCase()
                                                    : '?',
                                                size: 40),
                                            title: Text('@$uname',
                                                style: AppTextStyles.labelMd
                                                    .copyWith(
                                                        color: AppColors
                                                            .textPrimary)),
                                            trailing: Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: sel
                                                        ? AppColors
                                                            .accentGradient
                                                        : null,
                                                    border: sel
                                                        ? null
                                                        : Border.all(
                                                            color: AppColors
                                                                .hairline2,
                                                            width: 1.5)),
                                                child: sel
                                                    ? const SculptedIcon(
                                                        Icons.check,
                                                        size: 15,
                                                        color: Colors.white,
                                                        onDark: true)
                                                    : null),
                                          );
                                        })),
                    SafeArea(
                        top: false,
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                            child: _ScaleTap(
                                onTap: _selected.isEmpty
                                    ? null
                                    : () {
                                        if (_active) {
                                          Navigator.pop(
                                              context, _selected.keys.toList());
                                        }
                                      },
                                // Primary товч — pill 52 + gradient glow
                                child: Container(
                                    height: 52,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                        gradient: _selected.isEmpty
                                            ? null
                                            : AppColors.accentGradient,
                                        color: _selected.isEmpty
                                            ? AppColors.bgSurface
                                            : null,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        boxShadow: _selected.isEmpty
                                            ? null
                                            : AppColors.glowShadow(
                                                AppColors.accentStart)),
                                    alignment: Alignment.center,
                                    child: Text(
                                        _selected.isEmpty
                                            ? 'Хэрэглэгч сонгоно уу'
                                            : 'Нэмэх (${_selected.length})',
                                        style: AppTextStyles.btn.copyWith(
                                            color: _selected.isEmpty
                                                ? AppColors.textTertiary
                                                : Colors.white)))))),
                  ]),
                ),
              ));
  }
}
