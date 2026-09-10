import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/glass_icon_button.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/stickers.dart';
import '../widgets/chat_tokens.dart';

class DmThreadScreen extends StatefulWidget {
  final String threadId; // partner's user_id
  final String? replyNote; // note-д хариулж байгаа бол түүний текст
  const DmThreadScreen({super.key, required this.threadId, this.replyNote});
  @override State<DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends State<DmThreadScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  /// Илгээх товчны идэвх — товчлуур бүрт бүх дэлгэцийг setState хийхгүйн тулд
  /// зөвхөн энэ notifier дээр сонсогч (send FAB) дахин зурагдана.
  final _canSend = ValueNotifier<bool>(false);

  List<Map<String, dynamic>> _msgs = [];
  Map<String, dynamic>? _partner;
  bool _loading = true;
  bool _sending = false;
  bool _showEmoji = false;
  bool _streamError = false; // realtime stream алдаа гарсан эсэх
  bool _firstLoad = true;    // stream-ийн анхны emission эсэх (анх нээхэд уншсан болгоно)
  bool _markedUnread = false; // хэрэглэгч гараар "уншаагүй" болгосон — авто-read түр зогсооно
  String _emojiTab = 'emoji'; // 'emoji' | 'sticker'

  StreamSubscription? _sub;
  String? _pendingNote; // note-д хариулж байгаа эсэх

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    final n = widget.replyNote?.trim();
    if (n != null && n.isNotEmpty) _pendingNote = n;
    _ctrl.addListener(_syncCanSend);
    _loadPartner();
    _subscribe();
  }

  // Composer хоосон эсэхээс илгээх товчны төлөв хамаарна
  void _syncCanSend() => _canSend.value = _ctrl.text.trim().isNotEmpty;

  Future<void> _loadPartner() async {
    try {
      final p = await SupabaseService.client
          .from('profiles')
          .select('id, username, avatar_url, last_seen_at')
          .eq('id', widget.threadId)
          .maybeSingle();
      if (mounted) setState(() => _partner = p);
    } catch (_) {}
  }

  void _subscribe() {
    final me = _myId;
    // conversation_id-р scope — бүх messages хүснэгтийг sub хийхгүй
    final cid = ([me, widget.threadId]..sort()).join('_');
    _sub = SupabaseService.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', cid)
        .order('created_at')
        .listen((data) {
          if (!mounted) return;
          final msgs = (data as List).cast<Map<String, dynamic>>().toList()
            ..sort((a, b) => (a['created_at'] as String? ?? '')
                .compareTo(b['created_at'] as String? ?? ''));
          final prevLen = _msgs.length;
          final wasNearBottom = _isNearBottom();
          final grew = msgs.length > prevLen;
          final newestMine = msgs.isNotEmpty &&
              msgs.last['sender_id'] == me;
          final incomingNew = grew && !newestMine; // партнёроос ШИНЭ мессеж
          // Партнёроос шинэ мессеж ирвэл "уншаагүй" төлөв дуусна
          if (incomingNew) _markedUnread = false;
          setState(() { _msgs = msgs; _loading = false; _streamError = false; });
          // Уншиж байх үед (дээшээ гүйлгэсэн) read-receipt эсвэл ирсэн мессеж
          // хэрэглэгчийг доош "татахгүй" — зөвхөн шинэ мессеж нэмэгдсэн бөгөөд
          // хэрэглэгч аль хэдийн доор байгаа, эсвэл шинэ мессеж минийх бол гүйлгэнэ.
          if (grew && (wasNearBottom || newestMine)) _scrollToBottom();
          // Уншсан болгох: зөвхөн анх нээхэд ЭСВЭЛ партнёроос шинэ мессеж ирэхэд.
          // Гараар "уншаагүй болгосон" бол stream-ийн UPDATE эргэж уншсан болгодог
          // байсныг зогсоов (шинэ мессеж иртэл, эсвэл дахин нээх хүртэл хэвээр).
          if (!_markedUnread && (_firstLoad || incomingNew)) _markRead();
          _firstLoad = false;
        }, onError: (e) {
          // Stream алдаа — мөнхийн spinner-ээс сэргийлж error төлөв рүү шилжинэ
          if (mounted) setState(() { _loading = false; _streamError = true; });
        });
  }

  void _retrySubscribe() {
    _sub?.cancel();
    setState(() { _loading = true; _streamError = false; });
    _subscribe();
  }

  // Хэрэглэгч жагсаалтын доод хэсэгт (уншиж дуусаад) байгаа эсэх
  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 120;
  }

  /// Сүүлийн 2 минутад идэвхтэй байсан бол online гэж үзнэ
  bool get _partnerOnline {
    final iso = _partner?['last_seen_at'] as String?;
    if (iso == null) return false;
    final t = DateTime.tryParse(iso);
    if (t == null) return false;
    return DateTime.now().toUtc().difference(t.toUtc()).inMinutes < 2;
  }

  /// Offline үед "сүүлд идэвхтэй Xм өмнө" гэх мэт бичвэр
  String get _presenceLabel {
    final iso = _partner?['last_seen_at'] as String?;
    if (iso == null) return 'офлайн';
    final t = DateTime.tryParse(iso);
    if (t == null) return 'офлайн';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 2) return 'онлайн';
    if (d.inMinutes < 60) return 'сүүлд идэвхтэй ${d.inMinutes}м өмнө';
    if (d.inHours < 24) return 'сүүлд идэвхтэй ${d.inHours}ц өмнө';
    return 'сүүлд идэвхтэй ${d.inDays}ө өмнө';
  }

  // Партнёроос ирсэн мессежийг "уншсан" болгож тэмдэглэнэ
  Future<void> _markRead() async {
    final me = _myId;
    if (me.isEmpty) return;
    try {
      await SupabaseService.client
          .from('messages')
          .update({'is_read': true})
          .eq('sender_id', widget.threadId)
          .eq('receiver_id', me)
          .eq('is_read', false);
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  // Партнёрын мессежийг "уншаагүй" болгоно (жагсаалт руу буцахад тодрох)
  Future<void> _markUnread() async {
    final me = _myId;
    if (me.isEmpty) return;
    _markedUnread = true; // stream-ийн авто-read-ийг зогсооно (доор эргэж уншуулахгүй)
    try {
      await SupabaseService.client
          .from('messages')
          .update({'is_read': false})
          .eq('sender_id', widget.threadId)
          .eq('receiver_id', me);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Уншаагүй болголоо'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2)));
      }
    } catch (_) {
      _markedUnread = false; // амжилтгүй — авто-read-ийг дахин зөвшөөрнө
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Амжилтгүй боллоо. Дахин оролдоно уу.'),
          backgroundColor: AppColors.error));
      }
    }
  }

  // App bar-ийн ⋮ товч — Профайл / Уншаагүй болгох
  void _showThreadOptions() {
    final username = (_partner?['username'] as String? ?? 'User')
        .replaceAll('@', '');
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
              Text(username, style: AppTextStyles.labelLg)])),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.person_outline,
              color: AppColors.textSecondary, size: 22),
            title: Text('Профайл харах', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(sheetCtx);
              context.push('/creator/${widget.threadId}');
            }),
          ListTile(
            leading: const Icon(Icons.mark_chat_unread_outlined,
              color: AppColors.textSecondary, size: 22),
            title: Text('Уншаагүй болгох', style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textPrimary)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              await _markUnread();
            }),
          const SizedBox(height: 12),
        ])),
    );
  }

  Future<void> _send() => _sendText(_ctrl.text);

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    final noteRef = _pendingNote; // эхний мессежид л note ишлэлийг хавсаргана
    setState(() { _sending = true; _pendingNote = null; });
    try {
      await SupabaseService.client.from('messages').insert({
        'sender_id':   _myId,
        'receiver_id': widget.threadId,
        'body':        text,
        'is_read':     false,
        if (noteRef != null) 'note_text': noteRef,
      });
    } catch (_) {
      // Илгээж чадаагүй — текст + note ишлэлийг сэргээж, мэдэгдэнэ
      if (mounted) {
        _ctrl.text = text;
        setState(() => _pendingNote = noteRef);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Илгээж чадсангүй. Дахин оролдоно уу.'),
          backgroundColor: AppColors.error));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  void _onEmojiTap(String e) {
    if (_emojiTab == 'sticker' || _emojiTab == 'owl') {
      _sendText(e);            // sticker → шууд илгээх
    } else {
      _ctrl.text += e;         // emoji → текстэд нэмэх
      _ctrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _ctrl.text.length));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.removeListener(_syncCanSend);
    _ctrl.dispose();
    _canSend.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username  = _partner?['username'] as String? ?? 'User';
    final avatarUrl = _partner?['avatar_url'] as String?;
    final initial   = username.replaceAll('@','').isNotEmpty
        ? username.replaceAll('@','')[0].toUpperCase() : '?';
    // Өөрийн илгээсэн хамгийн сүүлийн мессеж (түүн дор "Үзсэн" харуулна)
    final lastMineIdx = _msgs.lastIndexWhere((m) => m['sender_id'] == _myId);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      extendBodyBehindAppBar: true,
      appBar: _GlassAppBar(
        username: username,
        avatarUrl: avatarUrl,
        initial: initial,
        online: _partnerOnline,
        presenceLabel: _presenceLabel,
        onBack: () => context.pop(),
        onTapPeer: () => context.push('/creator/${widget.threadId}'),
        onMore: _showThreadOptions,
      ),
      body: Stack(children: [
        // ── Aurora glow backdrop ──
        const Positioned.fill(child: _AuroraBackdrop()),
        Column(children: [
          Expanded(child: _loading
            ? const _ThreadSkeleton()
            : _streamError
              ? _ThreadErrorState(onRetry: _retrySubscribe)
              : _msgs.isEmpty
                // Хоосон thread — profile hero 96 + presence шилэн pill
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppAvatar(imageUrl: avatarUrl, initial: initial,
                      size: 96, showRing: true, showOnlineDot: _partnerOnline),
                    const SizedBox(height: 16),
                    Text(username, style: AppTextStyles.h1),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.bgElevated.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.hairline)),
                      child: Text(_presenceLabel,
                        style: AppTextStyles.bodyXs.copyWith(
                          color: _partnerOnline
                              ? AppColors.lime : AppColors.textSecondary,
                          fontWeight: FontWeight.w600))),
                    const SizedBox(height: 12),
                    Text('Яриа эхлүүлээрэй!',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary)),
                  ]))
                : ListView.builder(
                    controller: _scroll,
                    // Дээд padding — glass app bar-ын доор эхэлж, гүйлгэхэд
                    // мессежүүд bar-ын АРААР шилжин орно
                    padding: EdgeInsets.fromLTRB(20,
                        MediaQuery.of(context).padding.top + 76, 20, 12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m    = _msgs[i];
                      final isMe = m['sender_id'] == _myId;
                      final text = m['body'] as String? ?? '';
                      final time = m['created_at'] as String?;
                      // Date separator
                      final showDate = i == 0 ||
                          !_sameDay(time, _msgs[i-1]['created_at'] as String?);
                      // Bubble GROUP — дараалсан ижил илгээгчийн мессежүүдийг
                      // нягт багцална (өдөр солигдоход групп таслагдана)
                      final nextSameDay = i < _msgs.length - 1 &&
                          _sameDay(_msgs[i+1]['created_at'] as String?, time);
                      final prevSame = !showDate &&
                          _msgs[i-1]['sender_id'] == m['sender_id'];
                      final nextSame = nextSameDay &&
                          _msgs[i+1]['sender_id'] == m['sender_id'];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDate)
                            Center(child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _DateChip(label: _dateLabel(time)))),
                          _Bubble(text: text, isMe: isMe, time: _timeStr(time),
                            storyMediaUrl: m['story_media_url'] as String?,
                            noteText: m['note_text'] as String?,
                            isFirstInGroup: !prevSame,
                            isLastInGroup: !nextSame,
                            avatarUrl: avatarUrl,
                            senderInitial: initial),
                          // "Үзсэн" — зөвхөн өөрийн сүүлийн мессеж уншигдсан үед
                          if (isMe && i == lastMineIdx && (m['is_read'] == true))
                            Padding(
                              padding: const EdgeInsets.only(right: 4, bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Icon(Icons.done_all_rounded,
                                    size: 14, color: AppColors.neonCyan),
                                  const SizedBox(width: 4),
                                  Text('Үзсэн', style: AppTextStyles.bodyXs.copyWith(
                                    color: AppColors.neonCyan,
                                    fontWeight: FontWeight.w600)),
                                ])),
                        ]);
                    })),

          // ── Composer dock — дээд булан 28 шилэн панел (note ишлэл + input + emoji нэг дор) ──
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgElevated.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: const Border(top: BorderSide(color: AppColors.hairline2)),
              boxShadow: AppColors.shadowDock),
            child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            // Note-д хариулж байгаа бол ишлэл харуулна
            if (_pendingNote != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline)),
                child: Row(children: [
                  Container(width: 3, height: 32,
                    decoration: BoxDecoration(color: AppColors.neonCyan,
                      borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$username-ийн note-д хариулж байна',
                        style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.neonCyan, fontWeight: FontWeight.w600)),
                      Text(_pendingNote!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyXs.copyWith(
                          color: AppColors.textSecondary)),
                    ])),
                  GestureDetector(
                    onTap: () => setState(() => _pendingNote = null),
                    child: const Icon(Icons.close, size: 18,
                      color: AppColors.textTertiary)),
                ]),
              ),
            // ── Messenger input: шилэн pill 52 + тусдаа gradient send FAB 44 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Шилэн pill — зүүн талд emoji toggle, текст сунадаг
                  Expanded(child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.hairline)),
                    child: Row(children: [
                      const SizedBox(width: 4),
                      // Emoji/sticker панел toggle (нээлттэй үед keyboard icon)
                      IconButton(
                        onPressed: () => setState(() => _showEmoji = !_showEmoji),
                        tooltip: 'Emoji / Sticker',
                        icon: Icon(
                          _showEmoji
                              ? Icons.keyboard_outlined
                              : Icons.emoji_emotions_outlined,
                          size: 22,
                          color: _showEmoji
                              ? AppColors.neonCyan
                              : AppColors.textSecondary)),
                      Expanded(child: TextField(
                        controller: _ctrl,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: AppColors.textPrimary),
                        textInputAction: TextInputAction.send,
                        cursorColor: AppColors.neonCyan,
                        onTap: () { if (_showEmoji) setState(() => _showEmoji = false); },
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Мессеж бичих…',
                          hintStyle: AppTextStyles.bodyMd.copyWith(
                            color: AppColors.textTertiary),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 15),
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none))),
                      const SizedBox(width: 14),
                    ]),
                  )),
                  const SizedBox(width: 10),
                  // SEND — gradient circle FAB 44 + glow, дарахад агшина.
                  // Composer хоосон үед: glow-гүй, бүдэг дүүргэлт, дарагдахгүй.
                  ValueListenableBuilder<bool>(
                    valueListenable: _canSend,
                    builder: (_, canSend, __) {
                      final lit = canSend || _sending;
                      return _ScaleTap(
                        onTap: (canSend && !_sending) ? _send : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: lit ? AppColors.accentGradient : null,
                            color: lit
                                ? null
                                : AppColors.bgSurface.withValues(alpha: 0.7),
                            border: lit
                                ? null
                                : Border.all(color: AppColors.hairline),
                            boxShadow: lit
                                ? AppColors.glowShadow(AppColors.accentStart,
                                    alpha: 0.45, blur: 18,
                                    offset: const Offset(0, 8))
                                : null),
                          child: _sending
                            ? const Padding(padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                            : Icon(Icons.send_rounded,
                                color: lit
                                    ? Colors.white : AppColors.textTertiary,
                                size: 19)),
                      );
                    }),
                ]),
            ),
            if (_showEmoji) _buildEmojiPanel(),
          ]))),
        ]),
      ]),
    );
  }

  // created_at нь UTC — орон нутгийн (UB, UTC+8) огноогоор бүлэглэнэ.
  // Эс тэгвээс шөнө 00:00–08:00-д илгээсэн мессежүүд өмнөх өдөрт бүлэглэгддэг.
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
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildEmojiPanel() {
    final isSticker = _emojiTab == 'sticker';
    final isOwl     = _emojiTab == 'owl';
    final items     = isSticker ? _kStickers : _kEmojis;
    return Container(
      height: 240,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Row(children: [
          _emojiTabBtn('emoji',   'Emoji'),
          _emojiTabBtn('sticker', 'Sticker'),
          _emojiTabBtn('owl',     '🦉 Owl'),
        ]),
        const Divider(height: 1, color: AppColors.hairline),
        Expanded(child: isOwl
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in kOwlStickers)
                  _ScaleTap(
                    onTap: () => _onEmojiTap(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(16)),
                      child: Text(s, style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                  ),
              ]))
          : GridView.count(
              crossAxisCount: isSticker ? 5 : 8,
              padding: const EdgeInsets.all(8),
              children: [
                for (final e in items)
                  _ScaleTap(
                    onTap: () => _onEmojiTap(e),
                    child: Center(child: Text(e,
                      style: TextStyle(fontSize: isSticker ? 40 : 26))),
                  ),
              ],
            )),
      ]),
    );
  }

  Widget _emojiTabBtn(String key, String label) {
    final active = _emojiTab == key;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _emojiTab = key),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(
          color: active ? AppColors.neonCyan : Colors.transparent, width: 2))),
        child: Center(child: Text(label, style: AppTextStyles.bodyMd.copyWith(
          color: active ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
      )));
  }
}

