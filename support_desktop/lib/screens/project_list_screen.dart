import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/live_sync.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'ops_widgets.dart';
import '../widgets/tp_loader.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({
    super.key,
    required this.service,
    required this.onOpenProject,
    this.readOnly = false,
  });

  final TaskService service;
  final void Function(Project project) onOpenProject;
  final bool readOnly;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen>
    with LiveRefresh<ProjectListScreen> {
  late Future<List<Project>> _future;
  bool _silentSwap = false;
  bool _silentBusy = false;

  @override
  void initState() {
    super.initState();
    _future = widget.service.listProjects();
  }

  @override
  List<String> get liveKeys => const ['task'];

  @override
  void onLiveChange() => _silentReload();

  Future<void> _reload() async {
    setState(() {
      _future = widget.service.listProjects();
      _silentSwap = false;
    });
    await _future;
  }

  Future<void> _silentReload() async {
    if (!mounted || _silentBusy) return;
    _silentBusy = true;
    try {
      final fresh = await widget.service.listProjects();
      if (!mounted) return;
      setState(() {
        _silentSwap = true;
        _future = Future.value(fresh);
      });
    } catch (_) {
    } finally {
      _silentBusy = false;
    }
  }

  bool _adding = false;
  bool _creating = false;
  final _name = TextEditingController();
  final _category = TextEditingController();
  String _color = 'slate';

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    super.dispose();
  }

  void _cancelAdd() {
    setState(() {
      _adding = false;
      _name.clear();
      _category.clear();
      _color = 'slate';
    });
  }

  Future<void> _create() async {
    if (_name.text.isEmpty) {
      opsToast(context, 'Please fill out the Project name field.', error: true);
      return;
    }
    if (_category.text.isEmpty) {
      opsToast(context, 'Please fill out the Category field.', error: true);
      return;
    }
    setState(() => _creating = true);
    final r = await widget.service.createProject(
      name: _name.text,
      category: _category.text,
      color: _color,
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (!r.ok) {
      opsToast(context, r.message, error: true);
      return;
    }
    _cancelAdd();
    _reload();
  }

  Future<void> _delete(Project p) async {
    final ok = await opsConfirm(
      context,
      title: 'Delete this project?',
      message:
          '"${p.name.isEmpty ? 'this project' : p.name}" will be removed. Its tasks are kept but become unfiled.',
      confirm: 'Delete project',
    );
    if (!ok || !mounted) return;
    final r = await widget.service.deleteProject(p.id);
    if (!mounted) return;
    opsToast(context, r.message, error: !r.ok);
    if (r.ok) _silentReload();
  }

  Widget _addBar(BuildContext context, List<Project> projects) {
    final cats = <String>{for (final p in projects) p.category}.toList();
    if (!_adding) {
      return Align(
        alignment: Alignment.centerRight,
        child: SignalButton(
          label: 'Add project',
          icon: Icons.add,
          onPressed: () => setState(() => _adding = true),
        ),
      );
    }
    return WebCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: OpsField(
              label: 'Project name',
              child: TextField(
                controller: _name,
                autofocus: true,
                maxLength: 255,
                decoration: const InputDecoration(
                    counterText: '', hintText: 'e.g. QuickServe POS'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: OpsField(
              label: 'Category',
              child: Autocomplete<String>(
                optionsBuilder: (v) => cats.where((c) =>
                    c.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (v) => _category.text = v,
                fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                  if (ctrl.text != _category.text) ctrl.text = _category.text;
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    maxLength: 128,
                    onChanged: (v) => _category.text = v,
                    decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'e.g. QuickTrade POS Development'),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: OpsField(
              label: 'Color',
              child: DropdownButtonFormField<String>(
                initialValue: _color,
                items: const [
                  DropdownMenuItem(value: 'slate', child: Text('Slate')),
                  DropdownMenuItem(value: 'emerald', child: Text('Emerald')),
                  DropdownMenuItem(value: 'amber', child: Text('Amber')),
                  DropdownMenuItem(value: 'rose', child: Text('Rose')),
                  DropdownMenuItem(value: 'blue', child: Text('Blue')),
                  DropdownMenuItem(value: 'violet', child: Text('Violet')),
                ],
                onChanged: (v) => setState(() => _color = v ?? 'slate'),
              ),
            ),
          ),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          GhostButton(label: 'Cancel', onPressed: _creating ? null : _cancelAdd),
          const SizedBox(width: 10),
          SignalButton(label: 'Create project', busy: _creating, onPressed: _create),
        ]),
      ]),
    );
  }

  Future<void> _toggleStar(Project p) async {
    final fresh = (await _future)
        .map(
          (q) => q.id == p.id
              ? Project(
                  id: q.id,
                  name: q.name,
                  category: q.category,
                  color: q.color,
                  starred: !q.starred,
                  archived: q.archived,
                  taskCount: q.taskCount,
                  ownerId: q.ownerId,
                  ownerName: q.ownerName,
                  updatedAt: q.updatedAt,
                )
              : q,
        )
        .toList();
    setState(() {
      _silentSwap = true;
      _future = Future.value(fresh);
    });
    await widget.service.toggleProjectStar(p.id, !p.starred);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Project>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !(_silentSwap && snap.hasData)) {
          return const Center(child: TpLoader());
        }
        if (snap.hasError) {
          return WebCard(
            child: SizedBox(
              height: 260,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const IconTile(
                      icon: Icons.error_outline,
                      size: 52,
                      color: Brand.danger,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Could not load projects',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    GhostButton(
                      label: 'Retry',
                      icon: Icons.refresh,
                      onPressed: _reload,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final projects = (snap.data ?? const <Project>[]).toList();
        if (projects.isEmpty) {
          return ListView(children: [
            if (!widget.readOnly) ...[
              _addBar(context, projects),
              const SizedBox(height: 14),
            ],
            WebCard(
              child: SizedBox(
                height: 260,
                child: EmptyState(
                  icon: Icons.folder_open_outlined,
                  label: 'No projects yet',
                  hint: widget.readOnly
                      ? 'Nothing has been created yet.'
                      : 'Hit Add project to spin up your first one.',
                ),
              ),
            ),
          ]);
        }

        final starred = projects.where((p) => p.starred).toList();
        final byCategory = <String, List<Project>>{};
        for (final p in projects) {
          byCategory.putIfAbsent(p.category, () => []).add(p);
        }
        return LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1400
                ? 4
                : c.maxWidth >= 1000
                ? 3
                : c.maxWidth >= 640
                ? 2
                : 1;
            const gap = 14.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            Widget grid(List<Project> items) => Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final p in items)
                  SizedBox(
                    width: w,
                    child: _ProjectCard(
                      project: p,
                      readOnly: widget.readOnly,
                      onTap: () => widget.onOpenProject(p),
                      onStar: () => _toggleStar(p),
                      onDelete: () => _delete(p),
                    ),
                  ),
              ],
            );
            return ListView(
              key: const PageStorageKey<String>('tk-project-list'),
              children: [
                if (!widget.readOnly) ...[
                  _addBar(context, projects),
                  const SizedBox(height: 14),
                ],
                if (starred.isNotEmpty) ...[
                  _CategoryHeader(
                    label: 'Starred',
                    count: starred.length,
                    icon: Icons.star,
                    iconColor: Brand.warning,
                  ),
                  grid(starred),
                  const SizedBox(height: 22),
                ],
                for (final entry in byCategory.entries) ...[
                  _CategoryHeader(
                    label: entry.key.isEmpty ? 'Uncategorized' : entry.key,
                    count: entry.value.length,
                  ),
                  grid(entry.value),
                  const SizedBox(height: 22),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.label,
    required this.count,
    this.icon,
    this.iconColor,
  });

  final String label;
  final int count;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: iconColor ?? context.brand.paperDim),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: text.labelLarge?.copyWith(color: context.brand.paper),
          ),
          const SizedBox(width: 8),
          StatusPill(label: '$count'),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: context.brand.rule)),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatefulWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onStar,
    required this.onDelete,
    this.readOnly = false,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onStar;
  final VoidCallback onDelete;
  final bool readOnly;

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final project = widget.project;
    final rail = _railColor(project.color);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 92,
          decoration: BoxDecoration(
            color: _hover ? context.brand.surfaceHi : context.brand.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover ? rail.withValues(alpha: 0.6) : context.brand.rule,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Container(width: 4, color: rail),
              const SizedBox(width: 14),
              IconTile(icon: Icons.folder_outlined, size: 36, color: rail),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.brand.paper,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 13,
                          color: context.brand.paperDim,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${project.taskCount} ${project.taskCount == 1 ? "task" : "tasks"}',
                          style: text.bodySmall,
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.person_outline,
                          size: 13,
                          color: context.brand.paperDim,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            project.ownerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly)
                IconButton(
                  onPressed: widget.onStar,
                  tooltip: project.starred ? 'Unstar project' : 'Star project',
                  icon: Icon(
                    project.starred ? Icons.star : Icons.star_border,
                    size: 20,
                    color: project.starred
                        ? Brand.warning
                        : context.brand.paperDim,
                  ),
                )
              else if (project.starred)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.star, size: 20, color: Brand.warning),
                ),
              if (!widget.readOnly)
                IconButton(
                  onPressed: widget.onDelete,
                  tooltip: 'Delete project',
                  icon: Icon(Icons.delete_outline,
                      size: 19, color: context.brand.paperDim),
                ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  static Color _railColor(ProjectColor c) {
    switch (c) {
      case ProjectColor.slate:
        return const Color(0xFF94A3B8);
      case ProjectColor.emerald:
        return const Color(0xFF16A34A);
      case ProjectColor.amber:
        return const Color(0xFFF59E0B);
      case ProjectColor.rose:
        return const Color(0xFFE11D48);
      case ProjectColor.blue:
        return const Color(0xFF2563EB);
      case ProjectColor.violet:
        return const Color(0xFF7C3AED);
    }
  }
}
