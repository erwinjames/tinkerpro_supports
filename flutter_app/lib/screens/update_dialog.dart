import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.update, required this.service});

  final AppUpdate update;
  final UpdateService service;

  static Future<void> show(
    BuildContext context,
    AppUpdate update,
    UpdateService service,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(update: update, service: service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return _DialogReveal(
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                decoration: BoxDecoration(
                  color: b.isDark ? const Color(0xFF12304F) : Brand.navy,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Brand.orange.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Brand.orange.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: Brand.orange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            update.version.isNotEmpty
                                ? 'Version ${update.version}'
                                : 'New release',
                            style: text.labelMedium?.copyWith(
                              color: Brand.orange,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Semantics(
                            header: true,
                            child: Text(
                              'Update available',
                              style: text.titleLarge?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (update.changelog.isEmpty)
                        Text(
                          'A new version of the app is available.',
                          style: text.bodyMedium,
                        )
                      else ...[
                        Text("What's new", style: text.titleSmall),
                        const SizedBox(height: 10),
                        Flexible(
                          child: Container(
                            decoration: BoxDecoration(
                              color: b.surfaceHi,
                              border: Border.all(color: b.rule),
                              borderRadius: BorderRadius.circular(
                                Brand.radiusLg,
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final line in update.changelog)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(
                                              top: 3,
                                              right: 8,
                                            ),
                                            child: Icon(
                                              Icons.check_circle_rounded,
                                              size: 16,
                                              color: Brand.success,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              line,
                                              style: text.bodyMedium,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SignalButton(
                      label: 'Update now',
                      icon: Icons.download_rounded,
                      onPressed: () async {
                        final url = update.apkUrl;
                        if (url.isNotEmpty) {
                          await launchUrl(
                            Uri.parse(url),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: b.paperDim,
                      ),
                      onPressed: () {
                        service.snooze(update.build);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Later'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogReveal extends StatefulWidget {
  const _DialogReveal({required this.child});

  final Widget child;

  @override
  State<_DialogReveal> createState() => _DialogRevealState();
}

class _DialogRevealState extends State<_DialogReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
        child: widget.child,
      ),
    );
  }
}
