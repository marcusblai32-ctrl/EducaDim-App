import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/widgets/common.dart';

/// Plan d'étude : GET/POST plan/, PATCH/DELETE plan/<id>/ (tâches de l'apprenant, liées ou non à un cours).
class PlanItem {
  PlanItem({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.due,
    required this.courseTitle,
    required this.auto,
  });
  final int id;
  String title;
  String description;
  String priority;
  String status;
  DateTime? due;
  final String? courseTitle;
  final bool auto;

  bool get done => status == 'completed';

  factory PlanItem.fromJson(Map m) => PlanItem(
        id: (m['id'] as num).toInt(),
        title: '${m['title'] ?? ''}',
        description: '${m['description'] ?? ''}',
        priority: '${m['priority'] ?? 'medium'}',
        status: '${m['status'] ?? 'pending'}',
        due: m['due_date'] is String ? DateTime.tryParse(m['due_date'] as String)?.toLocal() : null,
        courseTitle: m['course_title'] is String ? m['course_title'] as String : null,
        auto: m['auto'] == true,
      );
}

class PlanRepository {
  PlanRepository(this.api);
  final ApiClient api;

  Future<List<PlanItem>> list() async {
    try {
      final res = await api.dio.get('plan/');
      final m = res.data is Map ? res.data as Map : const {};
      return [
        for (final x in (m['items'] as List? ?? []))
          if (x is Map) PlanItem.fromJson(x),
      ];
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<PlanItem> create(String title, DateTime? due, String priority) async {
    try {
      final res = await api.dio.post('plan/', data: {
        'title': title,
        'priority': priority,
        if (due != null) 'due_date': due.toUtc().toIso8601String(),
      });
      return PlanItem.fromJson(res.data as Map);
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<void> setStatus(int id, String status) async {
    try {
      await api.dio.patch('plan/$id/', data: {'status': status});
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }

  Future<void> remove(int id) async {
    try {
      await api.dio.delete('plan/$id/');
    } on DioException catch (e) {
      throw mapDio(e);
    }
  }
}

String _fmt(DateTime d) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
}

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final PlanRepository _repo = PlanRepository(context.read<ApiClient>());
  List<PlanItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : tr('Une erreur est survenue.');
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggle(PlanItem it) async {
    final before = it.status;
    setState(() => it.status = it.done ? 'pending' : 'completed');
    try {
      await _repo.setStatus(it.id, it.status);
    } catch (e) {
      if (!mounted) return;
      setState(() => it.status = before);
      _toast(e is ApiException ? e.message : 'Une erreur est survenue.');
    }
  }

  Future<void> _delete(PlanItem it) async {
    final index = _items.indexOf(it);
    setState(() => _items.remove(it));
    try {
      await _repo.remove(it.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items.insert(index < 0 ? 0 : index, it));
      _toast(e is ApiException ? e.message : 'Une erreur est survenue.');
    }
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<PlanItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddSheet(repo: _repo),
    );
    if (created != null && mounted) setState(() => _items.insert(0, created));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.65);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final open = _items.where((i) => !i.done).toList();
    final overdue = open.where((i) => i.due != null && i.due!.isBefore(now)).toList();
    final todayL = open.where((i) => i.due != null && !overdue.contains(i) && i.due!.isBefore(tomorrow)).toList();
    final soon = open.where((i) => i.due != null && !overdue.contains(i) && !todayL.contains(i)).toList();
    final none = open.where((i) => i.due == null).toList();
    final done = _items.where((i) => i.done).toList();

    Widget section(String title, List<PlanItem> list, {Color? color}) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
          child: Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ),
        for (final it in list) _tile(it, t, muted),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mon plan d’étude')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Chargement impossible',
                  message: _error!,
                  action: OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
                )
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.checklist_rounded,
                      title: 'Votre plan est vide',
                      message: 'Ajoutez une tâche, ou inscrivez-vous à un cours : une tâche « Terminer le cours » sera ajoutée pour vous.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
                        section('En retard', overdue, color: Colors.red.shade700),
                        section('Aujourd’hui', todayL),
                        section('À venir', soon),
                        section('Sans échéance', none),
                        section('Terminées', done, color: muted),
                      ]),
                    ),
    );
  }

  Widget _tile(PlanItem it, ThemeData t, Color muted) {
    return Dismissible(
      key: ValueKey('plan-${it.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _delete(it),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: Checkbox(
            value: it.done,
            shape: const CircleBorder(),
            onChanged: (_) => _toggle(it),
          ),
          title: Text(
            it.title,
            style: TextStyle(
              decoration: it.done ? TextDecoration.lineThrough : null,
              color: it.done ? muted : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: (it.due != null || it.courseTitle != null)
              ? Text([
                  if (it.due != null) _fmt(it.due!),
                  if (it.courseTitle != null) it.courseTitle!,
                ].join(' · '))
              : null,
          trailing: it.priority == 'high'
              ? Icon(Icons.flag_rounded, color: Colors.red.shade600, size: 20)
              : null,
          onTap: () => _toggle(it),
        ),
      ),
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet({required this.repo});
  final PlanRepository repo;
  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _title = TextEditingController();
  DateTime? _due;
  String _priority = 'medium';
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 730)), initialDate: _due ?? now);
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_due ?? now.add(const Duration(hours: 1))));
    if (!mounted) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, tm?.hour ?? 18, tm?.minute ?? 0));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _err = tr('Écrivez le titre de la tâche.'));
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      final it = await widget.repo.create(title, _due, _priority);
      if (mounted) Navigator.of(context).pop(it);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _err = e is ApiException ? e.message : tr('Une erreur est survenue.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Nouvelle tâche', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        TextField(
          controller: _title,
          autofocus: true,
          textInputAction: TextInputAction.done,
          maxLength: 255,
          decoration: InputDecoration(labelText: tr('Que voulez-vous faire ?'), errorText: _err),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _pickDue,
            icon: const Icon(Icons.event_rounded),
            label: Text(_due == null ? 'Ajouter une échéance' : _fmt(_due!)),
          ),
          if (_due != null)
            TextButton(onPressed: () => setState(() => _due = null), child: const Text('Retirer')),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'low', label: Text('Basse')),
            ButtonSegment(value: 'medium', label: Text('Moyenne')),
            ButtonSegment(value: 'high', label: Text('Haute')),
          ],
          selected: {_priority},
          onSelectionChanged: (s) => setState(() => _priority = s.first),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer'),
          ),
        ),
      ]),
    );
  }
}
