import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import 'admin_repository.dart';
import 'form_sheet.dart';

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

String _msg(Object e) => e is ApiException
    ? (e.isOffline ? 'Connexion requise pour cette action.' : e.message)
    : 'Une erreur est survenue.';

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
        backgroundColor: EdColors.red,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
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
              const Text(
                  'Les cours créés ici sont des brouillons : publiez-les quand ils sont prêts.',
                  style: TextStyle(height: 1.5)),
              const SizedBox(height: 12),
              for (final c in courses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: Icon(c['publie'] == true ? Icons.public : Icons.edit_note_rounded,
                          color: c['publie'] == true ? EdColors.good : EdColors.blue),
                      title: Text('${c['titre']}'),
                      subtitle: Text(
                          '${c['publie'] == true ? 'Publié' : 'Brouillon'} · ${c['unites_count']} unité(s)'),
                      trailing: const Icon(Icons.chevron_right),
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
  final _prix = TextEditingController(text: '0');
  final _duree = TextEditingController(text: '0');
  int? _cat, _niv;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_titre, _desc, _prix, _duree]) {
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
          decoration: const InputDecoration(labelText: 'Titre du cours'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextFormField(
                  controller: _prix,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Prix (HTG, 0 = gratuit)'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextFormField(
                  controller: _duree,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée (heures)'))),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _cat,
          decoration: const InputDecoration(labelText: 'Catégorie'),
          items: [for (final c in cats) DropdownMenuItem(value: c['id'] as int, child: Text('${c['nom']}'))],
          onChanged: (v) => _cat = v,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _niv,
          decoration: const InputDecoration(labelText: 'Niveau'),
          items: [for (final n in nivs) DropdownMenuItem(value: n['id'] as int, child: Text('${n['label']}'))],
          onChanged: (v) => _niv = v,
        ),
        const SizedBox(height: 18),
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

  Future<void> _addUnite() async {
    final v = await showFormSheet(context, 'Nouvelle unité', [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('description', 'Description', multiline: true),
    ]);
    if (v == null) return;
    await _run(() => _repo.createUnite(widget.courseId, v), 'Unité ajoutée.');
  }

  Future<void> _addModule(int uniteId) async {
    final v = await showFormSheet(context, 'Nouveau module', [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('description', 'Description', multiline: true),
    ]);
    if (v == null) return;
    await _run(() => _repo.createModule(uniteId, v), 'Module ajouté.');
  }

  Future<void> _addLecon(int moduleId) async {
    final v = await showFormSheet(context, 'Nouvelle leçon', [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('description', 'Description', multiline: true),
      FieldSpec('contenu', 'Texte de la leçon (facultatif)', multiline: true),
    ]);
    if (v == null) return;
    await _run(() => _repo.createLecon(moduleId, v), 'Leçon ajoutée.');
  }

  Future<void> _addSection(int leconId, Map meta) async {
    final types = {for (final t in (meta['section_types'] as List)) '${t['value']}': '${t['label']}'};
    final v = await showFormSheet(context, 'Nouvelle section', [
      FieldSpec('titre', 'Titre', required: true),
      FieldSpec('type_section', 'Type', options: types, initial: 'developpement'),
    ]);
    if (v == null) return;
    await _run(() => _repo.createSection(leconId, v), 'Section ajoutée.');
  }

  Future<void> _addContenu(int sectionId) async {
    final v = await showFormSheet(context, 'Nouveau contenu', [
      FieldSpec('type_contenu', 'Type', options: const {
        'texte': 'Texte',
        'video': 'Vidéo (URL)',
        'audio': 'Audio (URL)',
        'image': 'Image (URL)',
        'pdf': 'PDF (URL)',
        'lien': 'Lien externe',
      }),
      FieldSpec('titre', 'Titre (facultatif)'),
      FieldSpec('texte', 'Texte',
          multiline: true, required: true, showIf: (x) => x['type_contenu'] == 'texte'),
      FieldSpec('url', 'URL (https://…)',
          required: true, hint: 'https://', showIf: (x) => x['type_contenu'] != 'texte'),
    ]);
    if (v == null) return;
    await _run(() => _repo.createContenu(sectionId, v), 'Contenu ajouté.');
  }

  Future<void> _addQuiz(String niveau, int parentId) async {
    final v = await showFormSheet(context, 'Nouveau quiz', [
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
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${course['titre']}', style: t.textTheme.titleMedium),
                      Text(course['publie'] == true ? 'Publié' : 'Brouillon (invisible pour les étudiants)',
                          style: t.textTheme.bodySmall),
                    ])),
                    Switch(
                      value: course['publie'] == true,
                      onChanged: (v) => _run(() => _repo.setCoursePublished(widget.courseId, v),
                          v ? 'Cours publié.' : 'Cours repassé en brouillon.'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Text('Programme', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (unites.isEmpty) const Text('Aucune unité. Commencez par en ajouter une.'),
              for (final u in unites) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.folder_outlined, size: 20, color: EdColors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('${u['titre']}',
                                style: const TextStyle(fontWeight: FontWeight.w800))),
                        TextButton.icon(
                            onPressed: () => _addModule(u['id'] as int),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Module')),
                      ]),
                      for (final m in (u['modules'] as List)) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Row(children: [
                            const Icon(Icons.view_module_outlined, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text('${m['titre']}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700, color: t.colorScheme.primary))),
                            PopupMenuButton<String>(
                              tooltip: 'Actions du module',
                              onSelected: (a) =>
                                  a == 'lecon' ? _addLecon(m['id'] as int) : _addQuiz('module', m['id'] as int),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'lecon', child: Text('Ajouter une leçon')),
                                PopupMenuItem(value: 'quiz', child: Text('Ajouter un quiz au module')),
                              ],
                            ),
                          ]),
                        ),
                        for (final l in (m['lecons'] as List)) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 30),
                            child: Row(children: [
                              const Icon(Icons.menu_book_outlined, size: 18),
                              const SizedBox(width: 6),
                              Expanded(child: Text('${l['titre']}')),
                              PopupMenuButton<String>(
                                tooltip: 'Actions de la leçon',
                                onSelected: (a) => a == 'section'
                                    ? _addSection(l['id'] as int, meta)
                                    : _addQuiz('lecon', l['id'] as int),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'section', child: Text('Ajouter une section')),
                                  PopupMenuItem(value: 'quiz', child: Text('Ajouter un quiz à la leçon')),
                                ],
                              ),
                            ]),
                          ),
                          for (final s in (l['sections'] as List))
                            Padding(
                              padding: const EdgeInsets.only(left: 48),
                              child: Row(children: [
                                const Icon(Icons.segment, size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text('${s['titre']} · ${s['contenus_count']} contenu(s)',
                                        style: t.textTheme.bodySmall)),
                                IconButton(
                                  tooltip: 'Ajouter un contenu',
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  onPressed: () => _addContenu(s['id'] as int),
                                ),
                              ]),
                            ),
                        ],
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                  onPressed: _addUnite,
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une unité')),
              const SizedBox(height: 22),
              Text('Quiz', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (quizzes.isEmpty) const Text('Aucun quiz pour ce cours.'),
              for (final q in quizzes)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.quiz_outlined, color: EdColors.blue),
                    title: Text('${q['titre']}'),
                    subtitle: Text(
                        '${q['niveau']} · ${q['questions_count']} question(s) · ${q['publie'] == true ? 'publié' : 'brouillon'}'),
                    onTap: () async {
                      await context.push('/admin/quiz/${q['id']}/question', extra: '${q['titre']}');
                      if (mounted) setState(() => _v++);
                    },
                    trailing: Switch(
                      value: q['publie'] == true,
                      onChanged: (v) => _run(() => _repo.setQuizPublished(q['id'] as int, v),
                          v ? 'Quiz publié.' : 'Quiz repassé en brouillon.'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => _addQuiz('cours', widget.courseId),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter un quiz au cours')),
            ]),
          );
        },
      ),
    );
  }
}

