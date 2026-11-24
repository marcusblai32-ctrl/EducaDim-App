import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/i18n/text.dart';
import 'offline_media.dart';

/// Lecteur PDF d'EducaDim — ouvert dans une page à part, LECTURE SEULE :
/// le fichier n'est chargé qu'en mémoire (rien n'est écrit sur le téléphone, aucun bouton télécharger/partager).
/// 3 modes de lecture : livre (pages qui tournent), défilement vertical, défilement horizontal.
/// Zoom (boutons, pincement, double toucher), saut de page, surlignage (zones) mémorisé sur le téléphone.
enum _Mode { book, vertical, horizontal }

class _Rendered {
  _Rendered(this.bytes, this.ratio);
  final Uint8List bytes;
  final double ratio; // largeur / hauteur
}

class _Hl {
  _Hl(this.page, this.l, this.t, this.r, this.b, this.color);
  final int page;
  final double l, t, r, b; // 0..1 dans la page
  final int color;
  Map<String, dynamic> toJson() => {'p': page, 'l': l, 't': t, 'r': r, 'b': b, 'c': color};
  static _Hl? fromJson(dynamic j) {
    if (j is! Map) return null;
    double d(dynamic v) => v is num ? v.toDouble() : 0;
    return _Hl((j['p'] is num) ? (j['p'] as num).toInt() : 0, d(j['l']), d(j['t']), d(j['r']), d(j['b']),
        (j['c'] is num) ? (j['c'] as num).toInt() : 0xFFFFEB3B);
  }
}

const _hlColors = [0xFFFFEB3B, 0xFF66BB6A, 0xFF4FC3F7, 0xFFFF8A80];

String _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

class OnlinePdfScreen extends StatefulWidget {
  const OnlinePdfScreen(this.url, {super.key, this.title});
  final String url;
  final String? title;
  @override
  State<OnlinePdfScreen> createState() => _OnlinePdfScreenState();
}

class _OnlinePdfScreenState extends State<OnlinePdfScreen> {
  PdfDocument? _doc;
  int _count = 0;
  String? _error;

  _Mode _mode = _Mode.vertical;
  double _zoom = 1.0;
  int _current = 0;
  bool _hlMode = false;
  int _hlColor = _hlColors[0];
  final List<_Hl> _hls = [];

  final Map<int, _Rendered> _cache = {};
  final Map<int, Future<_Rendered?>> _pending = {};
  final Map<int, double> _ratios = {};
  Future<void> _chain = Future.value();

  final PageController _pc = PageController();
  final ScrollController _vc = ScrollController();
  final ScrollController _hc = ScrollController();
  double _extent = 600; // hauteur (vertical) ou largeur (horizontal) d'une page affichée

  final Map<int, Offset> _ptrs = {};
  double? _pinchD, _pinchZ;

  late final String _key = 'pdfv_${_fnv(Uri.tryParse(widget.url)?.path ?? widget.url)}';

  @override
  void initState() {
    super.initState();
    _vc.addListener(() => _onScroll(_vc));
    _hc.addListener(() => _onScroll(_hc));
    _load();
  }

  @override
  void dispose() {
    _save();
    _pc.dispose();
    _vc.dispose();
    _hc.dispose();
    _doc?.close();
    super.dispose();
  }

