class OdooProduct {
  final int odooId;
  final String name;
  final String code;
  final String category;
  final String unit;
  final String source; // 'odoo_product' | 'purchase_order'

  OdooProduct({
    required this.odooId,
    required this.name,
    required this.code,
    required this.category,
    required this.unit,
    this.source = 'odoo_product',
  });

  String get firestoreId => 'odoo_$odooId';

  factory OdooProduct.fromJson(Map<String, dynamic> json) {
    return OdooProduct(
      odooId: json['id'] as int,
      name: json['name'] as String,
      code: json['default_code'] is String ? json['default_code'] : '',
      category: json['categ_id'] is List
          ? (json['categ_id'] as List).last.toString()
          : '',
      unit: json['uom_id'] is List
          ? (json['uom_id'] as List).last.toString()
          : '',
    );
  }

  factory OdooProduct.fromFirestore(String id, Map<String, dynamic> data) {
    return OdooProduct(
      odooId: data['odooId'] as int,
      name: data['name'] as String,
      code: data['code'] as String? ?? '',
      category: data['category'] as String? ?? '',
      unit: data['unit'] as String? ?? '',
      source: data['source'] as String? ?? 'odoo_product',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'odooId': odooId,
    'name': name,
    'code': code,
    'category': category,
    'unit': unit,
    'source': source,
    'updatedAt': DateTime.now().toIso8601String(),
  };
}