import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';
import '../services/firestore_service.dart';
import 'add_batch_screen.dart';

class BatchListScreen extends StatelessWidget {
  final OdooProduct product;

  const BatchListScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name),
            if (product.code.isNotEmpty)
              Text(product.code,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: StreamBuilder<List<BatchModel>>(
        stream: firestore.streamBatches(product.firestoreId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final batches = snapshot.data ?? [];

          if (batches.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text('Aucun lot enregistré'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: batches.length,
            itemBuilder: (context, i) => _BatchCard(
              batch: batches[i],
              product: product,
              firestore: firestore,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddBatchScreen(
              products: [product],
              preselectedProduct: product,
            ),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  final BatchModel batch;
  final OdooProduct product;
  final FirestoreService firestore;

  const _BatchCard({
    required this.batch,
    required this.product,
    required this.firestore,
  });

  Color _statusColor(ExpiryStatus s) {
    return switch (s) {
      ExpiryStatus.expired => Colors.grey,
      ExpiryStatus.critical => Colors.red,
      ExpiryStatus.warning => Colors.orange,
      ExpiryStatus.soon => Colors.amber,
      ExpiryStatus.ok => Colors.green,
    };
  }

  String _statusLabel(ExpiryStatus s, int days) {
    return switch (s) {
      ExpiryStatus.expired => 'Expiré',
      ExpiryStatus.critical => days == 0 ? 'Expire aujourd\'hui' : 'Expire demain',
      ExpiryStatus.warning => 'Dans $days jours',
      ExpiryStatus.soon => 'Dans $days jours',
      ExpiryStatus.ok => 'Dans $days jours',
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(batch.status);
    final label = _statusLabel(batch.status, batch.daysUntilExpiry);
    final fmt = DateFormat('dd/MM/yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.grey,
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Info(icon: Icons.tag, label: 'Lot', value: batch.batchNumber),
                const SizedBox(width: 20),
                _Info(
                  icon: Icons.event_outlined,
                  label: 'Expiration',
                  value: fmt.format(batch.expiryDate),
                  highlight: color,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Info(
                  icon: Icons.local_shipping_outlined,
                  label: 'Livraison',
                  value: fmt.format(batch.deliveryDate),
                ),
                const SizedBox(width: 20),
                _Info(
                  icon: Icons.inventory_outlined,
                  label: 'Quantité',
                  value: '${batch.quantity.toStringAsFixed(0)} ${batch.unit}',
                ),
              ],
            ),
            if (batch.notes != null) ...[
              const SizedBox(height: 8),
              Text(batch.notes!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce lot ?'),
        content:
        Text('Lot ${batch.batchNumber} sera supprimé définitivement.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await firestore.deleteBatch(product.firestoreId, batch.id);
            },
            style:
            FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? highlight;

  const _Info({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15,
            color: highlight ??
                Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: highlight)),
          ],
        ),
      ],
    );
  }
}