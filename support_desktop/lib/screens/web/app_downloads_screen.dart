import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/app_downloads_service.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import 'portal_ui.dart';
import '../../widgets/premium.dart';
import '../../widgets/tp_loader.dart';

const _android = Color(0xFF3DDC84);
const _chat = Color(0xFF1D5FD1);

class AppDownloadsScreen extends StatefulWidget {
  const AppDownloadsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<AppDownloadsScreen> createState() => _AppDownloadsScreenState();
}

class _AppDownloadsScreenState extends State<AppDownloadsScreen>
    with LiveRefresh<AppDownloadsScreen> {
  late final AppDownloadsService _svc = AppDownloadsService(widget.api);
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  AdData? _data;
  String _tab = 'users';
  String _app = '';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['appdownloads'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await _svc.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool _match(String search, List<String> apps) =>
      (_q.isEmpty || search.contains(_q)) &&
      (_app.isEmpty || apps.contains(_app));

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      onRefresh: _load,
      children: [
        const PortalHeader(
          eyebrow: 'Super Admin',
          title: 'App Downloads',
          sub: 'Who downloaded the Android apps, and how many times.',
          subMaxWidth: 900,
        ),
        ..._body(),
      ],
    );
  }

  List<Widget> _body() {
    if (_loading && _data == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: TpLoader()),
        ),
      ];
    }
    final d = _data;
    return [
      if (_error != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
              PortalButton(
                label: 'Retry',
                icon: Icons.refresh,
                onPressed: _load,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (d != null) ...[
        ResponsiveGrid(
          minItemWidth: 300,
          spacing: 16,
          children: [for (final s in d.summary) _summaryCard(s)],
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
            PortalTab(
              label: 'By user (${d.users.length})',
              selected: _tab == 'users',
              onColor: Brand.signal,
              fontSize: 13.6,
              onTap: () => setState(() => _tab = 'users'),
            ),
            const SizedBox(width: 6),
            PortalTab(
              label: 'Download log (${d.recent.length})',
              selected: _tab == 'log',
              onColor: Brand.signal,
              fontSize: 13.6,
              onTap: () => setState(() => _tab = 'log'),
            ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
            Container(
              height: 38,
              width: 200,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.brand.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.brand.rule),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _app,
                  isExpanded: true,
                  isDense: true,
                  style: portalCell(context).copyWith(fontSize: 14),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All apps')),
                    for (final a in d.apps)
                      DropdownMenuItem(value: a.file, child: Text(a.label)),
                  ],
                  onChanged: (v) => setState(() => _app = v ?? ''),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 260,
              child: PortalSearch(
                controller: _searchCtrl,
                hint: 'Search name, role, IP…',
                icon: false,
                height: 38,
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        PortalCard(
          radius: 12,
          child: _tab == 'users' ? _usersTable(d) : _logTable(d),
        ),
      ],
    ];
  }

  Widget _summaryCard(AdSummary s) {
    Widget stat(int v, String label) => Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$v',
            style: TextStyle(
              fontSize: 25.6,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: context.brand.paper,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w600,
              color: context.brand.paperDim,
            ),
          ),
        ],
      ),
    );
    return PortalCard(
      radius: 12,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.android, color: _android, size: 19),
              const SizedBox(width: 8),
              Text(
                s.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.brand.paper,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              stat(s.total, 'Downloads'),
              stat(s.users, 'Unique users'),
              stat(s.last7, 'Last 7 days'),
            ],
          ),
          const SizedBox(height: 12),
          Text('Last download: ${s.lastAt}', style: portalMeta(context)),
        ],
      ),
    );
  }

  Widget _table({
    required String id,
    required List<PortalCol> columns,
    required List<List<Widget>> rows,
  }) {
    return PortalTable(
      tableId: 'portal:downloads:$id',
      columns: columns,
      rows: rows,
      empty: 'No downloads recorded yet.',
      headerBg: context.brand.surface,
      headerLetterSpacing: 0.7,
      cellPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
  }

  Widget _usersTable(AdData d) {
    final cell = portalCell(context).copyWith(
      fontSize: 14,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final rows = d.users.where((u) => _match(u.search, u.apps)).map((u) {
      return <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              u.name,
              overflow: TextOverflow.ellipsis,
              style: cell.copyWith(fontWeight: FontWeight.w600),
            ),
            if (u.email.isNotEmpty)
              Text(
                u.email,
                overflow: TextOverflow.ellipsis,
                style: portalMeta(context),
              ),
          ],
        ),
        Text(u.role, style: cell),
        Text('${u.supportCount}', style: cell),
        Text('${u.chatCount}', style: cell),
        Text('${u.total}', style: cell.copyWith(fontWeight: FontWeight.w700)),
        Text(u.firstAt, style: cell),
        Text(u.lastAt, style: cell),
      ];
    }).toList();
    return _table(
      id: 'users',
      columns: const [
        PortalCol('User', flex: 26),
        PortalCol('Role', flex: 9),
        PortalCol('Support APK', flex: 14, right: true),
        PortalCol('Chat APK', flex: 11, right: true),
        PortalCol('Total', flex: 8, right: true),
        PortalCol('First download', flex: 16),
        PortalCol('Last download', flex: 16),
      ],
      rows: rows,
    );
  }

  Widget _logTable(AdData d) {
    final cell = portalCell(context).copyWith(fontSize: 14);
    final rows = d.recent.where((r) => _match(r.search, r.apps)).map((r) {
      final bg = r.isChat ? const Color(0xFFE8F1FF) : const Color(0xFFFFF3E6);
      final fg = r.isChat ? _chat : const Color(0xFFC25E00);
      return <Widget>[
        Text(r.date, style: cell, maxLines: 1),
        Text(
          r.name,
          overflow: TextOverflow.ellipsis,
          style: cell.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(r.role, style: cell),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            r.app,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(r.source, style: cell),
        Tooltip(
          message: r.userAgent,
          child: Text(r.device, style: cell),
        ),
        Text(r.ip, style: portalMeta(context)),
      ];
    }).toList();
    return _table(
      id: 'log',
      columns: const [
        PortalCol('Date', flex: 3),
        PortalCol('User', flex: 3),
        PortalCol('Role', flex: 2),
        PortalCol('App', flex: 1),
        PortalCol('Downloaded from', flex: 2),
        PortalCol('Device', flex: 2),
        PortalCol('IP address', flex: 2),
      ],
      rows: rows,
    );
  }
}