  // ---------- chargement ----------
  Future<void> _load() async {
    try {
      // Hors ligne : copie locale si le cours est téléchargé, sinon réseau (en mémoire seulement).
      List<int>? data;
      final local = await OfflineMedia.localFile(widget.url);
      if (local != null) {
        try {
          data = await File(local).readAsBytes();
        } catch (_) {}
      }
      if (data == null) {
        final res = await Dio().get<List<int>>(widget.url,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 90)));
        data = res.data;
      }
      if (data == null || data.isEmpty) {
        if (mounted) setState(() => _error = tr('Ce document est indisponible.'));
        return;
      }
      final doc = await PdfDocument.openData(Uint8List.fromList(data));
      await _restore();
      if (!mounted) {
        doc.close();
        return;
      }
      setState(() {
        _doc = doc;
        _count = doc.pagesCount;
        _current = _current.clamp(0, math.max(0, _count - 1)).toInt();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump(_current));
    } catch (_) {
      if (mounted) setState(() => _error = tr('Impossible de charger le document. Vérifiez votre connexion.'));
    }
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      final mi = m['mode'];
      if (mi is int && mi >= 0 && mi < _Mode.values.length) _mode = _Mode.values[mi];
      if (m['page'] is num) _current = (m['page'] as num).toInt();
      for (final h in (m['hl'] as List? ?? [])) {
        final x = _Hl.fromJson(h);
        if (x != null) _hls.add(x);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode({'mode': _mode.index, 'page': _current, 'hl': _hls.map((e) => e.toJson()).toList()}));
    } catch (_) {}
  }

  // ---------- rendu des pages (une à la fois : plus sûr avec pdfx) ----------
  Future<T> _enqueue<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        c.complete(await job());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  Future<_Rendered?> _render(int i) {
    final hit = _cache[i];
    if (hit != null) return Future.value(hit);
    return _pending[i] ??= _enqueue(() => _renderNow(i)).whenComplete(() => _pending.remove(i));
  }

  Future<_Rendered?> _renderNow(int i) async {
    final doc = _doc;
    if (doc == null) return null;
    final page = await doc.getPage(i + 1);
    try {
      const w = 1400.0;
      final h = w * page.height / page.width;
      final img = await page.render(width: w, height: h, format: PdfPageImageFormat.jpeg, backgroundColor: '#FFFFFF', quality: 90);
      if (img == null) return null;
      final r = _Rendered(img.bytes, page.width / page.height);
      _ratios[i] = r.ratio;
      _cache[i] = r;
      while (_cache.length > 12) {
        _cache.remove(_cache.keys.first);
      }
      return r;
    } finally {
      await page.close();
    }
  }

  double _ratioOf(int i) => _ratios[i] ?? (_ratios.isNotEmpty ? _ratios.values.first : 0.707);

  // ---------- navigation ----------
  void _onScroll(ScrollController c) {
    if (!c.hasClients || _extent <= 0) return;
    final i = (c.offset / _extent).round().clamp(0, math.max(0, _count - 1)).toInt();
    if (i != _current) setState(() => _current = i);
  }

  void _jump(int i) {
    if (_count == 0) return;
    i = i.clamp(0, _count - 1).toInt();
    if (_mode == _Mode.book || _hlMode) {
      if (_pc.hasClients) _pc.jumpToPage(i);
    } else if (_mode == _Mode.vertical) {
      if (_vc.hasClients) _vc.jumpTo(math.min(i * _extent, _vc.position.maxScrollExtent));
    } else {
      if (_hc.hasClients) _hc.jumpTo(math.min(i * _extent, _hc.position.maxScrollExtent));
    }
    if (_current != i) setState(() => _current = i);
  }

  void _setMode(_Mode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _hlMode = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jump(_current));
    _save();
  }

  void _setZoom(double z) {
    setState(() => _zoom = z.clamp(1.0, 4.0).toDouble());
    WidgetsBinding.instance.addPostFrameCallback((_) => _jump(_current));
  }

  void _toggleHl() {
    setState(() {
      _hlMode = !_hlMode;
      if (_hlMode) _zoom = 1.0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jump(_current));
  }

  Future<void> _askPage() async {
    final ctl = TextEditingController(text: '${_current + 1}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Aller à la page')),
        content: TextField(controller: ctl, keyboardType: TextInputType.number, autofocus: true,
            decoration: InputDecoration(hintText: '1 – $_count')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim())), child: Text(tr('Aller'))),
        ],
      ),
    );
    if (v != null) _jump(v - 1);
  }

  // ---------- gestes : pincement + double toucher ----------
  void _ptrDown(PointerDownEvent e) => _ptrs[e.pointer] = e.position;
  void _ptrMove(PointerMoveEvent e) {
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.position;
    if (_ptrs.length == 2 && !_hlMode) {
      final pts = _ptrs.values.toList();
      final d = (pts[0] - pts[1]).distance;
      if (_pinchD == null) {
        _pinchD = d;
        _pinchZ = _zoom;
      } else if (_pinchD! > 10) {
        final z = (_pinchZ! * d / _pinchD!).clamp(1.0, 4.0).toDouble();
        if ((z - _zoom).abs() > 0.02) setState(() => _zoom = z);
      }
    }
  }

  void _ptrEnd(PointerEvent e) {
    _ptrs.remove(e.pointer);
    if (_ptrs.length < 2 && _pinchD != null) {
      _pinchD = null;
      _pinchZ = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump(_current));
    }
  }

  // ---------- pages ----------
  Widget _tile(int i, double width, {bool editing = false}) => _PageTile(
        key: ValueKey('t$i-${width.round()}-$editing'),
        index: i,
        width: width,
        render: _render,
        ratio: _ratioOf(i),
        highlights: _hls.where((h) => h.page == i).toList(),
        editing: editing,
        color: _hlColor,
        onAdd: (h) {
          setState(() => _hls.add(h));
          _save();
        },
        onRemove: (h) {
          setState(() => _hls.remove(h));
          _save();
        },
      );

  Widget _body() {
    return LayoutBuilder(builder: (context, c) {
      if (_hlMode) return _hlView(c);
      switch (_mode) {
        case _Mode.book:
          return _bookView(c);
        case _Mode.vertical:
          return _verticalView(c);
        case _Mode.horizontal:
          return _horizontalView(c);
      }
    });
  }

  Widget _zoomWrap(Widget tile, BoxConstraints c) {
    if (_zoom <= 1.001) return Center(child: tile);
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth, minHeight: c.maxHeight),
          child: Center(child: tile),
        ),
      ),
    );
  }

  Widget _bookView(BoxConstraints c) {
    return PageView.builder(
      controller: _pc,
      itemCount: _count,
      physics: _zoom > 1.001 ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
      onPageChanged: (i) => setState(() => _current = i),
      itemBuilder: (_, i) {
        final fitW = math.min(c.maxWidth - 16, (c.maxHeight - 16) * _ratioOf(i));
        final page = _zoomWrap(_tile(i, fitW * _zoom), c);
        return AnimatedBuilder(
          animation: _pc,
          builder: (_, child) {
            double delta = 0;
            if (_pc.hasClients && _pc.position.haveDimensions) delta = i - (_pc.page ?? _current.toDouble());
            delta = delta.clamp(-1.0, 1.0).toDouble();
            return Transform(
              alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(delta * 0.85),
              child: child,
            );
          },
          child: page,
        );
      },
    );
  }

  Widget _verticalView(BoxConstraints c) {
    final w = (c.maxWidth - 16) * _zoom;
    _extent = w / _ratioOf(0) + 12;
    final list = ListView.builder(
      controller: _vc,
      itemCount: _count,
      itemExtent: _extent,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: FittedBox(fit: BoxFit.contain, child: _tile(i, w)),
      ),
    );
    if (_zoom <= 1.001) return list;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: w + 16, height: c.maxHeight, child: list),
    );
  }

  Widget _horizontalView(BoxConstraints c) {
    final fitW = math.min((c.maxWidth - 16) * 0.92, (c.maxHeight - 16) * _ratioOf(0));
    final w = fitW * _zoom;
    _extent = w + 12;
    return ListView.builder(
      controller: _hc,
      scrollDirection: Axis.horizontal,
      itemCount: _count,
      itemExtent: _extent,
      itemBuilder: (_, i) => SizedBox(
        width: _extent,
        child: _zoom > 1.001
            ? SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _tile(i, w)))
            : Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: _tile(i, w))),
      ),
    );
  }

  /// Surlignage : une page à la fois, ajustée à l'écran (le doigt dessine un rectangle ; toucher un rectangle l'enlève).
  Widget _hlView(BoxConstraints c) {
    return PageView.builder(
      controller: _pc,
      itemCount: _count,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (_, i) {
        final fitW = math.min(c.maxWidth - 16, (c.maxHeight - 16) * _ratioOf(i));
        return Center(child: _tile(i, fitW, editing: true));
      },
    );
  }

  // ---------- interface ----------
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? tr('Document'), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_doc != null) ...[
            PopupMenuButton<_Mode>(
              tooltip: tr('Mode de lecture'),
              icon: Icon(_mode == _Mode.book
                  ? Icons.auto_stories_rounded
                  : _mode == _Mode.vertical
                      ? Icons.swap_vert_rounded
                      : Icons.swap_horiz_rounded),
              onSelected: _setMode,
              itemBuilder: (_) => [
                CheckedPopupMenuItem(value: _Mode.book, checked: _mode == _Mode.book, child: Text(tr('Livre (pages qui tournent)'))),
                CheckedPopupMenuItem(value: _Mode.vertical, checked: _mode == _Mode.vertical, child: Text(tr('Défilement vertical'))),
                CheckedPopupMenuItem(value: _Mode.horizontal, checked: _mode == _Mode.horizontal, child: Text(tr('Défilement horizontal'))),
              ],
            ),
            IconButton(
              tooltip: tr('Surligner'),
              icon: Icon(Icons.border_color_rounded, color: _hlMode ? Color(_hlColor) : null),
              onPressed: _toggleHl,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'goto') _askPage();
                if (v == 'clear') {
                  setState(() => _hls.removeWhere((h) => h.page == _current));
                  _save();
                }
                if (v == 'clearall') {
                  setState(_hls.clear);
                  _save();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'goto', child: Text(tr('Aller à la page…'))),
                PopupMenuItem(value: 'clear', child: Text(tr('Effacer les surlignages de cette page'))),
                PopupMenuItem(value: 'clearall', child: Text(tr('Effacer tous les surlignages'))),
              ],
            ),
          ],
        ],
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _doc == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _ptrDown,
                      onPointerMove: _ptrMove,
                      onPointerUp: _ptrEnd,
                      onPointerCancel: _ptrEnd,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: _hlMode ? null : () => _setZoom(_zoom > 1.001 ? 1.0 : 2.0),
                        child: Container(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: _body()),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_hlMode)
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(tr('Dessinez avec le doigt · toucher un trait pour l’enlever'), style: TextStyle(fontSize: 11.5, color: muted)),
                          ]),
                        if (_hlMode)
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            for (final col in _hlColors)
                              GestureDetector(
                                onTap: () => setState(() => _hlColor = col),
                                child: Container(
                                  margin: const EdgeInsets.all(6),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Color(col),
                                    shape: BoxShape.circle,
                                    border: Border.all(width: _hlColor == col ? 3 : 1, color: _hlColor == col ? Colors.black54 : Colors.black26),
                                  ),
                                ),
                              ),
                          ]),
                        Row(children: [
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.chevron_left_rounded),
                              onPressed: _current > 0 ? () => _jump(_current - 1) : null),
                          Expanded(
                            child: Slider(
                              min: 1,
                              max: math.max(2, _count).toDouble(),
                              divisions: _count > 1 ? _count - 1 : null,
                              value: (_current + 1).clamp(1, math.max(2, _count)).toDouble(),
                              onChanged: _count > 1 ? (v) => _jump(v.round() - 1) : null,
                            ),
                          ),
                          InkWell(
                              onTap: _askPage,
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  child: Text('${_current + 1} / $_count', style: const TextStyle(fontWeight: FontWeight.w700)))),
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.chevron_right_rounded),
                              onPressed: _current < _count - 1 ? () => _jump(_current + 1) : null),
                        ]),
                        if (!_hlMode)
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            IconButton(
                                tooltip: tr('Zoom -'),
                                icon: const Icon(Icons.zoom_out_rounded),
                                onPressed: _zoom > 1.001 ? () => _setZoom(_zoom - 0.5) : null),
                            SizedBox(
                                width: 64,
                                child: Text('${(_zoom * 100).round()} %', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                            IconButton(
                                tooltip: tr('Zoom +'),
                                icon: const Icon(Icons.zoom_in_rounded),
                                onPressed: _zoom < 3.999 ? () => _setZoom(_zoom + 0.5) : null),
                          ]),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}

