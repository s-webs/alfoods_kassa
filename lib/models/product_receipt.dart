import 'supplier.dart';
import 'sale_item.dart';

class ProductReceipt {
  final int id;
  final int? supplierId;
  final Supplier? supplier;
  final String? supplierName;
  final List<SaleItem> items;
  final List<String> images;
  final int totalQty;
  final double totalPrice;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductReceipt({
    required this.id,
    this.supplierId,
    this.supplier,
    this.supplierName,
    required this.items,
    required this.images,
    required this.totalQty,
    required this.totalPrice,
    required this.createdAt,
    required this.updatedAt,
  });

  String get supplierDisplayName =>
      supplier?.name ?? supplierName ?? 'Не указан';

  factory ProductReceipt.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>?;
    final supplierData = json['supplier'];
    return ProductReceipt(
      id: _parseInt(json['id']),
      supplierId: json['supplier_id'] != null
          ? _parseInt(json['supplier_id'])
          : null,
      supplier: supplierData != null
          ? Supplier.fromJson(supplierData as Map<String, dynamic>)
          : null,
      supplierName: json['supplier_name'] as String?,
      items: itemsList != null
          ? itemsList
              .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
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
      'supplier_name': supplierName,
      'supplier_id': supplierId,
      'items': items.map((item) => item.toJson()).toList(),
      'images': images,
    };
  }
}
