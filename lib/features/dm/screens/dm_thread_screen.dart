import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/stickers.dart';

class DmThreadScreen extends StatefulWidget {
  final String threadId; // partner's user_id
  final String? replyNote; // note-д хариулж байгаа бол түүний текст
  const DmThreadScreen({super.key, required this.threadId, this.replyNote});
  @override State<DmThreadScreen> createState() => _DmThreadScreenState();
}

class _DmThreadScreenState extends State<DmThreadScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _msgs = [];
  Map<String, dynamic>? _partner;
  bool _loading = true;
  bool _sending = false;
  bool _showEmoji = false;
  String _emojiTab = 'emoji'; // 'emoji' | 'sticker'

  StreamSubscription? _sub;
  String? _pendingNote; // note-д хариулж байгаа эсэх

  String get _myId => SupabaseService.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    final n = widget.replyNote?.trim();
    if (n != null && n.isNotEmpty) _pendingNote = n;
    _loadPartner();
    _subscribe();
  }

  Future<void> _loadPartner() async {
    try {
      final p = await SupabaseService.client
          .from('profiles')
          .select('id, username, avatar_url')
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
          setState(() { _msgs = msgs; _loading = false; });
          _scrollToBottom();
          _markRead(); // ирсэн мессежийг уншсан болгоно
        });
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
    _ctrl.dispose();
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
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20)),
        title: GestureDetector(
          onTap: () => context.push('/creator/${widget.threadId}'),
          child: Row(children: [
            AppAvatar(imageUrl: avatarUrl, initial: initial, size: 36),
            const SizedBox(width: 10),
            Text(username, style: AppTextStyles.labelLg),
          ])),
        titleSpacing: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.hairline)),
      ),
      body: Column(children: [
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accentStart, strokeWidth: 2))
          : _msgs.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppAvatar(imageUrl: avatarUrl, initial: initial, size: 64),
                  const SizedBox(height: 16),
                  Text(username, style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  Text('Start a conversation!',
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.textSecondary)),
                ]))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final m    = _msgs[i];
                    final isMe = m['sender_id'] == _myId;
                    final text = m['body'] as String? ?? '';
                    final time = m['created_at'] as String?;
                    // Date separator
                    final showDate = i == 0 ||
                        !_sameDay(time, _msgs[i-1]['created_at'] as String?);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDate)
                          Center(child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_dateLabel(time),
                              style: AppTextStyles.bodyXs.copyWith(
                                color: AppColors.textTertiary)))),
                        _Bubble(text: text, isMe: isMe, time: _timeStr(time),
                          storyMediaUrl: m['story_media_url'] as String?,
                          noteText: m['note_text'] as String?),
                        // "Үзсэн" — зөвхөн өөрийн сүүлийн мессеж уншигдсан үед
                        if (isMe && i == lastMineIdx && (m['is_read'] == true))
                          Padding(
                            padding: const EdgeInsets.only(right: 2, bottom: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Icon(Icons.done_all_rounded,
                                  size: 13, color: AppColors.accentStart),
                                const SizedBox(width: 3),
                                Text('Үзсэн', style: AppTextStyles.bodyXs.copyWith(
                                  color: AppColors.textTertiary)),
                              ])),
                      ]);
                  })),

        // Input + emoji panel
        SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Note-д хариулж байгаа бол ишлэл харуулна
          if (_pendingNote != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
              color: AppColors.bgElevated,
              child: Row(children: [
                Container(width: 3, height: 32,
                  decoration: BoxDecoration(color: AppColors.accentStart,
                    borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$username-ийн note-д хариулж байна',
                      style: AppTextStyles.bodyXs.copyWith(
                        color: AppColors.accentStart, fontWeight: FontWeight.w600)),
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
          Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            decoration: const BoxDecoration(
              color: AppColors.bgElevated,
              border: Border(top: BorderSide(color: AppColors.hairline))),
            child: Row(children: [
              IconButton(
                onPressed: () => setState(() => _showEmoji = !_showEmoji),
                icon: Icon(
                  _showEmoji ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
                  color: _showEmoji ? AppColors.accentStart : AppColors.textSecondary)),
              Expanded(child: TextField(
                controller: _ctrl,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.textPrimary),
                textInputAction: TextInputAction.send,
                onTap: () { if (_showEmoji) setState(() => _showEmoji = false); },
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppColors.hairline)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppColors.hairline)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(
                      color: AppColors.accentStart, width: 1.5)),
                  fillColor: AppColors.bgSurface,
                  filled: true))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 42, height: 42,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient),
                  child: _sending
                    ? const Padding(padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18))),
            ])),
          if (_showEmoji) _buildEmojiPanel(),
        ])),
      ]),
    );
  }

  bool _sameDay(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.parse(a); final db = DateTime.parse(b);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  String _dateLabel(String? iso) {
    if (iso == null) return '';
    final d = DateTime.parse(iso);
    final now = DateTime.now();
    if (_sameDay(iso, now.toIso8601String())) return 'Today';
    if (_sameDay(iso, now.subtract(const Duration(days:1)).toIso8601String()))
      return 'Yesterday';
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
      color: AppColors.bgElevated,
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
                  GestureDetector(
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
                  GestureDetector(
                    onTap: () => _onEmojiTap(e),
                    behavior: HitTestBehavior.opaque,
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
          color: active ? AppColors.accentStart : Colors.transparent, width: 2))),
        child: Center(child: Text(label, style: AppTextStyles.bodyMd.copyWith(
          color: active ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
      )));
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
  const _Bubble({required this.text, required this.isMe, required this.time,
    this.storyMediaUrl, this.noteText});

  @override
  Widget build(BuildContext context) {
    // 📝 Note-д хариулсан → note ишлэл + хариу bubble
    if (noteText != null && noteText!.trim().isNotEmpty) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(isMe ? 'Note-д хариулсан' : 'Таны note-д хариулсан',
                style: AppTextStyles.bodyXs.copyWith(
                  color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
              const SizedBox(height: 3),
              // Note ишлэл
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(left: BorderSide(
                    color: AppColors.accentStart, width: 3))),
                child: Text(noteText!, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyXs.copyWith(
                    color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  gradient: isMe ? AppColors.accentGradient : null,
                  color: isMe ? null : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(16)),
                child: Text(text, style: AppTextStyles.bodyMd.copyWith(
                  color: isMe ? Colors.white : AppColors.textPrimary)),
              ),
              const SizedBox(height: 2),
              Text(time, style: const TextStyle(
                fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    // 📷 Story-д хариулсан → story thumbnail + тэмдэг + хариу bubble
    if (storyMediaUrl != null) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
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
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  gradient: isMe ? AppColors.accentGradient : null,
                  color: isMe ? null : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border(left: BorderSide(
                    color: isMe ? Colors.white54 : AppColors.accentStart, width: 3))),
                child: Text(text, style: AppTextStyles.bodyMd.copyWith(
                  color: isMe ? Colors.white : AppColors.textPrimary)),
              ),
              const SizedBox(height: 2),
              Text(time, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    // 🦉 Owl sticker → онцгой gradient pill
    if (isOwlSticker(text)) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(20)),
                child: Text(text, style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 2),
              Text(time, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    // Sticker / emoji-only → дэвсгэргүй, том хэмжээгээр
    if (_isEmojiOnly(text)) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 46)),
              const SizedBox(height: 2),
              Text(time, style: TextStyle(
                fontSize: 10, color: AppColors.textTertiary)),
            ])));
    }
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
        gradient: isMe ? AppColors.accentGradient : null,
        color: isMe ? null : AppColors.bgSurface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18))),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(text, style: AppTextStyles.bodyMd.copyWith(
            color: isMe ? Colors.white : AppColors.textPrimary)),
          const SizedBox(height: 3),
          Text(time, style: TextStyle(
            fontSize: 10, color: isMe ? Colors.white60 : AppColors.textTertiary)),
        ])));
  }
}
