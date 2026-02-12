import 'sale_item.dart';

class Sale {
  static const String statusCompleted = 'completed';
  static const String statusReturned = 'returned';

  final int id;
  final int? shiftId;
  final int? cashierId;
  final int? counterpartyId;
  final bool isOnCredit;
  final double paidAmount;
  final List<SaleItem> items;
  final int totalQty;
  final double totalPrice;
  final String status;
  final DateTime createdAt;

  const Sale({
    required this.id,
    this.shiftId,
    this.cashierId,
    this.counterpartyId,
    this.isOnCredit = false,
    this.paidAmount = 0,
    required this.items,
    required this.totalQty,
    required this.totalPrice,
    this.status = statusCompleted,
    required this.createdAt,
  });

  bool get isReturned => status == statusReturned;

  double get remainingDebt {
    if (!isOnCredit) return 0;
    return (totalPrice - paidAmount).clamp(0, double.infinity);
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>?;
    return Sale(
      id: _parseInt(json['id']),
      shiftId: json['shift_id'] != null ? _parseInt(json['shift_id']) : null,
      cashierId: json['cashier_id'] != null ? _parseInt(json['cashier_id']) : null,
      counterpartyId: json['counterparty_id'] != null ? _parseInt(json['counterparty_id']) : null,
      isOnCredit: json['is_on_credit'] == true,
      paidAmount: _parseDouble(json['paid_amount']),
      items: itemsList != null
          ? itemsList
              .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      totalQty: _parseInt(json['total_qty']),
      totalPrice: _parseDouble(json['total_price']),
      status: json['status']?.toString() ?? statusCompleted,
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
