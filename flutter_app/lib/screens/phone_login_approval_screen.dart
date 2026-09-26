import 'dart:async';

import 'package:flutter/material.dart';

import '../services/biometric_auth.dart';
import '../theme.dart';

enum _Stage { loading, ready, working, approved, denied, failed }

class PhoneLoginApprovalScreen extends StatefulWidget {
  const PhoneLoginApprovalScreen({
    super.key,
    required this.biometrics,
    required this.requestId,
    this.preview,
  });

  final BiometricAuth biometrics;
  final String requestId;
  final Map<String, dynamic>? preview;

  @override
  State<PhoneLoginApprovalScreen> createState() =>
      _PhoneLoginApprovalScreenState();
}

class _PhoneLoginApprovalScreenState extends State<PhoneLoginApprovalScreen> {
  _Stage _stage = _Stage.loading;
  String _message = '';
  Map<String, dynamic> _details = const {};
  int? _choice;
  DateTime? _expiresAt;
  DateTime? _requestedAt;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final preview = widget.preview;
    if (preview != null) {
      _apply(preview);
    } else {
      _load();
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_stage == _Stage.ready && _secondsLeft <= 0) {
        setState(() {
          _stage = _Stage.failed;
          _message = 'This sign-in request expired.';
        });
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _secondsLeft {
    final at = _expiresAt;
    if (at == null) return 0;
    final left = at.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  void _apply(Map<String, dynamic> res) {
    if (res['success'] != true) {
      setState(() {
        _stage = _Stage.failed;
        _message =
            (res['message'] ?? 'This sign-in request is no longer available.')
                .toString();
      });
      return;
    }
    final now = DateTime.now();
    final expiresIn = int.tryParse('${res['expires_in']}') ?? 0;
    final age = int.tryParse('${res['age_seconds']}') ?? 0;
    setState(() {
      _details = res;
      _expiresAt = now.add(Duration(seconds: expiresIn));
      _requestedAt = now.subtract(Duration(seconds: age));
      _stage = expiresIn > 0 ? _Stage.ready : _Stage.failed;
      if (expiresIn <= 0) _message = 'This sign-in request expired.';
    });
  }

  Future<void> _load() async {
    try {
      final res = await widget.biometrics.phoneLoginDetails(widget.requestId);
      if (!mounted) return;
      _apply(res);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _message =
            'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  List<int> get _choices {
    final raw = _details['choices'];
    if (raw is! List) return const [];
    return [for (final v in raw) int.tryParse('$v') ?? 0];
  }

  Future<void> _approve() async {
    final choice = _choice;
    if (choice == null || _stage != _Stage.ready) return;
    setState(() => _stage = _Stage.working);
    try {
      final ok = await widget.biometrics.confirm(
        'Confirm your fingerprint to approve this sign-in',
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _stage = _Stage.ready);
        return;
      }
      final res = await widget.biometrics.phoneLoginRespond(
        widget.requestId,
        approve: true,
        choice: choice,
      );
      if (!mounted) return;
      setState(() {
        if (res['success'] == true && res['status'] == 'approved') {
          _stage = _Stage.approved;
          _message =
              'Sign-in approved. The computer will continue automatically.';
        } else if (res['status'] == 'denied') {
          _stage = _Stage.denied;
          _message = (res['message'] ?? 'The sign-in was blocked.').toString();
        } else {
          _stage = _Stage.failed;
          _message = (res['message'] ?? 'Could not approve this sign-in.')
              .toString();
        }
      });
    } on BiometricUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.ready;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _message =
            'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  Future<void> _deny() async {
    if (_stage != _Stage.ready) return;
    setState(() => _stage = _Stage.working);
    try {
      final res = await widget.biometrics.phoneLoginRespond(
        widget.requestId,
        approve: false,
      );
      if (!mounted) return;
      setState(() {
        _stage = res['success'] == true ? _Stage.denied : _Stage.failed;
        _message = res['success'] == true
            ? 'Sign-in denied. The computer was not signed in.'
            : (res['message'] ?? 'Could not deny this sign-in.').toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _message =
            'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Scaffold(
      backgroundColor: b.canvas,
      appBar: AppBar(
        title: const Text('Sign-in request'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.loading => const Center(child: CircularProgressIndicator()),
          _Stage.approved => _result(
            Icons.verified_rounded,
            b.success,
            'Approved',
          ),
          _Stage.denied => _result(Icons.block_rounded, b.danger, 'Denied'),
          _Stage.failed => _result(
            Icons.timer_off_outlined,
            b.paperDim,
            'Not available',
          ),
          _ => _form(),
        },
      ),
    );
  }

  Widget _result(IconData icon, Color color, String title) {
    final b = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: b.tint(color, 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: color),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: b.paper,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: TextStyle(color: b.paperDim, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    final b = context.brand;
    final busy = _stage == _Stage.working;
    final platform = (_details['platform'] ?? 'TinkerPro Support Desktop')
        .toString();
    final location = (_details['location'] ?? '').toString();
    final ip = (_details['ip'] ?? '').toString();
    final account = (_details['account'] ?? '').toString();
    final left = _secondsLeft;
    final countdown = '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
    final requested = _requestedAt;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: b.signalGlow(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.desktop_windows_outlined,
              size: 36,
              color: b.signal,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Are you trying to sign in?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: b.paper,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          account.isEmpty
              ? 'A computer is asking to sign in to your account.'
              : 'A computer is asking to sign in as $account.',
          textAlign: TextAlign.center,
          style: TextStyle(color: b.paperDim, fontSize: 14.5, height: 1.4),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: b.surface,
            borderRadius: BorderRadius.circular(Brand.radiusLg),
            border: Border.all(color: b.rule),
            boxShadow: b.shadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              _row(Icons.computer_outlined, 'Device', platform),
              _row(
                Icons.place_outlined,
                'Location',
                location.isEmpty ? 'Unknown' : location,
              ),
              _row(Icons.lan_outlined, 'IP address', ip),
              _row(
                Icons.schedule,
                'Requested',
                requested == null ? '—' : _clock(requested),
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Which number is shown on the computer?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: b.paper,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final n in _choices)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _numberChoice(n, busy),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Expires in $countdown',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: left <= 20 ? b.danger : b.paperDim,
            fontSize: 13,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: TextStyle(color: b.danger, fontSize: 13.5),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: busy || _choice == null ? null : _approve,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fingerprint),
            label: Text(
              _choice == null
                  ? 'Pick the number to approve'
                  : 'Approve with fingerprint',
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _deny,
            style: OutlinedButton.styleFrom(
              foregroundColor: b.danger,
              side: BorderSide(color: b.danger.withValues(alpha: 0.6)),
            ),
            icon: const Icon(Icons.block),
            label: const Text("Deny, this wasn't me"),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "If you didn't start this sign-in, tap Deny. Nobody can sign in "
          'without your fingerprint and the number on their screen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: b.paperDim, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value, {bool last = false}) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: b.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: b.paperDim),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: b.paperDim, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: b.paper,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberChoice(int n, bool busy) {
    final b = context.brand;
    final selected = _choice == n;
    return Material(
      color: selected ? b.signalGlow(0.16) : b.surface,
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        onTap: busy
            ? null
            : () => setState(() {
                _choice = n;
                _message = '';
              }),
        child: Container(
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radiusLg),
            border: Border.all(
              color: selected ? b.signal : b.rule,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            '$n',
            style: TextStyle(
              color: selected ? b.signalInk : b.paper,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
