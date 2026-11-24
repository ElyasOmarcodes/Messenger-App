import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';

/// Bottom sheet: start a chat by email/@username, or create a group.
Future<Chat?> showNewChatSheet(BuildContext context) {
  return showModalBottomSheet<Chat>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _NewChatSheet(),
  );
}

/// Text field + "Find" button that resolves an email or @username to a profile.
class PersonFinder extends StatefulWidget {
  const PersonFinder({super.key, required this.onFound, this.buttonKey = 'find', this.autofocus = true});
  final ValueChanged<Profile> onFound;
  final String buttonKey;
  final bool autofocus;

  @override
  State<PersonFinder> createState() => _PersonFinderState();
}

class _PersonFinderState extends State<PersonFinder> {
  final _q = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    if (_q.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    Profile? p;
    String? err;
    try {
      p = await AppScope.read(context).findUser(_q.text);
      if (p == null) err = 'not_found';
    } catch (_) {
      err = 'err_network';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err == null ? null : context.tr(err);
    });
    if (p != null) {
      _q.clear();
      widget.onFound(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _q,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: context.tr('find_hint'),
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _find(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(72, 52)),
          onPressed: _busy ? null : _find,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
              : Text(context.tr(widget.buttonKey)),
        ),
      ],
    );
  }
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet();

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  bool _group = false;
  final _title = TextEditingController();
  final List<Profile> _members = [];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _openDirect(Profile p) async {
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    final chat = await AppScope.read(context).startDirectChat(p);
    nav.pop(chat);
  }

  Future<void> _createGroup() async {
    if (_title.text.trim().isEmpty) return;
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    final chat = await AppScope.read(context).createGroup(_title.text, _members);
    nav.pop(chat);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.person_rounded), label: Text(context.tr('new_chat'))),
                ButtonSegment(value: true, icon: const Icon(Icons.groups_rounded), label: Text(context.tr('new_group'))),
              ],
              selected: {_group},
              onSelectionChanged: (v) => setState(() => _group = v.first),
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (!_group) ...[
              Text(context.tr('find_person'), style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              PersonFinder(onFound: _openDirect, buttonKey: 'start_chat'),
            ] else ...[
              TextField(
                controller: _title,
                maxLength: 60,
                decoration: InputDecoration(labelText: context.tr('group_name'), prefixIcon: const Icon(Icons.groups_rounded), counterText: ''),
              ),
              const SizedBox(height: 14),
              Text(context.tr('add_members'), style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              PersonFinder(
                autofocus: false,
                buttonKey: 'add',
                onFound: (p) => setState(() {
                  if (!_members.any((m) => m.id == p.id)) _members.add(p);
                }),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _members)
                    InputChip(
                      avatar: Avatar(seed: m.id, label: m.name, imageUrl: m.avatarUrl, size: 24),
                      label: Text(m.name),
                      onDeleted: () => setState(() => _members.remove(m)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _createGroup,
                style: FilledButton.styleFrom(backgroundColor: Brand.accent, foregroundColor: Colors.white),
                icon: const Icon(Icons.check_rounded),
                label: Text(context.tr('create')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
