import 'dart:typed_data';
import 'package:flutter/material.dart' hide Text;
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/security/offline_access.dart';
import 'download_service.dart';

/// Visionneuse PDF intégrée : le fichier est déchiffré en mémoire seulement, jamais écrit en clair,
/// jamais transmis à une autre application.
class SecurePdfScreen extends StatefulWidget {
  const SecurePdfScreen(this.id, {super.key, this.title});
  final String id;
  final String? title;
  @override
  State<SecurePdfScreen> createState() => _SecurePdfScreenState();
}

class _SecurePdfScreenState extends State<SecurePdfScreen> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final ds = context.read<DownloadService>();
    final access = context.read<OfflineAccess>();
    final item = ds.items.where((i) => i.id == widget.id).toList();
    if (item.isNotEmpty && item.first.courseId != null && access.isLocked(item.first.courseId!)) {
      setState(() => _error = tr('Votre accès à ce cours a expiré. Renouvelez votre abonnement pour le relire.'));
      return;
    }
    final Uint8List? bytes = await ds.readBytes(widget.id);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _error = tr('Ce document n’est plus disponible sur cet appareil.'));
      return;
    }
    setState(() => _controller = PdfControllerPinch(document: PdfDocument.openData(bytes)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? tr('Document'))),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : PdfViewPinch(controller: _controller!),
    );
  }
}
