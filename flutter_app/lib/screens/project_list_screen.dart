/// Projects view — mirror of the admin web's Projects board, condensed
/// into a vertical list of cards grouped by category. Phase 4 of the
/// task port.
///
/// Tapping a project navigates back to the Tasks view filtered by that
/// project's id via the [onOpenProject] callback (TaskListScreen plumbs
/// it into its own listTasks call).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({
    super.key,
    required this.service,
    required this.onOpenProject,
  });

  final TaskService service;
  final void Function(Project project) onOpenProject;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  late Future<List<Project>> _future;
  String? _lastSig;
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _future = widget.service.listProjects();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentReload());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _signature(List<Project> ps) {
    final b = StringBuffer();
    for (final p in ps) {
      b
        ..write(p.id)
        ..write('|')
        ..write(p.starred ? '1' : '0')
        ..write('|')
        ..write(p.taskCount)
        ..write('|')
        ..write(p.name)
        ..write(';');
    }
    return b.toString();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.service.listProjects();
      _lastSig = null;
    });
    await _future;
  }

  Future<void> _silentReload() async {
    if (!mounted) return;
    try {
      final fresh = await widget.service.listProjects();
      if (!mounted) return;
      final sig = _signature(fresh);
      if (sig == _lastSig) return;
      _lastSig = sig;
      setState(() => _future = Future.value(fresh));
    } catch (_) {/* swallow; refresh button still works */}
  }

  Future<void> _toggleStar(Project p) async {
    // Optimistic: flip the star locally so the tap feels immediate.
    final fresh = (await _future).map((q) => q.id == p.id
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
        : q).toList();
    setState(() => _future = Future.value(fresh));
    try {
      await widget.service.toggleProjectStar(p.id, !p.starred);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Star failed: $e')),
      );
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: context.brand.signal,
      backgroundColor: context.brand.surface,
      onRefresh: _reload,
      child: FutureBuilder<List<Project>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.brand.signal),
              ),
            );
          }
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              children: [
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.error_outline,
                          size: 36, color: context.brand.paperDim),
                      const SizedBox(height: 12),
                      Text(
                        'Could not load projects',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: context.brand.paper),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        snap.error.toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: context.brand.paperDim),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          final projects = (snap.data ?? const <Project>[]).toList();
          if (projects.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              children: [
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.folder_open_outlined,
                          size: 36, color: context.brand.paperDim),
                      const SizedBox(height: 12),
                      Text(
                        'No projects yet',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: context.brand.paper),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          // Star section pinned to the top (matches the web's "Starred"
          // pin) followed by category groupings in first-seen order.
          final starred = projects.where((p) => p.starred).toList();
          final byCategory = <String, List<Project>>{};
          for (final p in projects) {
            byCategory.putIfAbsent(p.category, () => []).add(p);
          }
          return ListView(
            key: const PageStorageKey<String>('tk-project-list'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (starred.isNotEmpty) ...[
                _CategoryHeader(
                  label: 'STARRED',
                  count: starred.length,
                  icon: Icons.star,
                  iconColor: const Color(0xFFE0B14C),
                ),
                ...starred.map((p) => _ProjectCard(
                      project: p,
                      onTap: () => widget.onOpenProject(p),
                      onStar: () => _toggleStar(p),
                    )),
                const SizedBox(height: 24),
              ],
              for (final entry in byCategory.entries) ...[
                _CategoryHeader(label: entry.key.toUpperCase(), count: entry.value.length),
                ...entry.value.map((p) => _ProjectCard(
                      project: p,
                      onTap: () => widget.onOpenProject(p),
                      onStar: () => _toggleStar(p),
                    )),
                const SizedBox(height: 24),
              ],
            ],
          );
        },
      ),
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
            Icon(icon, size: 14, color: iconColor ?? context.brand.paperDim),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: text.labelLarge?.copyWith(
              letterSpacing: 2.0,
              color: context.brand.paperDim,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: context.brand.rule),
            ),
            child: Text(
              count.toString(),
              style: text.labelSmall?.copyWith(color: context.brand.paperDim),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onStar,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final railColor = _railColor(project.color);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.rule),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              // Left color rail — same accent system as the web cards.
              Container(
                width: 4,
                height: 64,
                decoration: BoxDecoration(
                  color: railColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          color: context.brand.paper,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 12, color: context.brand.paperDim),
                          const SizedBox(width: 4),
                          Text(
                            '${project.taskCount} ${project.taskCount == 1 ? "task" : "tasks"}',
                            style: text.labelSmall
                                ?.copyWith(color: context.brand.paperDim),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.person_outline,
                              size: 12, color: context.brand.paperDim),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              project.ownerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall
                                  ?.copyWith(color: context.brand.paperDim),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: onStar,
                tooltip:
                    project.starred ? 'Unstar project' : 'Star project',
                icon: Icon(
                  project.starred ? Icons.star : Icons.star_border,
                  size: 20,
                  color: project.starred
                      ? const Color(0xFFE0B14C)
                      : context.brand.paperDim,
                ),
              ),
              const SizedBox(width: 4),
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
        return const Color(0xFF35A776);
      case ProjectColor.amber:
        return const Color(0xFFE0B14C);
      case ProjectColor.rose:
        return const Color(0xFFE05A82);
      case ProjectColor.blue:
        return const Color(0xFF7AA3E0);
      case ProjectColor.violet:
        return const Color(0xFFA88AE0);
    }
  }
}
