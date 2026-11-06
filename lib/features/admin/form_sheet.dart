import 'package:flutter/material.dart';

class FieldSpec {
  FieldSpec(this.key, this.label,
      {this.multiline = false,
      this.required = false,
      this.number = false,
      this.options,
      this.initial,
      this.hint,
      this.showIf});
  final String key, label;
  final bool multiline, required, number;
  final Map<String, String>? options; // valeur -> libellé (liste déroulante)
  final String? initial, hint;
  final bool Function(Map<String, String> values)? showIf;
}

/// Petit formulaire modal générique : retourne les valeurs saisies, ou null si annulé.
Future<Map<String, String>?> showFormSheet(
    BuildContext context, String title, List<FieldSpec> fields,
    {String submitLabel = 'Ajouter'}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FormSheet(title, fields, submitLabel),
  );
}

class _FormSheet extends StatefulWidget {
  const _FormSheet(this.title, this.fields, this.submitLabel);
  final String title, submitLabel;
  final List<FieldSpec> fields;
  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _ctrl = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial ?? f.options?.keys.first ?? ''),
  };

  Map<String, String> get _values => {for (final e in _ctrl.entries) e.key: e.value.text};

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            for (final f in widget.fields)
              if (f.showIf == null || f.showIf!(_values))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: f.options != null
                      ? DropdownButtonFormField<String>(
                          initialValue: _ctrl[f.key]!.text,
                          decoration: InputDecoration(labelText: f.label),
                          items: [
                            for (final o in f.options!.entries)
                              DropdownMenuItem(value: o.key, child: Text(o.value)),
                          ],
                          onChanged: (v) => setState(() => _ctrl[f.key]!.text = v ?? ''),
                        )
                      : TextFormField(
                          controller: _ctrl[f.key],
                          minLines: f.multiline ? 3 : 1,
                          maxLines: f.multiline ? 8 : 1,
                          keyboardType: f.number ? TextInputType.number : null,
                          decoration: InputDecoration(labelText: f.label, hintText: f.hint),
                          validator: (v) =>
                              f.required && (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
                        ),
                ),
            FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) Navigator.pop(context, _values);
              },
              child: Text(widget.submitLabel),
            ),
          ]),
        ),
      ),
    );
  }
}