// ── Glass app bar (chevron back · neon-ring avatar w/ live dot · name + 'онлайн' · phone/video/more) ──
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String username;
  final String? avatarUrl;
  final String initial;
  final bool online;
  final String presenceLabel;
  final VoidCallback onBack;
  final VoidCallback onTapPeer;
  final VoidCallback onMore;
  const _GlassAppBar({
    required this.username,
    required this.avatarUrl,
    required this.initial,
    required this.online,
    required this.presenceLabel,
    required this.onBack,
    required this.onTapPeer,
    required this.onMore,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Тун удахгүй'),
      duration: Duration(milliseconds: 1400),
      backgroundColor: AppColors.bgElevated));
  }

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
            border: const Border(
              bottom: BorderSide(color: AppColors.hairline2)),
          ),
          child: Row(children: [
            // round glass back button — апп даяар нэг л хэлбэр
            GlassIconButton(
              icon: Icons.chevron_left_rounded,
              iconSize: 24,
              tooltip: 'Буцах',
              onTap: onBack,
            ),
            const SizedBox(width: 6),
            // avatar in neon ring + жинхэнэ presence-ээр цэг
            GestureDetector(
              onTap: onTapPeer,
              child: AppAvatar(
                imageUrl: avatarUrl, initial: initial,
                size: 42, showRing: true, showOnlineDot: online),
            ),
            const SizedBox(width: 10),
            // name + presence sub (жинхэнэ last_seen_at-аас)
            Expanded(child: GestureDetector(
              onTap: onTapPeer,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(username,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.h2),
                  const SizedBox(height: 2),
                  Row(children: [
                    if (online) ...[
                      Container(width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.lime, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Flexible(child: Text(presenceLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyXs.copyWith(
                        color: online ? AppColors.lime : AppColors.textTertiary,
                        fontWeight: FontWeight.w600))),
                  ]),
                ]),
            )),
            // right glass round buttons — дуудлага/видео "тун удахгүй", ⋮ идэвхтэй
            GlassIconButton(icon: Icons.call, iconSize: 18,
              tooltip: 'Дуудлага', onTap: () => _soon(context)),
            const SizedBox(width: 2),
            GlassIconButton(icon: Icons.videocam_outlined, iconSize: 20,
              tooltip: 'Видео дуудлага', onTap: () => _soon(context)),
            const SizedBox(width: 2),
            GlassIconButton(icon: Icons.more_vert, iconSize: 20,
              tooltip: 'Бусад', onTap: onMore),
          ]),
      ),
    );
  }
}

