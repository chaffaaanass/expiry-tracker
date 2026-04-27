import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/batch_model.dart';
import '../services/firestore_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _firestore = FirestoreService();
  int _daysFilter = 7;
  bool _loading = true;
  List<ExpiringBatch> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items =
      await _firestore.fetchExpiringBatches(days: _daysFilter);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final critical = _items.where((i) => i.daysLeft <= 1).length;
    final warning = _items.where((i) => i.daysLeft > 1 && i.daysLeft <= 3).length;
    final ok = _items.where((i) => i.daysLeft > 3).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // Summary cards
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [1, 3, 7, 14, 30].map((d) {
                          final selected = _daysFilter == d;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text('$d jours'),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _daysFilter = d);
                                _load();
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stats row
                    Row(
                      children: [
                        _StatCard(
                          label: 'Critique',
                          count: critical,
                          color: Colors.red,
                          icon: Icons.warning_outlined,
                        ),
                        const SizedBox(width: 10),
                        _StatCard(
                          label: 'Attention',
                          count: warning,
                          color: Colors.orange,
                          icon: Icons.access_time_outlined,
                        ),
                        const SizedBox(width: 10),
                        _StatCard(
                          label: 'À venir',
                          count: ok,
                          color: Colors.green,
                          icon: Icons.check_circle_outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Text(
                      '${_items.length} lot${_items.length != 1 ? 's' : ''} expirant dans $_daysFilter jours',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // List
            if (_items.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green),
                      SizedBox(height: 16),
                      Text('Aucun produit en alerte',
                          style: TextStyle(fontSize: 18)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) =>
                      _ExpiryCard(item: _items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(count.toString(),
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ExpiryCard extends StatelessWidget {
  final ExpiringBatch item;
  const _ExpiryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final days = item.daysLeft;
    final color = days <= 1
        ? Colors.red
        : days <= 3
        ? Colors.orange
        : days <= 7
        ? Colors.amber
        : Colors.green;

    final dayLabel = days == 0
        ? 'Aujourd\'hui'
        : days == 1
        ? 'Demain'
        : 'J-$days';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(dayLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: days == 0 || days == 1 ? 11 : 16)),
          ),
        ),
        title: Text(item.productName,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          'Lot ${item.batch.batchNumber} · '
              'Exp: ${DateFormat('dd/MM/yy').format(item.batch.expiryDate)} · '
              'Qté: ${item.batch.quantity.toStringAsFixed(0)} ${item.batch.unit}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            days == 0
                ? 'URGENT'
                : '$days j',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13),
          ),
        ),
      ),
    );
  }
}