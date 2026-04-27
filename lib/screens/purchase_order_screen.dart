import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_order_model.dart';
import '../models/product_model.dart';
import '../services/odoo_service.dart';       // singleton
import '../services/firestore_service.dart';
import 'add_batch_screen.dart';

class PurchaseOrderScreen extends StatefulWidget {
  const PurchaseOrderScreen({super.key});

  @override
  State<PurchaseOrderScreen> createState() => _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends State<PurchaseOrderScreen> {
  final _firestore = FirestoreService();

  bool              _loading = true;
  List<PurchaseOrder> _orders = [];
  String?           _error;

  // Track which PO lines already have a batch added (to show a checkmark)
  final Set<String> _doneLinesIds = {};

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  // ─── Load new POs from Odoo ───────────────────────────────────────────────

  Future<void> _loadOrders() async {
    setState(() { _loading = true; _error = null; });
    try {
      // OdooService.instance is always configured — no null check needed
      final seenIds = await _firestore.getTrackedPoIds();
      final orders  = await OdooService.instance.fetchNewPurchaseOrders(
        excludeIds: seenIds,
      );

      if (mounted) setState(() { _orders = orders; _loading = false; });
    } on OdooException catch (e) {
      if (mounted) {
        setState(() { _error = 'Erreur Odoo: ${e.message}'; _loading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bons de commande'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _loadOrders,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Récupération des bons de commande Odoo...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadOrders,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: Colors.green),
            const SizedBox(height: 16),
            const Text('Aucun nouveau bon de commande',
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              'Tous les bons de commande ont été traités.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh),
              label: const Text('Vérifier à nouveau'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders.length,
        itemBuilder: (context, i) => _POCard(
          order:       _orders[i],
          firestore:   _firestore,
          doneLinesIds: _doneLinesIds,
          onLineAdded: (lineKey) {
            setState(() => _doneLinesIds.add(lineKey));
          },
          onAllDone: () {
            setState(() => _orders.removeAt(i));
          },
        ),
      ),
    );
  }
}

// ─── Purchase Order Card ──────────────────────────────────────────────────────

class _POCard extends StatelessWidget {
  final PurchaseOrder   order;
  final FirestoreService firestore;
  final Set<String>     doneLinesIds;
  final void Function(String lineKey) onLineAdded;
  final VoidCallback    onAllDone;

  const _POCard({
    required this.order,
    required this.firestore,
    required this.doneLinesIds,
    required this.onLineAdded,
    required this.onAllDone,
  });

  String _lineKey(PurchaseOrderLine line) => '${order.id}_${line.id}';

  bool get _allLinesDone =>
      order.lines.every((l) => doneLinesIds.contains(_lineKey(l)));

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ──
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(order.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                _StatusBadge(state: order.state),
              ],
            ),

            const SizedBox(height: 4),

            // Supplier + date
            Row(
              children: [
                Icon(Icons.storefront_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(order.supplierName,
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13)),
                ),
                if (order.approvedAt != null)
                  Text(
                    dateFmt.format(order.approvedAt!),
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12),
                  ),
              ],
            ),

            const Divider(height: 24),

            // ── Lines ──
            Text(
              '${order.lines.length} produit(s) — saisissez les dates d\'expiration',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 12),

            ...order.lines.map((line) {
              final key  = _lineKey(line);
              final done = doneLinesIds.contains(key);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: done
                      ? Colors.green.shade50
                      : theme.colorScheme.surfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: done
                        ? Colors.green.shade200
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    // Done checkmark or product icon
                    Icon(
                      done
                          ? Icons.check_circle
                          : Icons.inventory_2_outlined,
                      color: done ? Colors.green : theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),

                    // Product name + qty
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.productName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13)),
                          Text(
                            'Reçu: ${line.receivedQty.toStringAsFixed(0)}'
                                ' / Commandé: ${line.orderedQty.toStringAsFixed(0)}',
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),

                    // Add lot button
                    if (!done)
                      FilledButton.tonal(
                        onPressed: () =>
                            _openAddBatch(context, line, key),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('+ Lot',
                            style: TextStyle(fontSize: 12)),
                      )
                    else
                      Text('Ajouté',
                          style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            }),

            const SizedBox(height: 14),

            // ── Action buttons ──
            Row(
              children: [
                // Mark all done (skip expiry entry)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _markAsSeen(context),
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Ignorer'),
                  ),
                ),
                const SizedBox(width: 10),
                // Mark done only if all lines have batches
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _allLinesDone
                        ? () => _markAsSeen(context)
                        : null,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Terminer'),
                  ),
                ),
              ],
            ),

            if (!_allLinesDone)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${order.lines.where((l) => !doneLinesIds.contains(_lineKey(l))).length} produit(s) sans date d\'expiration',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddBatch(
      BuildContext context, PurchaseOrderLine line, String lineKey) async {
    // Create/upsert the product in Firestore so we can attach a batch to it
    final product = OdooProduct(
      odooId:   line.productId,
      name:     line.productName,
      code:     '',
      category: '',
      unit:     '',
      source:   'purchase_order',
    );
    await firestore.upsertProduct(product);

    if (!context.mounted) return;

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddBatchScreen(
          products:            [product],
          preselectedProduct:  product,
          purchaseOrderId:     order.name,
        ),
      ),
    );

    // AddBatchScreen returns true when a batch was saved successfully
    if (added == true) {
      onLineAdded(lineKey);
    }
  }

  Future<void> _markAsSeen(BuildContext context) async {
    await firestore.markPoAsSeen([order.id]);
    onAllDone();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${order.name} marqué comme traité'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String state;
  const _StatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      'purchase' => 'Confirmé',
      'done'     => 'Reçu',
      'draft'    => 'Brouillon',
      'sent'     => 'Envoyé',
      _          => state,
    };
    final color = switch (state) {
      'purchase' => Colors.blue,
      'done'     => Colors.green,
      'draft'    => Colors.grey,
      'sent'     => Colors.orange,
      _          => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}