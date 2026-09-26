import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/admin_help_service.dart';
import '../../services/admin_services.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_help_modals.dart';
import 'admin_list.dart';
import '../../widgets/tp_loader.dart';

const _kDefaultCats = [
  HelpCategoryNode('v1', 'V1', []),
  HelpCategoryNode('v2', 'V2', []),
  HelpCategoryNode('invoice', 'Invoice', []),
  HelpCategoryNode('crm', 'CRM', []),
];

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, required this.service});
  final HelpService service;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> with LiveRefresh<HelpScreen> {
  late final AdminHelpApi _api = AdminHelpApi(widget.service.api);
  List<HelpCategoryNode> _cats = _kDefaultCats;
  List<Map<String, dynamic>> _topics = const [];
  final Set<int> _hidden = {};
  bool _loading = true;
  String? _error;
  String _cat = 'all';
  String _sub = '';
  String _subSub = '';
  bool _opening = false;
  List<List<int>> _rows = const [];

  HelpTaxonomy get _tx => HelpTaxonomy(_cats);

  @override
  void initState() {
    super.initState();
    _loadCategories().whenComplete(() async {
      await _loadTopics();
      if (!kDebugMode) return;
      final open = int.tryParse(Platform.environment['TP_HELP_OPEN_TOPIC'] ?? '');
      if (open != null && mounted) _openTopic(open);
      if (Platform.environment['TP_HELP_ADD'] == '1' && mounted) _addTopic();
    });
  }

  @override
  List<String> get liveKeys => const ['helpPage'];

  @override
  void onLiveChange() => _loadCategories().whenComplete(() => _loadTopics(silent: true));

  Future<void> _loadCategories() async {
    try {
      final cats = await _api.categories();
      if (!mounted) return;
      setState(() {
        if (cats.isNotEmpty) _cats = cats;
        if (_cat != 'all' && _tx.cat(_cat) == null) {
          _cat = 'all';
          _sub = '';
          _subSub = '';
        }
        if (_sub.isNotEmpty) _sub = _tx.normSub(_cat, _sub);
        _subSub = _sub.isNotEmpty ? _tx.normSubSub(_cat, _sub, _subSub) : '';
      });
    } catch (_) {}
  }

  Future<void> _loadTopics({bool silent = false}) async {
    if (!silent && _topics.isEmpty) setState(() => _loading = true);
    try {
      final topics = await _api.topics();
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_topics.isEmpty) _error = '$e';
      });
      if (!silent) toast(context, 'Failed to load help topics');
    }
  }

  int _idOf(Map t) => int.tryParse('${t['id']}') ?? 0;

  String _normCat(Map t) => _tx.normCat('${t['category'] ?? ''}');
  String _normSub(Map t) => _tx.normSub(_normCat(t), '${t['subcategory'] ?? ''}');
  String _normSubSub(Map t) =>
      _tx.normSubSub(_normCat(t), _normSub(t), '${t['subsubcategory'] ?? ''}');

  String _subName(String cat, String sub) => _tx.sub(cat, sub)?.name ?? '';

  String _subSubName(String cat, String sub, String ss) {
    for (final d in _tx.sub(cat, sub)?.subs ?? const <HelpCategoryNode>[]) {
      if (d.slug == ss) return d.name;
    }
    return '';
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _topics.where((t) => !_hidden.contains(_idOf(t))).toList();
    if (_cat != 'all') {
      list = list.where((t) => _normCat(t) == _cat).toList();
      if (_sub.isNotEmpty) {
        list = list.where((t) => _normSub(t) == _sub).toList();
        if (_subSub.isNotEmpty) {
          list = list.where((t) => _normSubSub(t) == _subSub).toList();
        }
      }
    }
    return list;
  }

  List<({String label, List<Map<String, dynamic>> items})> _groups(
    List<Map<String, dynamic>> topics,
    List<Map<String, dynamic>> ungrouped,
  ) {
    final showCat = _cat == 'all';
    final showSub = _sub.isEmpty;
    String label(String c, String s, String d) {
      final parts = [if (showCat) c, if (showSub) s, d].where((e) => e.isNotEmpty);
      return parts.isEmpty ? (d.isNotEmpty ? d : (s.isNotEmpty ? s : c)) : parts.join(' · ');
    }

    final order = <String>[];
    final map = <String, ({String label, List<Map<String, dynamic>> items})>{};
    void ensure(String key, String l) {
      if (!map.containsKey(key)) {
        map[key] = (label: l, items: <Map<String, dynamic>>[]);
        order.add(key);
      }
    }

    for (final c in _cats) {
      if (!showCat && c.slug != _cat) continue;
      for (final s in c.subs) {
        if (_sub.isNotEmpty && s.slug != _sub) continue;
        ensure('${c.slug}|${s.slug}|', label(c.name, s.name, ''));
        for (final d in s.subs) {
          if (_subSub.isNotEmpty && d.slug != _subSub) continue;
          ensure('${c.slug}|${s.slug}|${d.slug}', label(c.name, s.name, d.name));
        }
      }
    }
    for (final t in topics) {
      final c = _normCat(t);
      final s = _normSub(t);
      if (s.isEmpty) {
        ungrouped.add(t);
        continue;
      }
      final d = _normSubSub(t);
      final key = '$c|$s|$d';
      ensure(
        key,
        label(_tx.cat(c)?.name ?? c.toUpperCase(), _subName(c, s), d.isEmpty ? '' : _subSubName(c, s, d)),
      );
      map[key]!.items.add(t);
    }
    return [
      for (final k in order)
        if (map[k]!.items.isNotEmpty) map[k]!,
    ];
  }

  Future<void> _openTopic(int id) async {
    if (_opening) return;
    setState(() => _opening = true);
    Map<String, dynamic>? doc;
    try {
      doc = await _api.document(id);
      if (doc['success'] != true) {
        if (mounted) toast(context, 'Failed to load topic');
        doc = null;
      }
    } catch (_) {
      if (mounted) toast(context, 'Error opening help topic');
      doc = null;
    }
    if (mounted) setState(() => _opening = false);
    if (doc == null || !mounted) return;
    final result = await showHelpEditTopicModal(
      context,
      api: _api,
      taxonomy: _tx,
      topic: Map<String, dynamic>.from(doc['topic'] as Map),
      html: '${doc['html'] ?? ''}',
    );
    if (!mounted) return;
    if (result == HelpEditResult.saved) _loadTopics();
    if (result == HelpEditResult.delete) _deleteTopic(id);
  }

  void _deleteTopic(int id) {
    setState(() => _hidden.add(id));
    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final timer = Timer(const Duration(seconds: 5), () async {
      if (undone) return;
      messenger.hideCurrentSnackBar();
      try {
        final res = await _api.deleteTopic(id);
        if (res['success'] != true && mounted) {
          toast(context, 'Error deleting topic: ${res['message']}');
        }
      } catch (_) {
        if (mounted) toast(context, 'Error deleting topic');
      }
      if (!mounted) return;
      setState(() => _hidden.remove(id));
      _loadTopics(silent: true);
    });
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Help topic deleted'),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (undone) return;
            undone = true;
            timer.cancel();
            if (!mounted) return;
            setState(() => _hidden.remove(id));
            toast(context, 'Delete undone');
          },
        ),
      ),
    );
  }

  Future<void> _addTopic() async {
    final ok = await showHelpAddTopicModal(context, api: _api, taxonomy: _tx);
    if (ok && mounted) _loadTopics();
  }

  Future<void> _addCategory() async {
    final res = await showHelpCategoryModal(context, api: _api, taxonomy: _tx);
    if (res != null && mounted) await _loadCategories();
  }

  Future<void> _confirmDeleteSub(String cat, String sub, String subSub, String label) async {
    final deep = subSub.isNotEmpty;
    final ok = await confirmDialog(
      context,
      title: deep ? 'Delete this subcategory?' : 'Delete this category?',
      message: deep
          ? '"$label" will be removed. Topics under it stay, but lose the subcategory.'
          : '"$label" and its subcategories will be removed. Topics under it stay, but lose the category.',
      confirmLabel: deep ? 'Delete subcategory' : 'Delete category',
    );
    if (!ok || !mounted) return;
    final noun = deep ? 'Subcategory' : 'Category';
    try {
      final res = await _api.deleteSubcategory(cat, sub, subSub);
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, '${res['message'] ?? 'Could not delete the ${noun.toLowerCase()}'}');
        return;
      }
      setState(() {
        if (deep) {
          if (_subSub == subSub) _subSub = '';
        } else if (_sub == sub) {
          _sub = '';
          _subSub = '';
        }
      });
      toast(context, '$noun "$label" deleted');
      await _loadCategories();
      await _loadTopics(silent: true);
    } catch (_) {
      if (mounted) toast(context, 'Error deleting the ${noun.toLowerCase()}');
    }
  }

  void _moveCard(int dragged, int target) {
    if (dragged == target) return;
    final rows = [for (final r in _rows) List<int>.from(r)];
    final row = rows.firstWhere((r) => r.contains(dragged) && r.contains(target), orElse: () => const []);
    if (row.isEmpty) return;
    final to = row.indexOf(target);
    row.remove(dragged);
    row.insert(to, dragged);
    final payload = [for (final r in rows) ...r].where((id) => id > 0).toList();
    final ids = payload.toSet();
    final slots = <int>[];
    for (var i = 0; i < _topics.length; i++) {
      if (ids.contains(_idOf(_topics[i]))) slots.add(i);
    }
    final byId = {for (final t in _topics) _idOf(t): t};
    final next = List<Map<String, dynamic>>.from(_topics);
    for (var i = 0; i < payload.length && i < slots.length; i++) {
      final t = byId[payload[i]];
      if (t != null) next[slots[i]] = t;
    }
    setState(() => _topics = next);
    _api.reorder(payload).then((res) {
      if (res['success'] != true && mounted) {
        toast(context, '${res['message'] ?? 'Could not save the new order'}');
        _loadTopics(silent: true);
      }
    }).catchError((_) {
      if (mounted) {
        toast(context, 'Could not save the new order');
        _loadTopics(silent: true);
      }
    });
  }

  Widget _chip(String label, bool active, VoidCallback onTap, {bool solid = false, VoidCallback? onDelete}) {
    return Material(
      color: active ? (solid ? Brand.signal : const Color(0xFFFFF4EA)) : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: active ? Brand.signal : const Color(0xFFE7E5E4), width: 1.5),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(15, 6, onDelete == null ? 15 : 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? (solid ? Colors.white : Brand.signal) : const Color(0xFF78716C),
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Delete $label',
                  child: InkWell(
                    onTap: onDelete,
                    customBorder: const CircleBorder(),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: active ? (solid ? Colors.white : Brand.signal) : const Color(0xFFA8A29E),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  ({Color bg, Color fg, Color border}) _catColors(String slug) {
    switch (slug) {
      case 'v2':
        return (bg: const Color(0x1AFF7D00), fg: Brand.signal, border: const Color(0x59FF7D00));
      case 'invoice':
        return (bg: const Color(0x1A148C64), fg: const Color(0xFF0F7A58), border: const Color(0x4D148C64));
      case 'crm':
        return (bg: const Color(0x1A3C6EDC), fg: const Color(0xFF2F5EC4), border: const Color(0x4D3C6EDC));
      default:
        return (bg: const Color(0xFFF1F1EE), fg: const Color(0xFF78716C), border: const Color(0xFFE7E5E4));
    }
  }

  Widget _cardBody(Map<String, dynamic> t) {
    final cat = _normCat(t);
    final sub = _normSub(t);
    final ss = _normSubSub(t);
    final trail = [if (sub.isNotEmpty) _subName(cat, sub), if (ss.isNotEmpty) _subSubName(cat, sub, ss)];
    final colors = _catColors(cat);
    final icon = '${t['icon'] ?? ''}';
    final desc = '${t['subtitle'] ?? ''}'.isNotEmpty ? '${t['subtitle']}' : '${t['description'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: const Color(0xFFFFF4EA), borderRadius: BorderRadius.circular(11)),
                child: Icon(
                  helpFaIcon(icon.isEmpty ? kHelpDefaultIcon : icon),
                  size: 19,
                  color: helpHexColor('${t['icon_color'] ?? ''}'),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  (_tx.cat(cat)?.name ?? cat).toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: colors.fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${t['title'] ?? ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.25, color: Color(0xFF1C1917)),
          ),
          if (trail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EA),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0x47FF7D00)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_open, size: 11, color: Brand.signal),
                  const SizedBox(width: 5),
                  for (var i = 0; i < trail.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 11, color: Brand.signal),
                      ),
                    Text(trail[i], style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Brand.signal)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              desc,
              overflow: TextOverflow.fade,
              style: const TextStyle(fontSize: 13.3, height: 1.55, color: Color(0xFF78716C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> t, double width) {
    final id = _idOf(t);
    final body = SizedBox(width: width, height: 296, child: _HoverCard(onTap: () => _openTopic(id), child: _cardBody(t)));
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != id,
      onAcceptWithDetails: (d) => _moveCard(d.data, id),
      builder: (ctx, candidates, _) => Draggable<int>(
        data: id,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.85,
            child: SizedBox(
              width: width,
              height: 296,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Brand.signal, width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: _cardBody(t),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: body),
        child: candidates.isNotEmpty
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Color(0x33FF7D00), spreadRadius: 4)],
                ),
                child: body,
              )
            : body,
      ),
    );
  }

  Widget _grid(List<Map<String, dynamic>> items, double maxW) {
    const gap = 20.0;
    final cols = ((maxW + gap) / (280 + gap)).floor().clamp(1, 12);
    final w = (maxW - gap * (cols - 1)) / cols;
    return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in items) _card(t, w)]);
  }

  Widget _body() {
    if (_loading) return const Center(child: TpLoader(strokeWidth: 2.5));
    if (_error != null) return EmptyState(label: 'Could not load', hint: _error!);
    final topics = _filtered;
    if (topics.isEmpty) {
      _rows = const [];
      return const Center(
        child: Text('No help topics in this category yet.', style: TextStyle(color: Color(0xFF78716C))),
      );
    }
    final ungrouped = <Map<String, dynamic>>[];
    final groups = _groups(topics, ungrouped);
    _rows = groups.isEmpty
        ? [topics.map(_idOf).toList()]
        : [
            if (ungrouped.isNotEmpty) ungrouped.map(_idOf).toList(),
            for (final g in groups) g.items.map(_idOf).toList(),
          ];
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth - 32;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            if (groups.isEmpty)
              _grid(topics, w)
            else ...[
              if (ungrouped.isNotEmpty) _grid(ungrouped, w),
              for (final g in groups) ...[
                const SizedBox(height: 32),
                Row(
                  children: [
                    Text(g.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1C1917))),
                    const SizedBox(width: 11),
                    const Expanded(child: Divider(height: 1, color: Color(0xFFE7E5E4))),
                    const SizedBox(width: 11),
                    Text(
                      '${g.items.length} topic${g.items.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12.8, color: Color(0xFF78716C)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _grid(g.items, w),
              ],
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = _tx.cat(_cat);
    final sub = cat == null ? null : _tx.sub(_cat, _sub);
    return Scaffold(
      backgroundColor: context.brand.canvas,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 30, 8, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: context.brand.rule)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chip('All', _cat == 'all', () => setState(() {
                                    _cat = 'all';
                                    _sub = '';
                                    _subSub = '';
                                  })),
                              for (final c in _cats)
                                _chip(c.name, _cat == c.slug, () => setState(() {
                                      _cat = c.slug;
                                      _sub = '';
                                      _subSub = '';
                                    })),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _addCategory,
                          icon: const Icon(Icons.create_new_folder, size: 16),
                          label: const Text('Add Category', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Brand.signal,
                            side: const BorderSide(color: Brand.signal),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SignalButton(label: 'Add Topic', icon: Icons.add, onPressed: _addTopic),
                      ],
                    ),
                    if (cat != null && cat.subs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip('All ${cat.name}', _sub.isEmpty, () => setState(() {
                                _sub = '';
                                _subSub = '';
                              }), solid: true),
                          for (final s in cat.subs)
                            _chip(
                              s.name,
                              _sub == s.slug,
                              () => setState(() {
                                _sub = s.slug;
                                _subSub = '';
                              }),
                              solid: true,
                              onDelete: () => _confirmDeleteSub(cat.slug, s.slug, '', s.name.isEmpty ? s.slug : s.name),
                            ),
                        ],
                      ),
                    ],
                    if (sub != null && sub.subs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip('All ${sub.name}', _subSub.isEmpty, () => setState(() => _subSub = ''), solid: true),
                          for (final d in sub.subs)
                            _chip(
                              d.name,
                              _subSub == d.slug,
                              () => setState(() => _subSub = d.slug),
                              solid: true,
                              onDelete: () => _confirmDeleteSub(_cat, _sub, d.slug, d.name.isEmpty ? d.slug : d.name),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
          if (_opening)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(child: TpLoader(strokeWidth: 2.5)),
              ),
            ),
        ],
      ),
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hover ? Brand.signal : const Color(0xFFE7E5E4), width: 1.5),
            boxShadow: _hover
                ? const [
                    BoxShadow(color: Color(0x1FFF7D00), spreadRadius: 3),
                    BoxShadow(color: Color(0x12000000), blurRadius: 24, offset: Offset(0, 8)),
                  ]
                : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              if (_hover)
                const Positioned(
                  left: 24,
                  bottom: 18,
                  child: Row(
                    children: [
                      Text('Edit topic', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Brand.signal)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 12, color: Brand.signal),
                    ],
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 3,
                  color: _hover ? Brand.signal : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
