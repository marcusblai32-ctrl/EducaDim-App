import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:pdfx/pdfx.dart';
import '../../core/i18n/text.dart';

/// PDF lu DANS l'application : téléchargé en mémoire seulement (rien n'est écrit sur le téléphone), sans bouton
/// télécharger / ouvrir / partager.
class OnlinePdfScreen extends StatefulWidget {
  const OnlinePdfScreen(this.url, {super.key, this.title});
  final String url;
  final String? title;
  @override
  State<OnlinePdfScreen> createState() => _OnlinePdfScreenState();
}

class _OnlinePdfScreenState extends State<OnlinePdfScreen> {
  PdfControllerPinch? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Dio().get<List<int>>(widget.url,
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)));
      final data = res.data;
      if (!mounted) return;
      if (data == null || data.isEmpty) {
        setState(() => _error = tr('Ce document est indisponible.'));
        return;
      }
      setState(() => _controller = PdfControllerPinch(document: PdfDocument.openData(Uint8List.fromList(data))));
    } catch (_) {
      if (mounted) setState(() => _error = tr('Impossible de charger le document. Vérifiez votre connexion.'));
    }
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
