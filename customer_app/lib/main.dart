import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'models/customer_models.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/session_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Status bar adapts to the surface — light icons on the hero, dark on
  // the dashboard. We do a coarse default here; individual screens
  // override via AnnotatedRegion if they need to.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  final api = await ApiClient.create();
  final store = await SessionStore.create();
  final auth = AuthService(api, store);
  runApp(CustomerApp(auth: auth));
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key, required this.auth});
  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TinkerPro',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _Bootstrap(auth: auth),
    );
  }
}

/// Tiny splash that asks the server whether our PHPSESSID cookie still
/// resolves to an active customer. If yes, push the dashboard. If no,
/// push the TIN login screen. Either way replaces this splash so we
/// never come back here.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.auth});
  final AuthService auth;
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    // Honor the "Keep me signed in" toggle from the last login. If the
    // customer left it unchecked, blow away the cookie jar so the
    // server-side session can't auto-resolve us back into the dashboard.
    if (!widget.auth.store.rememberMe) {
      await widget.auth.api.wipeCookies();
      await widget.auth.store.setActiveCustomerId(null);
    }
    Customer? restored;
    try {
      restored = await widget.auth.restoreSession();
    } catch (_) {/* fall through to login */}
    if (!mounted) return;
    if (restored != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => DashboardScreen(
          auth: widget.auth,
          initialCustomer: restored!,
        ),
      ));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LoginScreen(auth: widget.auth),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.ink,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: Brand.primary,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Brand.signalGlow(0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.support_agent,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Brand.signal),
            ),
          ],
        ),
      ),
    );
  }
}
