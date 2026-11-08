import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/i18n/text.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'admin_repository.dart';
import 'form_sheet.dart';

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(snackBarAnimationStyle: AnimationStyle.noAnimation, SnackBar(content: Text(m)));

String _msg(Object e) => e is ApiException
    ? (e.isOffline ? tr('Connexion requise pour cette action.') : e.message)
    : tr('Une erreur est survenue.');

Future<bool> _confirm(BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(animationStyle: AnimationStyle.noAnimation, 
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        TextButton(
            style: TextButton.styleFrom(foregroundColor: EdColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer')),
      ],
    ),
  );
  return ok == true;
}

// ======================= Liste des cours gérables =======================

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdminRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouveau cours'),
        onPressed: () async {
          await context.push('/admin/course/new');
          if (mounted) setState(() => _v++);
        },
      ),
      body: AsyncView<List>(
        key: ValueKey(_v),
        load: repo.courses,
        builder: (context, courses, reload) {
          if (courses.isEmpty) {
            return const EmptyState(
                icon: Icons.library_add_outlined,
                title: 'Aucun cours',
                message: 'Créez votre premier cours avec le bouton « Nouveau cours ».');
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
              const Text('Les cours créés ici sont des brouillons : publiez-les quand ils sont prêts.',
                  style: TextStyle(height: 1.5)),
              const SizedBox(height: 12),
              for (final c in courses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: Icon(c['publie'] == true ? Icons.public_rounded : Icons.edit_note_rounded,
                          color: c['publie'] == true ? EdColors.good : null),
                      title: Text('${c['titre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${c['publie'] == true ? tr('Publié') : tr('Brouillon')} · ${tr('{n} unité(s)', {'n': c['unites_count']})}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await context.push('/admin/course/${c['id']}');
                        if (mounted) setState(() => _v++);
                      },
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ======================= Nouveau cours =======================

class AdminCourseFormScreen extends StatelessWidget {
  const AdminCourseFormScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdminRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau cours')),
      body: AsyncView<Map>(load: repo.meta, builder: (_, meta, __) => _CourseForm(meta)),
    );
  }
}

class _CourseForm extends StatefulWidget {
  const _CourseForm(this.meta);
  final Map meta;
  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  final _form = GlobalKey<FormState>();
  final _titre = TextEditingController();
  final _desc = TextEditingController();
  final _titreHt = TextEditingController();
  final _descHt = TextEditingController();
  final _prix = TextEditingController(text: '0');
  final _duree = TextEditingController(text: '0');
  int? _cat, _niv;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_titre, _desc, _titreHt, _descHt, _prix, _duree]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await context.read<AdminRepository>().createCourse({
        'titre': _titre.text,
        'description': _desc.text,
        'titre_ht': _titreHt.text,
        'description_ht': _descHt.text,
        'prix': _prix.text.trim().replaceAll(',', '.'),
        'duree': int.tryParse(_duree.text) ?? 0,
        if (_cat != null) 'categorie_id': _cat,
        if (_niv != null) 'niveau_id': _niv,
      });
      if (mounted) context.pushReplacement('/admin/course/${res['id']}');
    } catch (e) {
      if (mounted) _snack(context, _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = (widget.meta['categories'] as List?) ?? [];
    final nivs = (widget.meta['niveaux'] as List?) ?? [];
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        TextFormField(
          controller: _titre,
          decoration: InputDecoration(labelText: tr('Titre du cours')),
          validator: (v) => (v == null || v.trim().isEmpty) ? tr('Champ requis') : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
            controller: _desc,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(labelText: tr('Description'))),
        const SizedBox(height: 12),
        TextFormField(
            controller: _titreHt, decoration: InputDecoration(labelText: tr('Titre en créole (facultatif)'))),
        const SizedBox(height: 12),
        TextFormField(
            controller: _descHt,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(labelText: tr('Description en créole (facultatif)'))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextFormField(
                  controller: _prix,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Prix (HTG, 0 = gratuit)')))),
          const SizedBox(width: 12),
          Expanded(
              child: TextFormField(
                  controller: _duree,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Durée (heures)')))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _cat,
          decoration: InputDecoration(labelText: tr('Catégorie')),
          items: [for (final c in cats) DropdownMenuItem(value: c['id'] as int, child: Text('${c['nom']}'))],
          onChanged: (v) => _cat = v,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _niv,
          decoration: InputDecoration(labelText: tr('Niveau')),
          items: [for (final n in nivs) DropdownMenuItem(value: n['id'] as int, child: Text('${n['label']}'))],
          onChanged: (v) => _niv = v,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Créer le brouillon'),
        ),
      ]),
    );
  }
}

// ======================= Structure d'un cours =======================

class _Act {
  _Act(this.label, this.icon, this.onTap, {this.danger = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
}

class AdminCourseTreeScreen extends StatefulWidget {
  const AdminCourseTreeScreen(this.courseId, {super.key});
  final int courseId;
  @override
  State<AdminCourseTreeScreen> createState() => _AdminCourseTreeScreenState();
}

class _AdminCourseTreeScreenState extends State<AdminCourseTreeScreen> {
  int _v = 0;
  AdminRepository get _repo => context.read<AdminRepository>();

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      if (!mounted) return;
      _snack(context, ok);
      setState(() => _v++);
    } catch (e) {
      if (mounted) _snack(context, _msg(e));
    }
  }

  // ---------- création ----------
  Future<void> _addUnite() async {
    final v = await showFormSheet(context, tr('Nouvelle unité'), [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('description', 'Description', multiline: true),
    ]);
    if (v == null) return;
    await _run(() => _repo.createUnite(widget.courseId, v), tr('Unité ajoutée.'));
  }

  Future<void> _addModule(int uniteId) async {
    final v = await showFormSheet(context, tr('Nouveau module'), [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('description', 'Description', multiline: true),
    ]);
    if (v == null) return;
    await _run(() => _repo.createModule(uniteId, v), tr('Module ajouté.'));
  }

  Future<void> _addLecon(int moduleId) async {
    final v = await showFormSheet(context, tr('Nouvelle leçon'), [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('description', 'Description', multiline: true),
      FieldSpec('contenu', 'Texte de la leçon (facultatif)', multiline: true),
      FieldSpec('titre_ht', 'Titre en créole (facultatif)'),
      FieldSpec('description_ht', 'Description en créole (facultatif)', multiline: true),
    ]);
    if (v == null) return;
    await _run(() => _repo.createLecon(moduleId, v), tr('Leçon ajoutée.'));
  }

  Future<void> _addSection(int leconId, Map meta) async {
    final types = {for (final t in (meta['section_types'] as List)) '${t['value']}': '${t['label']}'};
    final v = await showFormSheet(context, tr('Nouvelle section'), [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('type_section', 'Type', options: types, initial: 'developpement'),
    ]);
    if (v == null) return;
    await _run(() => _repo.createSection(leconId, v), tr('Section ajoutée.'));
  }

  Future<void> _addContenu(int sectionId) async {
    final v = await showFormSheet(context, tr('Nouveau contenu'), [
      FieldSpec('type_contenu', 'Type', options: const {
        'texte': 'Texte',
        'video': 'Vidéo (URL)',
        'audio': 'Audio (URL)',
        'image': 'Image (URL)',
        'pdf': 'PDF (URL)',
        'lien': 'Lien externe',
      }),
      FieldSpec('titre', 'Titre (facultatif)'),
      FieldSpec('titre_ht', 'Titre en créole (facultatif)'),
      FieldSpec('texte', 'Texte', multiline: true, required: true, showIf: (x) => x['type_contenu'] == 'texte'),
      FieldSpec('texte_ht', 'Texte en créole (facultatif)',
          multiline: true, showIf: (x) => x['type_contenu'] == 'texte'),
      FieldSpec('url', 'URL (https://…)',
          required: true, hint: 'https://', showIf: (x) => x['type_contenu'] != 'texte'),
    ]);
    if (v == null) return;
    await _run(() => _repo.createContenu(sectionId, v), tr('Contenu ajouté.'));
  }

  Future<void> _addFlashcard(int moduleId) async {
    final v = await showFormSheet(context, tr('Nouvelle flashcard'), [
      FieldSpec('question', 'Question', required: true, multiline: true),
      FieldSpec('reponse', 'Réponse', required: true, multiline: true),
      FieldSpec('question_ht', 'Question en créole (facultatif)', multiline: true),
      FieldSpec('reponse_ht', 'Réponse en créole (facultatif)', multiline: true),
    ]);
    if (v == null) return;
    await _run(() => _repo.createFlashcard(moduleId, v), tr('Flashcard ajoutée.'));
  }

  Future<void> _addQuiz(String niveau, int parentId) async {
    final v = await showFormSheet(context, tr('Nouveau quiz'), [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('description', 'Description', multiline: true),
      FieldSpec('duree_quiz', 'Durée (minutes)', number: true, initial: '15', required: true),
      FieldSpec('pourcentage_reussite', 'Réussite (%)', number: true, initial: '70', required: true),
    ]);
    if (v == null) return;
    try {
      final q = await _repo.createQuiz({
        'niveau': niveau,
        'parent_id': parentId,
        'titre': v['titre'],
        'description': v['description'],
        'duree_quiz': int.tryParse(v['duree_quiz'] ?? '') ?? 15,
        'pourcentage_reussite': int.tryParse(v['pourcentage_reussite'] ?? '') ?? 70,
      });
      if (!mounted) return;
      await context.push('/admin/quiz/${q['id']}/question', extra: v['titre']);
      if (mounted) setState(() => _v++);
    } catch (e) {
      if (mounted) _snack(context, _msg(e));
    }
  }

  // ---------- modification ----------
  List<FieldSpec> _specs(String kind, Map f, Map meta) {
    String s(String k) => '${f[k] ?? ''}';
    switch (kind) {
      case 'course':
        final cats = {
          '': tr('Aucune'),
          for (final c in (meta['categories'] as List)) '${c['id']}': '${c['nom']}',
        };
        final nivs = {
          '': tr('Aucun'),
          for (final n in (meta['niveaux'] as List)) '${n['id']}': '${n['label']}',
        };
        final cat = s('categorie_id');
        final niv = s('niveau_id');
        return [
          FieldSpec('titre', 'Titre du cours', required: true, initial: s('titre')),
          FieldSpec('description', 'Description', multiline: true, initial: s('description')),
          FieldSpec('titre_ht', 'Titre en créole (facultatif)', initial: s('titre_ht')),
          FieldSpec('description_ht', 'Description en créole (facultatif)', multiline: true, initial: s('description_ht')),
          FieldSpec('prix', 'Prix (HTG, 0 = gratuit)', initial: s('prix')),
          FieldSpec('duree', 'Durée (heures)', number: true, initial: s('duree')),
          FieldSpec('categorie_id', 'Catégorie', options: cats, initial: cats.containsKey(cat) ? cat : ''),
          FieldSpec('niveau_id', 'Niveau', options: nivs, initial: nivs.containsKey(niv) ? niv : ''),
        ];
      case 'unite':
      case 'module':
        return [
          FieldSpec('titre', 'Titre', required: true, initial: s('titre')),
          FieldSpec('description', 'Description', multiline: true, initial: s('description')),
        ];
      case 'lecon':
        return [
          FieldSpec('titre', 'Titre', required: true, initial: s('titre')),
          FieldSpec('description', 'Description', multiline: true, initial: s('description')),
          FieldSpec('contenu', 'Texte de la leçon (facultatif)', multiline: true, initial: s('contenu')),
          FieldSpec('titre_ht', 'Titre en créole (facultatif)', initial: s('titre_ht')),
          FieldSpec('description_ht', 'Description en créole (facultatif)', multiline: true, initial: s('description_ht')),
        ];
      case 'section':
        final types = {for (final t in (meta['section_types'] as List)) '${t['value']}': '${t['label']}'};
        final cur = s('type_section');
        return [
          FieldSpec('titre', 'Titre', required: true, initial: s('titre')),
          FieldSpec('type_section', 'Type',
              options: types, initial: types.containsKey(cur) ? cur : types.keys.first),
        ];
      case 'contenu':
        final isText = s('type_contenu') == 'texte';
        return [
          FieldSpec('titre', 'Titre (facultatif)', initial: s('titre')),
          FieldSpec('titre_ht', 'Titre en créole (facultatif)', initial: s('titre_ht')),
          if (isText) ...[
            FieldSpec('texte', 'Texte', multiline: true, required: true, initial: s('texte')),
            FieldSpec('texte_ht', 'Texte en créole (facultatif)', multiline: true, initial: s('texte_ht')),
          ] else
            FieldSpec('url', 'URL (https://…)', required: true, initial: s('url')),
        ];
      case 'quiz':
        return [
          FieldSpec('titre', 'Titre', required: true, initial: s('titre')),
          FieldSpec('description', 'Description', multiline: true, initial: s('description')),
          FieldSpec('duree_quiz', 'Durée (minutes)', number: true, required: true, initial: s('duree_quiz')),
          FieldSpec('pourcentage_reussite', 'Réussite (%)', number: true, required: true, initial: s('pourcentage_reussite')),
        ];
      default: // flashcard
        return [
          FieldSpec('question', 'Question', required: true, multiline: true, initial: s('question')),
          FieldSpec('reponse', 'Réponse', required: true, multiline: true, initial: s('reponse')),
          FieldSpec('question_ht', 'Question en créole (facultatif)', multiline: true, initial: s('question_ht')),
          FieldSpec('reponse_ht', 'Réponse en créole (facultatif)', multiline: true, initial: s('reponse_ht')),
        ];
    }
  }

  Map<String, dynamic> _payload(String kind, Map<String, String> v) {
    final out = <String, dynamic>{...v};
    if (kind == 'course') {
      out['prix'] = (v['prix'] ?? '0').trim().replaceAll(',', '.');
      out['duree'] = int.tryParse(v['duree'] ?? '') ?? 0;
      out['categorie_id'] = (v['categorie_id'] ?? '').isEmpty ? null : int.tryParse(v['categorie_id']!);
      out['niveau_id'] = (v['niveau_id'] ?? '').isEmpty ? null : int.tryParse(v['niveau_id']!);
    }
    if (kind == 'quiz') {
      out['duree_quiz'] = int.tryParse(v['duree_quiz'] ?? '') ?? 15;
      out['pourcentage_reussite'] = int.tryParse(v['pourcentage_reussite'] ?? '') ?? 70;
    }
    return out;
  }

  Future<void> _edit(String kind, int id, Map meta) async {
    try {
      final f = await _repo.item(kind, id);
      if (!mounted) return;
      final v = await showFormSheet(context, tr('Modifier'), _specs(kind, f, meta), submitLabel: tr('Enregistrer'));
      if (v == null) return;
      await _run(() => _repo.updateItem(kind, id, _payload(kind, v)), tr('Modifications enregistrées.'));
    } catch (e) {
      if (mounted) _snack(context, _msg(e));
    }
  }

  Future<void> _delete(String kind, int id, String label, {bool leaveAfter = false}) async {
    final ok = await _confirm(
        context,
        tr('Supprimer cet élément ?'),
        tr('« {x} » sera supprimé définitivement, avec tout ce qu’il contient.', {'x': label}));
    if (!ok || !mounted) return;
    try {
      await _repo.deleteItem(kind, id);
      if (!mounted) return;
      _snack(context, tr('Élément supprimé.'));
      if (leaveAfter) {
        context.pop();
      } else {
        setState(() => _v++);
      }
    } catch (e) {
      if (mounted) _snack(context, _msg(e));
    }
  }

  // ---------- éléments d'interface ----------
  Widget _menu(List<_Act> acts) => PopupMenuButton<int>(popUpAnimationStyle: AnimationStyle.noAnimation, 
        tooltip: tr('Actions'),
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (i) => acts[i].onTap(),
        itemBuilder: (_) => [
          for (var i = 0; i < acts.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Row(children: [
                Icon(acts[i].icon, size: 20, color: acts[i].danger ? EdColors.red : null),
                const SizedBox(width: 10),
                Text(acts[i].label, style: TextStyle(color: acts[i].danger ? EdColors.red : null)),
              ]),
            ),
        ],
      );

  Widget _row(double indent, IconData icon, String title, List<_Act> acts,
      {String? subtitle, TextStyle? style}) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: style),
            if (subtitle != null) Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        _menu(acts),
      ]),
    );
  }

  _Act _editAct(String kind, int id, Map meta) =>
      _Act(tr('Modifier'), Icons.edit_outlined, () => _edit(kind, id, meta));
  _Act _delAct(String kind, int id, String label) =>
      _Act(tr('Supprimer'), Icons.delete_outline_rounded, () => _delete(kind, id, label), danger: true);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Structure du cours')),
      body: AsyncView<List>(
        key: ValueKey(_v),
        load: () async => [await _repo.tree(widget.courseId), await _repo.meta()],
        builder: (context, data, reload) {
          final tree = data[0] as Map;
          final meta = data[1] as Map;
          final course = tree['course'] as Map;
          final unites = (tree['unites'] as List?) ?? [];
          final quizzes = (tree['quizzes'] as List?) ?? [];
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${course['titre']}', style: t.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(course['publie'] == true ? tr('Publié') : tr('Brouillon (invisible pour les étudiants)'),
                            style: t.textTheme.bodySmall),
                      ]),
                    ),
                    Switch(
                      value: course['publie'] == true,
                      onChanged: (v) => _run(() => _repo.setCoursePublished(widget.courseId, v),
                          v ? tr('Cours publié.') : tr('Cours repassé en brouillon.')),
                    ),
                    _menu([
                      _editAct('course', widget.courseId, meta),
                      _Act(tr('Supprimer le cours'), Icons.delete_outline_rounded,
                          () => _delete('course', widget.courseId, '${course['titre']}', leaveAfter: true),
                          danger: true),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              Text('Programme', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (unites.isEmpty) const Text('Aucune unité. Commencez par en ajouter une.'),
              for (final u in unites) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 4, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _row(0, Icons.folder_outlined, '${u['titre']}', [
                        _Act(tr('Ajouter un module'), Icons.add_rounded, () => _addModule(u['id'] as int)),
                        _editAct('unite', u['id'] as int, meta),
                        _delAct('unite', u['id'] as int, '${u['titre']}'),
                      ], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      for (final m in (u['modules'] as List)) ...[
                        const SizedBox(height: 4),
                        _row(14, Icons.view_module_outlined, '${m['titre']}', [
                          _Act(tr('Ajouter une leçon'), Icons.add_rounded, () => _addLecon(m['id'] as int)),
                          _Act(tr('Ajouter une flashcard'), Icons.style_outlined, () => _addFlashcard(m['id'] as int)),
                          _Act(tr('Ajouter un quiz au module'), Icons.quiz_outlined, () => _addQuiz('module', m['id'] as int)),
                          _editAct('module', m['id'] as int, meta),
                          _delAct('module', m['id'] as int, '${m['titre']}'),
                        ], style: TextStyle(fontWeight: FontWeight.w700, color: t.colorScheme.primary)),
                        for (final f in ((m['flashcards'] as List?) ?? []))
                          _row(34, Icons.style_outlined, '${f['question']}', [
                            _editAct('flashcard', f['id'] as int, meta),
                            _delAct('flashcard', f['id'] as int, '${f['question']}'),
                          ], style: const TextStyle(fontSize: 13)),
                        for (final l in (m['lecons'] as List)) ...[
                          _row(30, Icons.menu_book_outlined, '${l['titre']}', [
                            _Act(tr('Ajouter une section'), Icons.add_rounded, () => _addSection(l['id'] as int, meta)),
                            _Act(tr('Ajouter un quiz à la leçon'), Icons.quiz_outlined, () => _addQuiz('lecon', l['id'] as int)),
                            _editAct('lecon', l['id'] as int, meta),
                            _delAct('lecon', l['id'] as int, '${l['titre']}'),
                          ]),
                          for (final s in (l['sections'] as List)) ...[
                            _row(48, Icons.segment_rounded, '${s['titre']}', [
                              _Act(tr('Ajouter un contenu'), Icons.add_rounded, () => _addContenu(s['id'] as int)),
                              _editAct('section', s['id'] as int, meta),
                              _delAct('section', s['id'] as int, '${s['titre']}'),
                            ], style: const TextStyle(fontSize: 13.5)),
                            for (final c in ((s['contenus'] as List?) ?? []))
                              _row(66, Icons.article_outlined,
                                  (c['titre'] as String?)?.isNotEmpty == true ? '${c['titre']}' : '${c['type_contenu']}', [
                                _editAct('contenu', c['id'] as int, meta),
                                _delAct('contenu', c['id'] as int, '${c['titre'] ?? c['type_contenu']}'),
                              ], subtitle: '${c['type_contenu']}', style: const TextStyle(fontSize: 13)),
                          ],
                        ],
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                  onPressed: _addUnite, icon: const Icon(Icons.add_rounded), label: const Text('Ajouter une unité')),
              const SizedBox(height: 24),
              Text('Quiz', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (quizzes.isEmpty) const Text('Aucun quiz pour ce cours.'),
              for (final q in quizzes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${q['titre']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(
                                  '${q['niveau']} · ${tr('{n} question(s)', {'n': q['questions_count']})} · ${q['publie'] == true ? tr('publié') : tr('brouillon')}',
                                  style: t.textTheme.bodySmall),
                            ]),
                          ),
                          Switch(
                            value: q['publie'] == true,
                            onChanged: (v) => _run(() => _repo.setQuizPublished(q['id'] as int, v),
                                v ? tr('Quiz publié.') : tr('Quiz repassé en brouillon.')),
                          ),
                          _menu([
                            _Act(tr('Ajouter une question'), Icons.add_rounded, () async {
                              await context.push('/admin/quiz/${q['id']}/question', extra: '${q['titre']}');
                              if (mounted) setState(() => _v++);
                            }),
                            _editAct('quiz', q['id'] as int, meta),
                            _delAct('quiz', q['id'] as int, '${q['titre']}'),
                          ]),
                        ]),
                        for (final qu in ((q['questions'] as List?) ?? []))
                          _row(6, Icons.help_outline_rounded, '${qu['texte']}', [
                            _Act(tr('Modifier'), Icons.edit_outlined, () async {
                              await context.push('/admin/quiz/${q['id']}/question?edit=${qu['id']}',
                                  extra: '${q['titre']}');
                              if (mounted) setState(() => _v++);
                            }),
                            _delAct('question', qu['id'] as int, '${qu['texte']}'),
                          ], style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => _addQuiz('cours', widget.courseId),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter un quiz au cours')),
            ]),
          );
        },
      ),
    );
  }
}

