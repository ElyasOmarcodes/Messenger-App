import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_options.dart';
import '../widgets/rich_message.dart';
import 'chat_screen.dart';

/// Telegram-style search: chats and people first, then messages, with
/// filters (photos, files, voice, links). Searches the messages kept on this
/// phone — they are end-to-end encrypted, so the server cannot (WhatsApp works
/// the same way). Opened from the chat list, or for one chat from its menu.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.chatId, this.initial = ''});
  final String? chatId;
  final String initial;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _ctl = TextEditingController(text: widget.initial);
  String? _kind;
  List<({Chat chat, Message m})> _results = const [];
  bool _busy = false;
  Timer? _debounce;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final run = ++_run;
    setState(() => _busy = true);
    final r = await AppScope.read(context).searchMessages(_ctl.text, chatId: widget.chatId, kind: _kind);
    if (!mounted || run != _run) return;
    setState(() {
      _results = r;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final q = _ctl.text.trim().toLowerCase();
    final chatHits = widget.chatId != null || q.isEmpty
        ? const <Chat>[]
        : app.chats.where((c) => app.chatTitle(c).toLowerCase().contains(q) || c.members.any((m) => (m.username ?? '').contains(q))).toList();
    final inChat = widget.chatId == null ? null : app.chatById(widget.chatId!);
    final filters = [(null, 'all'), ('media', 'photos'), ('files', 'files'), ('voice', 'voice_tab'), ('links', 'links')];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctl,
          autofocus: widget.initial.isEmpty,
          onChanged: (_) => _changed(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: inChat == null ? context.tr('search') : '${context.tr('search')}: ${app.chatTitle(inChat)}',
            border: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_ctl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: context.tr('clear'),
              onPressed: () {
                _ctl.clear();
                _changed();
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              children: [
                for (final (k, label) in filters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(context.tr(label)),
                      selected: _kind == k,
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _kind = k);
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (chatHits.isNotEmpty) ...[
            _Header(context.tr('chats')),
            for (final c in chatHits)
              ListTile(
                leading: ChatAvatar(chat: c, size: 46),
                title: NameLine(
                  app.chatTitle(c),
                  verified: app.isVerified(c),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id))),
              ),
          ],
          if (_results.isNotEmpty) _Header(context.tr('messages_n', {'n': context.digits(_results.length)})),
          for (final r in _results)
            ListTile(
              leading: ChatAvatar(chat: r.chat, size: 46),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      app.chatTitle(r.chat),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(chatListTime(r.m.createdAt, context.lang, Strings(context.lang)), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ],
              ),
              subtitle: _Snippet(text: _snippetOf(app, r.m), query: q),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(chatId: r.chat.id, jumpTo: r.m.id),
                ),
              ),
            ),
          if (!_busy && _results.isEmpty && chatHits.isEmpty && (q.isNotEmpty || _kind != null))
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                context.tr('no_results'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  String _snippetOf(AppController app, Message m) {
    final body = RichMessageText.strip(m.body);
    return body.isNotEmpty ? body : app.previewOf(m);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 14),
    ),
  );
}

/// One line of the message with the searched words in bold colour.
class _Snippet extends StatelessWidget {
  const _Snippet({required this.text, required this.query});
  final String text, query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final flat = text.replaceAll('\n', ' ');
    final i = query.isEmpty ? -1 : flat.toLowerCase().indexOf(query);
    if (i < 0) return Text(flat, maxLines: 2, overflow: TextOverflow.ellipsis);
    // start a little before the hit, so it is visible in one line
    final from = i > 30 ? i - 30 : 0;
    final pre = (from > 0 ? '…' : '') + flat.substring(from, i);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: pre),
          TextSpan(
            text: flat.substring(i, i + query.length),
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: flat.substring(i + query.length)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
