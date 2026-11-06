import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/sync/sync_service.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/common.dart';
import 'chat_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    context.read<ChatController>().load();
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _c.text;
    _c.clear();
    await context.read<ChatController>().send(text);
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final sync = context.watch<SyncService>();
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat EducaDim'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: SyncBadge(online: sync.online, pending: sync.pending)),
          ),
        ],
      ),
      body: Column(children: [
        if (sync.note != null && sync.pending > 0)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF5E6),
            padding: const EdgeInsets.all(12),
            child: Text(sync.note!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF875315))),
          ),
        Expanded(
          child: chat.messages.isEmpty
              ? const EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Aucun message',
                  message:
                      'Écrivez votre premier message. Hors ligne, il est conservé '
                      'et envoyé automatiquement au retour de la connexion.')
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: chat.messages.length,
                  itemBuilder: (_, i) {
                    final m = chat.messages[i];
                    return Align(
                      alignment:
                          m.isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: m.isMine ? EdColors.blue : t.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: m.isMine ? null : Border.all(color: t.dividerColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(m.body,
                                style: TextStyle(
                                    color: m.isMine ? Colors.white : null, height: 1.4)),
                            const SizedBox(height: 4),
                            Text(
                              m.isPending ? 'En attente d’envoi' : 'Envoyé',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: m.isMine ? Colors.white70 : null),
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
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Votre message…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: EdColors.red),
                tooltip: 'Envoyer',
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