// ======================= Ajouter / modifier une question =======================

class AdminQuestionScreen extends StatefulWidget {
  const AdminQuestionScreen(this.quizId, {super.key, this.title, this.questionId});
  final int quizId;
  final String? title;
  final int? questionId; // non nul = modification
  @override
  State<AdminQuestionScreen> createState() => _AdminQuestionScreenState();
}

class _AdminQuestionScreenState extends State<AdminQuestionScreen> {
  static const _types = {
    'single': 'Choix unique',
    'multiple': 'Choix multiples',
    'vrai_faux': 'Vrai / Faux',
    'texte_trous': 'Texte à trous',
    'texte_libre': 'Réponse libre',
  };
  String _type = 'single';
  final _texte = TextEditingController();
  final _expl = TextEditingController();
  final _points = TextEditingController(text: '1');
  final _expected = TextEditingController();
  List<TextEditingController> _ans = [TextEditingController(), TextEditingController()];
  final Set<int> _correct = {};
  bool _vrai = true;
  bool _busy = false;
  bool _loading = false;
  int _added = 0;

  bool get _editing => widget.questionId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _loading = true;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    try {
      final f = await context.read<AdminRepository>().item('question', widget.questionId!);
      if (!mounted) return;
      setState(() {
        _type = '${f['type_question']}';
        _texte.text = '${f['texte'] ?? ''}';
        _points.text = '${f['points'] ?? 1}';
        _expl.text = '${f['explication'] ?? ''}';
        final answers = (f['reponses'] as List?) ?? [];
        if (_type == 'single' || _type == 'multiple') {
          _ans = [for (final a in answers) TextEditingController(text: '${a['texte']}')];
          while (_ans.length < 2) {
            _ans.add(TextEditingController());
          }
          _correct
            ..clear()
            ..addAll([
              for (var i = 0; i < answers.length; i++)
                if (answers[i]['est_correcte'] == true) i,
            ]);
        } else if (_type == 'texte_trous' && answers.isNotEmpty) {
          _expected.text = '${answers.first['texte']}';
        } else if (_type == 'vrai_faux') {
          _vrai = f['vrai_est_correct'] == true;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(context, _msg(e));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_texte, _expl, _points, _expected, ..._ans]) {
      c.dispose();
    }
    super.dispose();
  }

  void _reset() {
    _texte.clear();
    _expl.clear();
    _expected.clear();
    for (final c in _ans) {
      c.clear();
    }
    _correct.clear();
  }

  Future<void> _save() async {
    if (_texte.text.trim().isEmpty) {
      _snack(context, tr('Écrivez l’énoncé de la question.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{
        if (!_editing) 'type_question': _type,
        'texte': _texte.text,
        'explication': _expl.text,
        'points': int.tryParse(_points.text) ?? 1,
        if (_type == 'vrai_faux') 'vrai_est_correct': _vrai,
        if (_type == 'single' || _type == 'multiple')
          'reponses': [
            for (var i = 0; i < _ans.length; i++) {'texte': _ans[i].text, 'est_correcte': _correct.contains(i)},
          ],
        if (_type == 'texte_trous')
          'reponses': [
            {'texte': _expected.text, 'est_correcte': true}
          ],
      };
      final repo = context.read<AdminRepository>();
      if (_editing) {
        await repo.updateItem('question', widget.questionId!, data);
        if (!mounted) return;
        _snack(context, tr('Modifications enregistrées.'));
        context.pop();
        return;
      }
      await repo.addQuestion(widget.quizId, data);
      if (!mounted) return;
      setState(() {
        _added++;
        _reset();
      });
      _snack(context, tr('Question ajoutée ({n} dans cette séance).', {'n': _added}));
    } catch (e) {
      if (mounted) _snack(context, _msg(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choice = _type == 'single' || _type == 'multiple';
    return Scaffold(
      appBar: AppBar(
          title: Text(_editing ? tr('Modifier la question') : (widget.title ?? tr('Questions du quiz')),
              overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: InputDecoration(labelText: tr('Type de question')),
                items: [for (final e in _types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: _editing
                    ? null // le type d'une question existante ne change pas
                    : (v) => setState(() {
                          _type = v ?? 'single';
                          _correct.clear();
                        }),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: _texte,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: tr('Énoncé de la question'))),
              const SizedBox(height: 12),
              if (choice) ...[
                const Text('Réponses (cochez la ou les bonnes)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (var i = 0; i < _ans.length; i++)
                  Row(children: [
                    IconButton(
                      tooltip: tr('Bonne réponse'),
                      icon: Icon(
                          _correct.contains(i)
                              ? (_type == 'single' ? Icons.radio_button_checked : Icons.check_box)
                              : (_type == 'single' ? Icons.radio_button_unchecked : Icons.check_box_outline_blank),
                          color: _correct.contains(i) ? EdColors.good : null),
                      onPressed: () => setState(() {
                        if (_type == 'single') _correct.clear();
                        _correct.contains(i) ? _correct.remove(i) : _correct.add(i);
                      }),
                    ),
                    Expanded(
                        child: TextField(
                            controller: _ans[i],
                            decoration: InputDecoration(labelText: tr('Réponse {n}', {'n': i + 1})))),
                    if (_ans.length > 2)
                      IconButton(
                        tooltip: tr('Retirer'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _ans.removeAt(i).dispose();
                          _correct.clear();
                        }),
                      ),
                  ]),
                TextButton.icon(
                    onPressed: _ans.length >= 8 ? null : () => setState(() => _ans.add(TextEditingController())),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Ajouter une réponse')),
              ],
              if (_type == 'vrai_faux')
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Bonne réponse : Vrai')),
                    ButtonSegment(value: false, label: Text('Bonne réponse : Faux')),
                  ],
                  selected: {_vrai},
                  onSelectionChanged: (s) => setState(() => _vrai = s.first),
                ),
              if (_type == 'texte_trous')
                TextField(
                    controller: _expected,
                    decoration: InputDecoration(labelText: tr('Texte attendu (sans tenir compte de la casse)'))),
              if (_type == 'texte_libre')
                const Text('Réponse libre : elle n’est pas notée automatiquement.', style: TextStyle(height: 1.5)),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(
                    width: 110,
                    child: TextField(
                        controller: _points,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: tr('Points')))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _expl,
                        decoration: InputDecoration(labelText: tr('Explication (facultatif)')))),
              ]),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_editing ? tr('Enregistrer') : tr('Ajouter la question')),
              ),
              if (!_editing) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => context.pop(), child: Text(tr('Terminer ({n} ajoutée(s))', {'n': _added}))),
                const SizedBox(height: 8),
                const Text('Un quiz doit avoir au moins une question pour être publié.',
                    style: TextStyle(fontSize: 12)),
              ],
            ]),
    );
  }
}
