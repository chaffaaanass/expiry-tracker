import 'package:cloud_firestore/cloud_firestore.dart';

class BatchModel {
  final String id;
  final String batchNumber;
  final DateTime expiryDate;
  final DateTime deliveryDate;
  final double quantity;
  final String unit;
  final String? purchaseOrderId;
  final String? notes;

  BatchModel({
    required this.id,
    required this.batchNumber,
    required this.expiryDate,
    required this.deliveryDate,
    required this.quantity,
    required this.unit,
    this.purchaseOrderId,
    this.notes,
  });

  int get daysUntilExpiry =>
      expiryDate.difference(DateTime.now()).inDays;

  bool get isExpired => expiryDate.isBefore(DateTime.now());

  ExpiryStatus get status {
    if (isExpired) return ExpiryStatus.expired;
    if (daysUntilExpiry <= 1) return ExpiryStatus.critical;
    if (daysUntilExpiry <= 3) return ExpiryStatus.warning;
    if (daysUntilExpiry <= 7) return ExpiryStatus.soon;
    return ExpiryStatus.ok;
  }

  factory BatchModel.fromFirestore(String id, Map<String, dynamic> data) {
    return BatchModel(
      id: id,
      batchNumber: data['batchNumber'] as String? ?? id.substring(0, 6),
      expiryDate: (data['expiryDate'] as Timestamp).toDate(),
      deliveryDate: data['deliveryDate'] != null
          ? (data['deliveryDate'] as Timestamp).toDate()
          : DateTime.now(),
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      unit: data['unit'] as String? ?? '',
      purchaseOrderId: data['purchaseOrderId'] as String?,
      notes: data['notes'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'batchNumber': batchNumber,
    'expiryDate': Timestamp.fromDate(expiryDate),
    'deliveryDate': Timestamp.fromDate(deliveryDate),
    'quantity': quantity,
    'unit': unit,
    'purchaseOrderId': purchaseOrderId,
    'notes': notes,
    'createdAt': FieldValue.serverTimestamp(),
  };

  BatchModel copyWith({
    String? batchNumber,
    DateTime? expiryDate,
    DateTime? deliveryDate,
    double? quantity,
    String? notes,
  }) {
    return BatchModel(
      id: id,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      quantity: quantity ?? this.quantity,
      unit: unit,
      purchaseOrderId: purchaseOrderId,
      notes: notes ?? this.notes,
    );
  }
}

enum ExpiryStatus { ok, soon, warning, critical, expired }