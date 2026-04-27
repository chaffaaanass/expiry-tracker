import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'odoo_service.dart';
import 'firestore_service.dart';
import 'notification_service.dart';

const _pollTask  = 'odoo_po_poll';
const _expiryTask = 'expiry_daily_check';

// ─── WorkManager entry point ──────────────────────────────────────────────────
// Must be top-level. Runs in a separate Dart isolate (no shared memory with UI).

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case _pollTask:
        await _pollPurchaseOrders();
        break;
      case _expiryTask:
        await _checkExpiringProducts();
        break;
    }
    return true;
  });
}

// ─── Task: Poll Odoo for new Purchase Orders ──────────────────────────────────

Future<void> _pollPurchaseOrders() async {
  try {
    // In an isolate, SharedPreferences is the only way to get the credentials.
    // OdooService.loadFromPrefs() loads them straight into the singleton.
    final loaded = await OdooService.loadFromPrefs();
    if (!loaded) return; // not logged in yet — skip

    final odoo      = OdooService.instance;
    final firestore = FirestoreService();
    final prefs     = await SharedPreferences.getInstance();

    final seenIds = await firestore.getTrackedPoIds();

    final lastPollStr = prefs.getString('last_poll_date');
    final lastPoll = lastPollStr != null
        ? DateTime.parse(lastPollStr)
        : DateTime.now().subtract(const Duration(days: 1));

    final newOrders = await odoo.fetchNewPurchaseOrders(
      sinceDate:  lastPoll,
      excludeIds: seenIds,
    );

    if (newOrders.isNotEmpty) {
      // Mark as seen right away to avoid double notification
      await firestore.markPoAsSeen(newOrders.map((o) => o.id).toList());

      // Save pending IDs so the PO screen can highlight them on open
      await prefs.setString(
        'pending_po_ids',
        newOrders.map((o) => o.id.toString()).join(','),
      );

      final productCount = newOrders.fold(0, (sum, o) => sum + o.lines.length);

      await NotificationService.instance.showLocalNotification(
        title: '📦 Nouvelle livraison reçue',
        body:
        '${newOrders.length} bon(s) de commande · '
            '$productCount produit(s) à renseigner',
        payload: 'new_po',
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    }

    await prefs.setString('last_poll_date', DateTime.now().toIso8601String());
  } catch (_) {
    // Silent fail — WorkManager will retry on next cycle
  }
}

// ─── Task: Check expiring products and notify ─────────────────────────────────

Future<void> _checkExpiringProducts() async {
  try {
    final firestore = FirestoreService();
    final expiring  = await firestore.fetchExpiringBatches(days: 7);

    for (final item in expiring) {
      final days = item.daysLeft;

      final urgency = switch (days) {
        0     => '🚨 AUJOURD\'HUI',
        1     => '🔴 demain',
        <= 3  => '🟠 dans $days jours',
        _     => '🟡 dans $days jours',
      };

      await NotificationService.instance.showLocalNotification(
        title: '${item.productName}',
        body:  'Lot ${item.batch.batchNumber} — $urgency · qté: ${item.batch.quantity} ${item.batch.unit}',
        payload: item.productId,
        id: item.batch.id.hashCode,
      );
    }
  } catch (_) {
    // Silent fail
  }
}

// ─── BackgroundService API ────────────────────────────────────────────────────

class BackgroundService {
  /// Call once in main() — registers the isolate dispatcher with WorkManager.
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  /// Start polling Odoo every 15 min for new POs.
  /// (15 min is the Android WorkManager minimum — iOS may delay more.)
  static Future<void> startPolling() async {
    await Workmanager().registerPeriodicTask(
      _pollTask,
      _pollTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  /// Schedule a daily expiry check at ~08:00 AM.
  static Future<void> scheduleExpiryCheck() async {
    await Workmanager().registerPeriodicTask(
      _expiryTask,
      _expiryTask,
      frequency: const Duration(hours: 24),
      initialDelay: _delayUntil8AM(),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  static Future<void> stopAll() async {
    await Workmanager().cancelAll();
  }

  static Duration _delayUntil8AM() {
    final now    = DateTime.now();
    var   target = DateTime(now.year, now.month, now.day, 8);
    if (target.isBefore(now)) target = target.add(const Duration(days: 1));
    return target.difference(now);
  }
}