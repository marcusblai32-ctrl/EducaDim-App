import 'package:flutter/material.dart';
import '../network/api_exception.dart';
import 'common.dart';

/// Charge une donnée asynchrone avec états chargement / erreur (avec réessai).
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _f = widget.load();

  Future<void> _reload() async {
    setState(() => _f = widget.load());
    try {
      await _f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final msg = snap.error is ApiException
                ? (snap.error as ApiException).message
                : 'Une erreur est survenue.';
            return EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Chargement impossible',
              message: msg,
              action: OutlinedButton(onPressed: _reload, child: const Text('Réessayer')),
            );
          }
          return widget.builder(context, snap.data as T, _reload);
        },
      );
}
