import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/odoo_service.dart';       // singleton
import '../services/firestore_service.dart';
import 'add_batch_screen.dart';
import 'batch_list_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final _firestore  = FirestoreService();
  final _searchCtrl = TextEditingController();
  String _search  = '';
  bool   _syncing = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Sync: fetch from Odoo → save to Firestore ───────────────────────────

  Future<void> _syncProducts() async {
    setState(() => _syncing = true);
    try {
      // OdooService.instance is already configured — just call it directly
      final products = await OdooService.instance.fetchProducts();
      await _firestore.upsertProducts(products);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${products.length} produits synchronisés'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } on OdooException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur Odoo: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ─── Open add-batch form ──────────────────────────────────────────────────

  Future<void> _openAddBatch() async {
    final products = await _firestore.streamProducts().first;
    if (!mounted) return;

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Synchronisez d\'abord les produits avec Odoo')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddBatchScreen(products: products)),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produits'),
        actions: [
          // Connection status indicator
          _ConnectionStatus(),
          // Sync button
          IconButton(
            icon: _syncing
                ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            tooltip: 'Synchroniser avec Odoo',
            onPressed: _syncing ? null : _syncProducts,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: 'Rechercher un produit...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_search.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                    },
                  ),
              ],
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<OdooProduct>>(
        stream: _firestore.streamProducts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final all      = snapshot.data ?? [];
          final filtered = _search.isEmpty
              ? all
              : all.where((p) =>
          p.name.toLowerCase().contains(_search) ||
              p.code.toLowerCase().contains(_search)).toList();

          if (all.isEmpty) {
            return _EmptyState(onSync: _syncProducts, syncing: _syncing);
          }

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                'Aucun produit trouvé pour "$_search"',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _syncProducts,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: filtered.length,
              itemBuilder: (context, i) => _ProductCard(
                product: filtered[i],
                firestore: _firestore,
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddBatch,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un lot'),
      ),
    );
  }
}

// ─── Connection status dot ────────────────────────────────────────────────────

class _ConnectionStatus extends StatefulWidget {
  @override
  State<_ConnectionStatus> createState() => _ConnectionStatusState();
}

class _ConnectionStatusState extends State<_ConnectionStatus> {
  bool? _connected;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await OdooService.instance.ping();
    if (mounted) setState(() => _connected = ok);
  }

  @override
  Widget build(BuildContext context) {
    final color = _connected == null
        ? Colors.grey
        : _connected!
        ? Colors.green
        : Colors.red;
    final tooltip = _connected == null
        ? 'Vérification...'
        : _connected!
        ? 'Odoo connecté'
        : 'Odoo non joignable';

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: GestureDetector(
          onTap: () { setState(() => _connected = null); _check(); },
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

// ─── Product card ─────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final OdooProduct product;
  final FirestoreService firestore;

  const _ProductCard({required this.product, required this.firestore});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: firestore.streamBatches(product.firestoreId),
      builder: (context, snapshot) {
        final batches       = snapshot.data ?? [];
        final activeBatches = batches.where((b) => !b.isExpired).toList();
        final hasUrgent     = activeBatches.any((b) => b.daysUntilExpiry <= 3);
        final theme         = Theme.of(context);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: hasUrgent
                ? BorderSide(color: Colors.red.shade300, width: 1.5)
                : BorderSide.none,
          ),
          child: ListTile(
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: hasUrgent
                  ? Colors.red.shade100
                  : theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.inventory_2_outlined,
                color: hasUrgent
                    ? Colors.red.shade700
                    : theme.colorScheme.secondary,
              ),
            ),
            title: Text(product.name,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(
              [
                if (product.code.isNotEmpty) '[${product.code}]',
                if (product.category.isNotEmpty) product.category,
              ].join(' · '),
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            trailing: _BatchBadge(
                activeBatches: activeBatches, hasUrgent: hasUrgent),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BatchListScreen(product: product)),
            ),
          ),
        );
      },
    );
  }
}

// ─── Batch badge (trailing) ───────────────────────────────────────────────────

class _BatchBadge extends StatelessWidget {
  final List activeBatches;
  final bool hasUrgent;

  const _BatchBadge({required this.activeBatches, required this.hasUrgent});

  @override
  Widget build(BuildContext context) {
    final count = activeBatches.length;
    final color = count == 0
        ? Colors.grey
        : hasUrgent
        ? Colors.red
        : Colors.green;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count lot${count != 1 ? 's' : ''}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color.shade700),
          ),
        ),
        if (activeBatches.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'J-${(activeBatches.first).daysUntilExpiry}',
            style: TextStyle(
                fontSize: 11,
                color: hasUrgent
                    ? Colors.red.shade600
                    : Colors.grey.shade600),
          ),
        ],
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onSync;
  final bool syncing;

  const _EmptyState({required this.onSync, required this.syncing});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 20),
            const Text('Aucun produit',
                style:
                TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Synchronisez avec Odoo pour importer\nla liste des produits.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: syncing ? null : onSync,
              icon: syncing
                  ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: const Text('Synchroniser maintenant'),
            ),
          ],
        ),
      ),
    );
  }
}