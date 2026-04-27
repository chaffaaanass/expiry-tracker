import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/batch_model.dart';
import '../services/firestore_service.dart';

class AddBatchScreen extends StatefulWidget {
  final List<OdooProduct> products;
  final OdooProduct? preselectedProduct;
  final String? purchaseOrderId;

  const AddBatchScreen({
    super.key,
    required this.products,
    this.preselectedProduct,
    this.purchaseOrderId,
  });

  @override
  State<AddBatchScreen> createState() => _AddBatchScreenState();
}

class _AddBatchScreenState extends State<AddBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirestoreService();
  final _dateFormat = DateFormat('dd/MM/yyyy');

  OdooProduct? _selectedProduct;
  DateTime? _expiryDate;
  DateTime _deliveryDate = DateTime.now();
  final _qtyCtrl = TextEditingController(text: '1');
  final _batchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.preselectedProduct ?? widget.products.firstOrNull;
    _batchCtrl.text = 'LOT-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  }

  Future<void> _pickDate({required bool isExpiry}) async {
    final initial = isExpiry
        ? (_expiryDate ?? DateTime.now().add(const Duration(days: 7)))
        : _deliveryDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isExpiry ? DateTime.now() : DateTime(2020),
      lastDate: DateTime(2030),
      helpText: isExpiry ? 'Date d\'expiration' : 'Date de livraison',
    );

    if (picked != null) {
      setState(() {
        if (isExpiry) {
          _expiryDate = picked;
        } else {
          _deliveryDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez une date d\'expiration')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final batch = BatchModel(
        id: '',
        batchNumber: _batchCtrl.text.trim(),
        expiryDate: _expiryDate!,
        deliveryDate: _deliveryDate,
        quantity: double.tryParse(_qtyCtrl.text) ?? 1,
        unit: _selectedProduct?.unit ?? '',
        purchaseOrderId: widget.purchaseOrderId,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      await _firestore.addBatch(_selectedProduct!.firestoreId, batch);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lot ajouté pour ${_selectedProduct!.name}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter un lot'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enregistrer'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.purchaseOrderId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bon de commande: ${widget.purchaseOrderId}',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),

            // Product selector
            _SectionLabel('Produit'),
            DropdownButtonFormField<OdooProduct>(
              value: _selectedProduct,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.inventory_2_outlined),
              ),
              items: widget.products
                  .map((p) => DropdownMenuItem(
                value: p,
                child: Text(p.name,
                    overflow: TextOverflow.ellipsis),
              ))
                  .toList(),
              onChanged: (p) => setState(() => _selectedProduct = p),
              validator: (v) => v == null ? 'Sélectionnez un produit' : null,
            ),

            const SizedBox(height: 20),

            // Batch number
            _SectionLabel('Numéro de lot'),
            TextFormField(
              controller: _batchCtrl,
              decoration: InputDecoration(
                hintText: 'LOT-001',
                prefixIcon: const Icon(Icons.tag),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) =>
              (v == null || v.isEmpty) ? 'Requis' : null,
            ),

            const SizedBox(height: 20),

            // Dates row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel('Date de livraison'),
                      _DateButton(
                        label: _dateFormat.format(_deliveryDate),
                        icon: Icons.local_shipping_outlined,
                        color: theme.colorScheme.secondaryContainer,
                        onTap: () => _pickDate(isExpiry: false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel('Date d\'expiration'),
                      _DateButton(
                        label: _expiryDate != null
                            ? _dateFormat.format(_expiryDate!)
                            : 'Sélectionner',
                        icon: Icons.event_outlined,
                        color: _expiryDate == null
                            ? theme.colorScheme.errorContainer
                            : _expiryDate!
                            .difference(DateTime.now())
                            .inDays <=
                            3
                            ? Colors.red.shade100
                            : Colors.green.shade100,
                        onTap: () => _pickDate(isExpiry: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Quantity
            _SectionLabel('Quantité'),
            TextFormField(
              controller: _qtyCtrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                suffixText: _selectedProduct?.unit ?? '',
                prefixIcon: const Icon(Icons.numbers),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requis';
                if (double.tryParse(v) == null) return 'Nombre invalide';
                return null;
              },
            ),

            const SizedBox(height: 20),

            // Notes
            _SectionLabel('Notes (optionnel)'),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Ex: stocké en chambre froide 3',
                prefixIcon: const Icon(Icons.notes),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Enregistrer le lot'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13)),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}