import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/session_store.dart';
import '../theme.dart';

/// One-time setup. Shown when [SessionStore.isConfigured] is false (first
/// launch on this device, or after a manual reset). The store name they
/// type here is the identity the support team sees in their inbox forever
/// — there's no way to rename through the UI yet, so the empty-state
/// copy nudges them to be deliberate about what they enter.
class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({
    super.key,
    required this.chat,
    required this.store,
    required this.onReady,
  });

  final ChatService chat;
  final SessionStore store;

  /// Called once chat.employeeStart resolves with a non-null
  /// [EmployeeChatInfo]. The shell uses this to swap to the chat screen.
  final void Function(EmployeeChatInfo info) onReady;

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final _ctrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  bool _busy = false;
  String? _error;
  String? _nameError;

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _ctrl.text.trim();
    final fullName = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your store name to continue.');
      return;
    }
    if (fullName.isEmpty) {
      setState(() => _nameError = 'Enter your full name to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });
    final info = await widget.chat.employeeStart(name, fullName: fullName);
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Check your connection and try again.';
      });
      return;
    }
    await widget.store.saveStoreName(name);
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
    return Scaffold(
      backgroundColor: Brand.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
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
                    child: const Icon(Icons.storefront,
                        color: Brand.canvas, size: 32),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your store name and your full name. The support '
                  'team sees the store as your identity in their inbox, and '
                  'your name on any ticket you file.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _ctrl,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _nameFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Store name',
                    hintText: 'e.g. D.D.S. Grocery — Main Branch',
                    errorText: _error,
                    prefixIcon: const Icon(Icons.store),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _continue(),
                  decoration: InputDecoration(
                    labelText: 'Your full name',
                    hintText: 'e.g. Juan Dela Cruz',
                    errorText: _nameError,
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
                      : const Text('Open chat'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tip: if you reinstall this app later, type the exact '
                  'same store name and your old chat history will resume.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: Brand.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
