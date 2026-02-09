import 'sale_item.dart';

class Sale {
  final int id;
  final int? shiftId;
  final int? cashierId;
  final List<SaleItem> items;
  final int totalQty;
  final double totalPrice;
  final DateTime createdAt;

  const Sale({
    required this.id,
    this.shiftId,
    this.cashierId,
    required this.items,
    required this.totalQty,
    required this.totalPrice,
    required this.createdAt,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>?;
    return Sale(
      id: _parseInt(json['id']),
      shiftId: json['shift_id'] != null ? _parseInt(json['shift_id']) : null,
      cashierId: json['cashier_id'] != null ? _parseInt(json['cashier_id']) : null,
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
}