// ======================= Ajouter des questions =======================

class AdminQuestionScreen extends StatefulWidget {
  const AdminQuestionScreen(this.quizId, {super.key, this.title});
  final int quizId;
  final String? title;
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
  final List<TextEditingController> _ans = [TextEditingController(), TextEditingController()];
  final Set<int> _correct = {};
  bool _vrai = true;
  bool _busy = false;
  int _added = 0;

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
      _snack(context, 'Écrivez l’énoncé de la question.');
      return;
    }
    setState(() => _busy = true);
    try {
      final data = <String, dynamic>{
        'type_question': _type,
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
      await context.read<AdminRepository>().addQuestion(widget.quizId, data);
      if (!mounted) return;
      setState(() {
        _added++;
        _reset();
      });
      _snack(context, 'Question ajoutée ($_added dans cette séance).');
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
      appBar: AppBar(title: Text(widget.title ?? 'Questions du quiz', overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type de question'),
          items: [for (final e in _types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() {
            _type = v ?? 'single';
            _correct.clear();
          }),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _texte,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Énoncé de la question')),
        const SizedBox(height: 12),
        if (choice) ...[
          const Text('Réponses (cochez la ou les bonnes)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (var i = 0; i < _ans.length; i++)
            Row(children: [
              IconButton(
                tooltip: 'Bonne réponse',
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
                      controller: _ans[i], decoration: InputDecoration(labelText: 'Réponse ${i + 1}'))),
              if (_ans.length > 2)
                IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _ans.removeAt(i).dispose();
                    _correct
                      ..clear();
                  }),
                ),
            ]),
          TextButton.icon(
              onPressed: _ans.length >= 8 ? null : () => setState(() => _ans.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une réponse')),
        ],
        if (_type == 'vrai_faux')
          SegmentedButton<bool>(
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
              decoration: const InputDecoration(labelText: 'Texte attendu (comparé sans tenir compte de la casse)')),
        if (_type == 'texte_libre')
          const Text('Réponse libre : elle n’est pas notée automatiquement.', style: TextStyle(height: 1.5)),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(
              width: 110,
              child: TextField(
                  controller: _points,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Points'))),
          const SizedBox(width: 12),
          Expanded(
              child: TextField(
                  controller: _expl, decoration: const InputDecoration(labelText: 'Explication (facultatif)'))),
        ]),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Ajouter la question'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => context.pop(), child: Text('Terminer ($_added ajoutée(s))')),
        const SizedBox(height: 8),
        const Text('Un quiz doit avoir au moins une question pour être publié.',
            style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}
