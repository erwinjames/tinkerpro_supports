import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/handoff_models.dart';
import '../services/handoff_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class ContinueAsScreen extends StatefulWidget {
  const ContinueAsScreen({
    super.key,
    required this.api,
    required this.offer,
    required this.signedInAs,
    required this.onContinue,
    required this.onUseAnother,
  });

  final ApiClient api;
  final HandoffOffer offer;
  final String? signedInAs;
  final Future<void> Function(bool remember) onContinue;
  final VoidCallback onUseAnother;

  @override
  State<ContinueAsScreen> createState() => _ContinueAsScreenState();
}

class _ContinueAsScreenState extends State<ContinueAsScreen> {
  bool _busy = false;
  bool _remember = true;

  HandoffAccount get _account => widget.offer.account;

  bool get _isSwitch =>
      widget.signedInAs != null && widget.signedInAs!.trim().isNotEmpty;

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      await widget.onContinue(_remember);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.brand;

    return StationScaffold(
      title: 'Continue',
      showBottomBrand: false,
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isSwitch) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: brand.surfaceHi,
                      borderRadius: BorderRadius.circular(Brand.radius),
                      border: Border.all(color: brand.rule),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: brand.paperDim),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You are signed in here as ${widget.signedInAs}.',
                            style: text.bodySmall?.copyWith(color: brand.paperDim),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                _HandoffAvatar(api: widget.api, account: _account),
                const SizedBox(height: 18),
                Text(
                  _account.displayName,
                  textAlign: TextAlign.center,
                  style: text.headlineSmall,
                ),
                if (_account.email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _account.email,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: brand.paperDim),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'This account is signed in to TinkerPro Support on this device.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: brand.paperDim),
                ),
                const SizedBox(height: 22),
                InkWell(
                  onTap: _busy ? null : () => setState(() => _remember = !_remember),
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _remember,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _remember = v ?? true),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Keep me signed in',
                            style: text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SignalButton(
                  label: _busy
                      ? 'Signing in…'
                      : 'Continue as ${_account.firstName}',
                  busy: _busy,
                  onPressed: _continue,
                ),
                const SizedBox(height: 12),
                GhostButton(
                  label: _isSwitch
                      ? 'Stay signed in as ${widget.signedInAs}'
                      : 'Use another account',
                  onPressed: _busy ? () {} : widget.onUseAnother,
                ),
                const SizedBox(height: 36),
                const BrandLockup(size: 72),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HandoffAvatar extends StatelessWidget {
  const _HandoffAvatar({required this.api, required this.account});

  final ApiClient api;
  final HandoffAccount account;

  String? get _url {
    final raw = account.profilePicture;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final clean = raw.replaceAll(RegExp(r'^/+'), '');
    return '${api.baseUrl}/$clean';
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final url = _url;
    final initials = account.displayName.trim().isEmpty
        ? '?'
        : account.displayName.trim()[0].toUpperCase();

    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: brand.surfaceHi,
          border: Border.all(color: brand.signal, width: 2),
          image: url == null
              ? null
              : DecorationImage(
                  image: NetworkImage(url, headers: api.authHeaders()),
                  fit: BoxFit.cover,
                ),
        ),
        alignment: Alignment.center,
        child: url != null
            ? null
            : Text(
                initials,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: brand.paperDim),
              ),
      ),
    );
  }
}
