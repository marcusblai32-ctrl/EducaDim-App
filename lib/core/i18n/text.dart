import 'package:flutter/material.dart' as m;
import 'lang.dart';

export 'lang.dart' show tr, Lang;

/// `Text` qui traduit automatiquement les textes de l'interface (FR → KR).
/// Les textes qui ne figurent pas dans la table (ex. titres de cours venant du
/// serveur) restent inchangés. À importer à la place de `Text` du framework :
///   import 'package:flutter/material.dart' hide Text;
///   import '.../core/i18n/text.dart';
class Text extends m.StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  }) : span = null;

  const Text.rich(
    this.span, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  }) : data = null;

  final String? data;
  final m.InlineSpan? span;
  final m.TextStyle? style;
  final m.TextAlign? textAlign;
  final int? maxLines;
  final m.TextOverflow? overflow;
  final bool? softWrap;

  @override
  m.Widget build(m.BuildContext context) {
    if (span != null) {
      return m.Text.rich(span!,
          style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap);
    }
    return m.Text(tr(data ?? ''),
        style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow, softWrap: softWrap);
  }
}
