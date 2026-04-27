import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/odoo_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'screens/login_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/purchase_order_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Load Odoo credentials into the singleton from SharedPreferences.
  //    From this point on, every screen and service just calls
  //    OdooService.instance.fetchProducts() — no credentials needed.
  await OdooService.loadFromPrefs();

  // 3. Start background polling engine (WorkManager)
  await BackgroundService.initialize();

  runApp(const ExpiryApp());
}

class ExpiryApp extends StatefulWidget {
  const ExpiryApp({super.key});

  @override
  State<ExpiryApp> createState() => _ExpiryAppState();
}

class _ExpiryAppState extends State<ExpiryApp> {
  bool? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isLoggedIn = prefs.getBool('is_logged_in') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    // Splash while checking prefs
    if (_isLoggedIn == null) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'Expiry Tracker',
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      // If already logged in → go directly to main shell, skip login
      initialRoute: _isLoggedIn! ? '/home' : '/login',
      routes: {
        '/login':     (_) => const LoginScreen(),
        '/home':      (_) => const _MainShell(),
        '/dashboard': (_) => const DashboardScreen(),
      },
      builder: (context, child) {
        // Init notifications (needs a BuildContext for permission dialogs)
        NotificationService.instance.initialize(context);
        return child!;
      },
    );
  }
}

// ─── Bottom navigation shell ──────────────────────────────────────────────────

class _MainShell extends StatefulWidget {
  const _MainShell();

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;

  static const _screens = [
    ProductListScreen(),
    DashboardScreen(),
    PurchaseOrderScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Produits',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Commandes',
          ),
        ],
      ),
    );
  }
}