// ── Web дээр hover cursor + дарахад агших tap wrapper (локал) ──
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

// ── Thread ачааллах skeleton — ээлжлэн зүүн/баруун bubble хэлбэрүүд ──
class _ThreadSkeleton extends StatefulWidget {
  const _ThreadSkeleton();
  @override
  State<_ThreadSkeleton> createState() => _ThreadSkeletonState();
}

class _ThreadSkeletonState extends State<_ThreadSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 700),
    lowerBound: 0.4, upperBound: 1.0)..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return FadeTransition(
      opacity: _c,
      child: ListView(
        // Glass app bar-ын доороос эхэлнэ
        padding: EdgeInsets.fromLTRB(20,
            MediaQuery.of(context).padding.top + 80, 20, 12),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 7; i++)
            Align(
              alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                height: 40,
                width: w * (0.35 + (i % 3) * 0.12),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(18)),
              )),
        ],
      ),
    );
  }
}

// ── Realtime stream алдаа — retry товчтой ──
class _ThreadErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ThreadErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, color: AppColors.textTertiary, size: 44),
      const SizedBox(height: 12),
      Text('Мессеж ачаалж чадсангүй', style: AppTextStyles.bodyMd.copyWith(
        color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      // Нэгдсэн primary CTA — GradientButton (md)
      GradientButton(
        label: 'Дахин оролдох',
        onPressed: onRetry,
        size: GradientButtonSize.md,
        fullWidth: false),
    ]));
}

