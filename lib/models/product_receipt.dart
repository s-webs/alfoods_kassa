import 'counterparty.dart';
import 'sale_item.dart';

class ProductReceipt {
  final int id;
  final int? counterpartyId;
  final Counterparty? counterparty;
  final String? supplierName;
  final List<SaleItem> items;
  final int totalQty;
  final double totalPrice;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductReceipt({
    required this.id,
    this.counterpartyId,
    this.counterparty,
    this.supplierName,
    required this.items,
    required this.totalQty,
    required this.totalPrice,
    required this.createdAt,
    required this.updatedAt,
  });

  String get supplierDisplayName =>
      counterparty?.name ?? supplierName ?? 'Не указан';

  factory ProductReceipt.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>?;
    final counterpartyData = json['counterparty'];
    return ProductReceipt(
      id: _parseInt(json['id']),
      counterpartyId: json['counterparty_id'] != null
          ? _parseInt(json['counterparty_id'])
          : null,
      counterparty: counterpartyData != null
          ? Counterparty.fromJson(counterpartyData as Map<String, dynamic>)
          : null,
      supplierName: json['supplier_name'] as String?,
      items: itemsList != null
          ? itemsList
              .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      totalQty: _parseInt(json['total_qty']),
      totalPrice: _parseDouble(json['total_price']),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'].toString())
          : DateTime.now(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'counterparty_id': counterpartyId,
      'supplier_name': supplierName,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}
