class PurchaseOrder {
  final int id;
  final String name;
  final String supplierName;
  final DateTime? approvedAt;
  final String state;
  final List<PurchaseOrderLine> lines;

  PurchaseOrder({
    required this.id,
    required this.name,
    required this.supplierName,
    required this.approvedAt,
    required this.state,
    required this.lines,
  });

  factory PurchaseOrder.fromJson(
      Map<String, dynamic> json, List<PurchaseOrderLine> lines) {
    return PurchaseOrder(
      id: json['id'] as int,
      name: json['name'] as String,
      supplierName: json['partner_id'] is List
          ? (json['partner_id'] as List).last.toString()
          : '',
      approvedAt: json['date_approve'] != null && json['date_approve'] != false
          ? DateTime.tryParse(json['date_approve'])
          : null,
      state: json['state'] as String? ?? '',
      lines: lines,
    );
  }
}

class PurchaseOrderLine {
  final int id;
  final int productId;
  final String productName;
  final double orderedQty;
  final double receivedQty;

  PurchaseOrderLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.orderedQty,
    required this.receivedQty,
  });

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderLine(
      id: json['id'] as int,
      productId: json['product_id'] is List
          ? (json['product_id'] as List).first as int
          : 0,
      productName: json['product_id'] is List
          ? (json['product_id'] as List).last.toString()
          : '',
      orderedQty: (json['product_qty'] as num?)?.toDouble() ?? 0,
      receivedQty: (json['qty_received'] as num?)?.toDouble() ?? 0,
    );
  }
}