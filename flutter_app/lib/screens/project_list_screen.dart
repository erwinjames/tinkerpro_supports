library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/task_models.dart';
import '../services/task_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

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
    } catch (_) {}
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
    setState(() => _future = Future.value(fresh));
    try {
      await widget.service.toggleProjectStar(p.id, !p.starred);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Star failed: $e')));
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<Project>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SkeletonList(
              count: 6,
              padding: EdgeInsets.fromLTRB(20, 4, 20, 20),
            );
          }
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
              children: [
                EmptyState(
                  label: 'Could not load projects',
                  hint: snap.error.toString(),
                  icon: Icons.error_outline_rounded,
                  action: OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
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
              children: const [
                EmptyState(
                  label: 'No projects yet',
                  hint: 'Projects you own or belong to will appear here.',
                  icon: Icons.folder_open_rounded,
                ),
              ],
            );
          }

          final starred = projects.where((p) => p.starred).toList();
          final byCategory = <String, List<Project>>{};
          for (final p in projects) {
            byCategory.putIfAbsent(p.category, () => []).add(p);
          }
          var seq = 0;
          Widget card(Project p) => _Rise(
            index: seq++,
            child: _ProjectCard(
              project: p,
              onTap: () => widget.onOpenProject(p),
              onStar: () => _toggleStar(p),
            ),
          );
          Widget header(String label, int count, IconData icon, Color? tone) =>
              _Rise(
                index: seq++,
                child: _CategoryHeader(
                  label: label,
                  count: count,
                  icon: icon,
                  iconColor: tone,
                ),
              );
          return ListView(
            key: const PageStorageKey<String>('tk-project-list'),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (starred.isNotEmpty) ...[
                header(
                  'Starred',
                  starred.length,
                  Icons.star_rounded,
                  Brand.warning,
                ),
                ...starred.map(card),
                const SizedBox(height: 20),
              ],
              for (final entry in byCategory.entries) ...[
                header(
                  entry.key,
                  entry.value.length,
                  Icons.folder_rounded,
                  null,
                ),
                ...entry.value.map(card),
                const SizedBox(height: 20),
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
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? b.signal),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          GlowBadge(label: count.toString(), color: iconColor ?? b.signal),
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
    final b = context.brand;
    final accent = _railColor(project.color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        radius: Brand.radiusLg,
        borderColor: project.starred
            ? Brand.warning.withValues(alpha: 0.42)
            : null,
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        child: Row(
          children: [
            IconTile(icon: Icons.folder_rounded, color: accent, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(color: b.paper),
                        ),
                      ),
                      if (project.archived) ...[
                        const SizedBox(width: 8),
                        StatusPill(label: 'Archived', color: b.paperDim),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      GlowBadge(
                        label:
                            '${project.taskCount} ${project.taskCount == 1 ? "task" : "tasks"}',
                        color: accent,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      const SizedBox(width: 10),
                      AppAvatar(name: project.ownerName, size: 20),
                      const SizedBox(width: 6),
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
            _StarButton(starred: project.starred, onTap: onStar),
          ],
        ),
      ),
    );
  }

  static Color _railColor(ProjectColor c) {
    switch (c) {
      case ProjectColor.slate:
        return const Color(0xFF64748B);
      case ProjectColor.emerald:
        return const Color(0xFF10B981);
      case ProjectColor.amber:
        return const Color(0xFFF59E0B);
      case ProjectColor.rose:
        return const Color(0xFFF43F5E);
      case ProjectColor.blue:
        return const Color(0xFF3B82F6);
      case ProjectColor.violet:
        return const Color(0xFF8B5CF6);
    }
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({required this.starred, required this.onTap});

  final bool starred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return IconButton(
      onPressed: onTap,
      tooltip: starred ? 'Unstar project' : 'Star project',
      icon: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: starred ? 1 : 0, end: starred ? 1 : 0),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (_, v, _) => Transform.scale(
          scale: 1 + v * 0.18,
          child: Transform.rotate(
            angle: v * 0.6,
            child: Icon(
              starred ? Icons.star_rounded : Icons.star_border_rounded,
              size: 22,
              color: Color.lerp(b.paperDim, Brand.warning, v),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rise extends StatefulWidget {
  const _Rise({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.07),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
      return;
    }
    final steps = widget.index < 0 ? 0 : (widget.index > 7 ? 7 : widget.index);
    if (steps == 0) {
      _c.forward();
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 45 * steps), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}