// ── Aurora glow backdrop (radial cyan/magenta wash on void) ──
class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop();
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.bgBase),
      child: Stack(children: [
        Positioned(
          top: -40, right: -30,
          child: _glow(220, AppColors.accentPurple.withValues(alpha: 0.18))),
        Positioned(
          bottom: -60, left: -40,
          child: _glow(240, AppColors.neonCyan.withValues(alpha: 0.10))),
      ]),
    );
  }

  Widget _glow(double size, Color c) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [c, Colors.transparent]),
    ),
  );
}

// ── Centered glass date-divider chip ──
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
      child: Text(label, style: AppTextStyles.labelSm.copyWith(
        color: AppColors.textSecondary)),
    );
  }
}

// Эмодзи / стикер жагсаалт (UB шөнийн амьдралын сэдэвт тохируулсан)
const _kEmojis = [
  '😀','😁','😂','🤣','😊','😍','😘','😎','🤩','🥳','😜','😏',
  '😢','😭','😡','😴','🤔','😅','🙄','😱','🥰','😋','🤤','🤗',
  '👍','👎','👏','🙏','💪','🙌','🤙','✌️','👌','🤝','🫶','👀',
  '🔥','✨','🎉','💯','❤️','🧡','💛','💚','💙','💜','🖤','💔',
  '🍻','🍺','🍷','🍸','🍹','🥂','🍾','🎶','🎵','🎤','🎧','🎸',
  '🕺','💃','🌃','🌙','⭐','🎂','🎁','📸','💋','💎','🚬','🥃',
];
const _kStickers = [
  '🎉','🔥','❤️','😂','👍','🥳','🍻','🌃','🎶','💃',
  '🕺','💯','😍','🙌','✨','😎','💋','🥂','🤩','🫶',
];

