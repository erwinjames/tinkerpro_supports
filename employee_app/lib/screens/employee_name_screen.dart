import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/session_store.dart';
import '../theme.dart';

/// Blocking name capture for a device that already has a store identity but
/// no operator name: installs that predate the full-name field, and phones
/// synced before QR sync started collecting it. The store name is the
/// account/resume key and is left untouched — we only ask who is at the
/// terminal, because that's what gets stamped on tickets and shown in the
/// agent inbox ("Store — Employee").
///
/// Deliberately has no skip: the same requirement as [StoreSetupScreen], just
/// reached from the other direction.
class EmployeeNameScreen extends StatefulWidget {
  const EmployeeNameScreen({
    super.key,
    required this.chat,
    required this.store,
    required this.onReady,
  });

  final ChatService chat;
  final SessionStore store;

  /// Called once the name is persisted and `chat.employeeStart` has re-run
  /// with it, so the server-side conversation label picks it up immediately.
  final void Function(EmployeeChatInfo info) onReady;

  @override
  State<EmployeeNameScreen> createState() => _EmployeeNameScreenState();
}

class _EmployeeNameScreenState extends State<EmployeeNameScreen> {
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final fullName = _nameCtrl.text.trim();
    if (fullName.isEmpty) {
      setState(() => _error = 'Enter your full name to continue.');
      return;
    }
    final storeName = (widget.store.storeName ?? '').trim();
    if (storeName.isEmpty) return; // shell wouldn't have shown us
    setState(() {
      _busy = true;
      _error = null;
    });
    final info = await widget.chat.employeeStart(storeName, fullName: fullName);
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection and '
            'try again.';
      });
      return;
    }
    await widget.store.saveEmployeeFullName(fullName);
    await widget.store.saveIdentity(
      userId: info.meId,
      convId: info.conversationId,
    );
    if (!mounted) return;
    widget.onReady(info);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final storeName = (widget.store.storeName ?? '').trim();
    return Scaffold(
      backgroundColor: Brand.surface,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Brand.signal,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_outline,
                          color: Brand.canvas, size: 32),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Who is using this terminal?',
                    textAlign: TextAlign.center,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    storeName.isEmpty
                        ? 'Enter your full name. Support sees it on every '
                            'ticket you file.'
                        : 'Signed in as $storeName. Enter your full name — '
                            'support sees it on every ticket you file.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_busy,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _continue(),
                    decoration: InputDecoration(
                      labelText: 'Your full name',
                      hintText: 'e.g. Juan Dela Cruz',
                      errorText: _error,
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _continue,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Brand.canvas,
                            ),
                          )
                        : const Text('Continue'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You can change this later from the home screen when a '
                    'different employee takes over.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: Brand.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
