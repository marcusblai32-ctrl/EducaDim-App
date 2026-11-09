import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import '../../core/i18n/text.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/common.dart';
import '../courses/course_widgets.dart';
import '../courses/models.dart' show formatDate;
import 'chat_controller.dart';

/// Liste des salons.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ChatController>().loadRooms());
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final sync = context.watch<SyncService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discussions'),
        actions: [
          SyncBadge(online: sync.online, pending: sync.pending),
          const SizedBox(width: 12),
        ],
      ),
      body: Builder(builder: (_) {
        if (chat.roomsLoading && chat.rooms.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (chat.rooms.isEmpty) {
          return RefreshIndicator(
            onRefresh: chat.loadRooms,
            child: ListView(children: [
              SizedBox(
                height: 420,
                child: EmptyState(
                  icon: chat.roomsError == null ? Icons.forum_outlined : Icons.cloud_off_rounded,
                  title: chat.roomsError == null ? 'Aucune discussion' : 'Chargement impossible',
                  message: chat.roomsError ??
                      'Ouvrez un cours auquel vous êtes inscrit et touchez « Discussion du cours » '
                          'pour rejoindre le groupe.',
                  action: chat.roomsError == null
                      ? null
                      : OutlinedButton(onPressed: chat.loadRooms, child: const Text('Réessayer')),
                ),
              ),
            ]),
          );
        }
        return RefreshIndicator(
          onRefresh: chat.loadRooms,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (chat.roomsFromCache) const OfflineBanner(),
            for (final r in chat.rooms)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: Stack(clipBehavior: Clip.none, children: [
                      Icon(r.type == 'group' ? Icons.groups_outlined : Icons.person_outline),
                      if (r.onlineCount > 0) const Positioned(right: -4, bottom: -4, child: OnlineDot(size: 12)),
                    ]),
                    title: Text(r.titre, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      r.lastText == null
                          ? 'Aucun message'
                          : '${r.lastUser ?? ''}: ${r.lastText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/chat/${r.id}', extra: r.titre),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

/// Conversation d'un salon.
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen(this.roomId, {super.key, this.title});
  final int roomId;
  final String? title;
  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  late ChatController _chat;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatController>();
    _chat = chat;
    chat.openRoom(widget.roomId);
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => chat.fetch(widget.roomId));
  }

  @override
  void dispose() {
    _chat.closeRoom(widget.roomId);
    _poll?.cancel();
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _c.text;
    _c.clear();
    await context.read<ChatController>().send(widget.roomId, text);
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final sync = context.watch<SyncService>();
    final t = Theme.of(context);
    final msgs = chat.messages(widget.roomId);
    if (msgs.length != _lastCount) {
      _lastCount = msgs.length;
      _toBottom();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Discussion', overflow: TextOverflow.ellipsis),
        actions: [
          SyncBadge(online: sync.online, pending: sync.pending),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(children: [
        if (chat.roomOffline[widget.roomId] == true)
          Container(
            width: double.infinity,
            color: EdColors.warn.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(10),
            child: const Text('Hors ligne : les nouveaux messages arriveront au retour de la connexion.',
                style: TextStyle(fontSize: 12, color: EdColors.warn)),
          ),
        if (chat.roomError[widget.roomId] != null)
          Container(
            width: double.infinity,
            color: EdColors.red.withValues(alpha: 0.10),
            padding: const EdgeInsets.all(10),
            child: Text(chat.roomError[widget.roomId]!,
                style: const TextStyle(fontSize: 12, color: EdColors.red)),
          ),
        Expanded(
          child: msgs.isEmpty
              ? const EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Aucun message',
                  message: 'Écrivez le premier message de ce salon.')
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    return Align(
                      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints:
                            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: m.mine ? EdColors.blue : t.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: m.mine ? null : Border.all(color: t.dividerColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!m.mine)
                              Text(m.userName,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: t.colorScheme.primary)),
                            Text(m.body,
                                style: TextStyle(
                                    color: m.mine ? Colors.white : null, height: 1.4)),
                            const SizedBox(height: 4),
                            Text(
                              m.isPending
                                  ? 'En attente d’envoi'
                                  : m.isFailed
                                      ? 'Échec d’envoi'
                                      : formatDate(m.createdAt),
                              style: TextStyle(
                                  fontSize: 10,
                                  color: m.mine ? Colors.white70 : null),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: tr('Votre message…')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: EdColors.red),
                tooltip: tr('Envoyer'),
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