// Зөвхөн эмодзиос бүрдсэн богино мессежийг том (sticker) хэлбэрээр харуулна
bool _isEmojiOnly(String s) {
  final t = s.trim();
  if (t.isEmpty || t.runes.length > 8) return false;
  return !RegExp(r'[A-Za-z0-9]').hasMatch(t);
}

class _Bubble extends StatelessWidget {
  final String text, time;
  final bool isMe;
  final String? storyMediaUrl;
  final String? noteText;
  // Bubble GROUP байрлал — radius, зай, avatar, цаг эндээс шалтгаална
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final String? avatarUrl;    // партнёрын avatar (группийн сүүлийн bubble дээр)
  final String senderInitial;
  const _Bubble({required this.text, required this.isMe, required this.time,
    this.storyMediaUrl, this.noteText,
    this.isFirstInGroup = true, this.isLastInGroup = true,
    this.avatarUrl, this.senderInitial = '?'});

  // Группийн байрлалаас хамаарсан radius — зөвхөн сүүлийнх нь "сүүл"-тэй
  BorderRadius get _radius {
    const r    = Radius.circular(18);
    const mid  = Radius.circular(6);
    const tail = Radius.circular(4);
    if (isMe) {
      return BorderRadius.only(
        topLeft: r, bottomLeft: r,
        topRight: isFirstInGroup ? r : mid,
        bottomRight: isLastInGroup ? tail : mid);
    }
    return BorderRadius.only(
      topRight: r, bottomRight: r,
      topLeft: isFirstInGroup ? r : mid,
      bottomLeft: isLastInGroup ? tail : mid);
  }