/// Une page : image + traits de surlignage ; en mode surlignage, le doigt dessine un rectangle.
class _PageTile extends StatefulWidget {
  const _PageTile({
    super.key,
    required this.index,
    required this.width,
    required this.render,
    required this.ratio,
    required this.highlights,
    required this.editing,
    required this.color,
    required this.onAdd,
    required this.onRemove,
  });
  final int index;
  final double width;
  final Future<_Rendered?> Function(int) render;
  final double ratio;
  final List<_Hl> highlights;
  final bool editing;
  final int color;
  final void Function(_Hl) onAdd;
  final void Function(_Hl) onRemove;
  @override
  State<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends State<_PageTile> {
  late Future<_Rendered?> _f = widget.render(widget.index);
  Offset? _a, _b;

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    return FutureBuilder<_Rendered?>(
      future: _f,
      builder: (context, snap) {
        final r = snap.data;
        final ratio = r?.ratio ?? widget.ratio;
        final h = w / ratio;
        Widget content;
        if (r == null) {
          content = Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: snap.hasError || snap.connectionState == ConnectionState.done
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextButton(
                        onPressed: () => setState(() => _f = widget.render(widget.index)),
                        child: Text(tr('Page illisible — réessayer'))))
                : const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        } else {
          content = Stack(fit: StackFit.expand, children: [
            Image.memory(r.bytes, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
            CustomPaint(painter: _HlPainter(widget.highlights, _a, _b, widget.color)),
            if (widget.editing)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => setState(() {
                  _a = d.localPosition;
                  _b = d.localPosition;
                }),
                onPanUpdate: (d) => setState(() => _b = d.localPosition),
                onPanEnd: (_) {
                  final a = _a, b = _b;
                  setState(() {
                    _a = null;
                    _b = null;
                  });
                  if (a == null || b == null) return;
                  final l = (math.min(a.dx, b.dx) / w).clamp(0.0, 1.0).toDouble();
                  final rr = (math.max(a.dx, b.dx) / w).clamp(0.0, 1.0).toDouble();
                  final t = (math.min(a.dy, b.dy) / h).clamp(0.0, 1.0).toDouble();
                  final bb = (math.max(a.dy, b.dy) / h).clamp(0.0, 1.0).toDouble();
                  if (rr - l < 0.02 || bb - t < 0.004) return;
                  widget.onAdd(_Hl(widget.index, l, t, rr, bb, widget.color));
                },
                onTapUp: (d) {
                  final x = d.localPosition.dx / w, y = d.localPosition.dy / h;
                  for (final hl in widget.highlights.reversed) {
                    if (x >= hl.l && x <= hl.r && y >= hl.t && y <= hl.b) {
                      widget.onRemove(hl);
                      return;
                    }
                  }
                },
              ),
          ]);
        }
        return Container(
          width: w,
          height: h,
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))]),
          child: content,
        );
      },
    );
  }
}

class _HlPainter extends CustomPainter {
  _HlPainter(this.hls, this.a, this.b, this.color);
  final List<_Hl> hls;
  final Offset? a, b;
  final int color;

  @override
  void paint(Canvas canvas, Size s) {
    for (final h in hls) {
      canvas.drawRect(Rect.fromLTRB(h.l * s.width, h.t * s.height, h.r * s.width, h.b * s.height),
          Paint()..color = Color(h.color).withValues(alpha: 0.42));
    }
    if (a != null && b != null) {
      canvas.drawRect(Rect.fromPoints(a!, b!), Paint()..color = Color(color).withValues(alpha: 0.42));
    }
  }

  @override
  bool shouldRepaint(covariant _HlPainter o) => true;
}