  // Тэдний (партнёрын) шилэн bubble
  BoxDecoration get _themGlass => BoxDecoration(
    color: AppColors.bgElevated.withValues(alpha: 0.8),
    borderRadius: _radius,
    border: Border.all(color: AppColors.hairline),
  );

  // Миний bubble — accent gradient (зөөлөн ~0.9) + neon glow
  BoxDecoration get _meGrad => BoxDecoration(
    gradient: AppColors.accentGradient.scale(0.9),
    borderRadius: _radius,
    boxShadow: [
      BoxShadow(
        color: AppColors.accentEnd.withValues(alpha: 0.28),
        blurRadius: 18, spreadRadius: -2, offset: const Offset(0, 6)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    // Партнёрын мөр: группийн СҮҮЛИЙН bubble дээр л avatar 28 харагдана,
    // бусад мөрөнд ижил өргөнтэй хоосон зай (bubble-ууд шулуун эгнэнэ)
    final row = isMe
        ? Align(alignment: Alignment.centerRight, child: body)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isLastInGroup)
                AppAvatar(imageUrl: avatarUrl, initial: senderInitial, size: 28)
              else
                const SizedBox(width: 28),
              const SizedBox(width: 8),
              Flexible(child: Align(
                alignment: Alignment.centerLeft, child: body)),
            ]);
    return Padding(
      // Ижил илгээгчийн дараалсан bubble-ууд 2px-ээр нягтарна
      padding: EdgeInsets.only(bottom: isLastInGroup ? 10 : 2),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          row,
          // Цаг (micro) — зөвхөн группийн сүүлийн bubble дор
          if (isLastInGroup)
            Padding(
              padding: EdgeInsets.only(
                top: 3, left: isMe ? 0 : 42, right: isMe ? 6 : 0),
              child: Text(time, style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.textSecondary))),
        ]),
    );
  }

  // Мессежийн агуулга — төрлөөс (note/story/sticker/энгийн) хамаарна
  Widget _buildBody(BuildContext context) {
    final maxW =
        MediaQuery.of(context).size.width * kBubbleMaxWidthFactor;
    // 📝 Note-д хариулсан → note ишлэл + хариу bubble
    if (noteText != null && noteText!.trim().isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(isMe ? 'Note-д хариулсан' : 'Таны note-д хариулсан',
            style: AppTextStyles.bodyXs.copyWith(
              color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
          const SizedBox(height: 3),
          // Note ишлэл
          Container(
            constraints: BoxConstraints(maxWidth: maxW),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgSurface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(14),
              border: const Border(left: BorderSide(
                color: AppColors.neonCyan, width: 3))),
            child: Text(noteText!, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: maxW),
            decoration: isMe ? _meGrad : _themGlass,
            child: Text(text, style: AppTextStyles.bodyMd.copyWith(
              color: isMe ? Colors.white : AppColors.textPrimary)),
          ),
        ]);
    }
    // 📷 Story-д хариулсан → story thumbnail + тэмдэг + хариу bubble
    if (storyMediaUrl != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 30, height: 42,
                child: Image.network(storyMediaUrl!, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.bgSurface,
                    child: const Icon(Icons.auto_stories,
                        size: 16, color: AppColors.textTertiary)))),
            ),
            const SizedBox(width: 6),
            Text(isMe ? 'Story-д хариулсан' : 'Таны story-д хариулсан',
              style: AppTextStyles.bodyXs.copyWith(
                color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
          ]),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: maxW),
            decoration: (isMe ? _meGrad : _themGlass).copyWith(
              border: Border(left: BorderSide(
                color: isMe ? Colors.white54 : AppColors.neonCyan, width: 3))),
            child: Text(text, style: AppTextStyles.bodyMd.copyWith(
              color: isMe ? Colors.white : AppColors.textPrimary)),
          ),
        ]);
    }
    // 🦉 Owl sticker → онцгой gradient pill
    if (isOwlSticker(text)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentEnd.withValues(alpha: 0.4),
              blurRadius: 20, offset: const Offset(0, 8)),
          ]),
        child: Text(text, style: const TextStyle(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      );
    }
    // Sticker / emoji-only → дэвсгэргүй, том хэмжээгээр
    if (_isEmojiOnly(text)) {
      return Text(text, style: const TextStyle(fontSize: 46));
    }
    // Энгийн текст bubble
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: isMe ? _meGrad : _themGlass,
      child: Text(text, style: AppTextStyles.bodyMd.copyWith(
        color: isMe ? Colors.white : AppColors.textPrimary)),
    );
  }
}
