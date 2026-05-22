import 'sale_item.dart';
import 'sale_payment_method.dart';
import 'sale_pos_transaction.dart';

class Sale {
  static const String statusCompleted = 'completed';
  static const String statusPartiallyReturned = 'partially_returned';
  static const String statusReturned = 'returned';

  final int id;
  final int? originalSaleId;
  final String? returnKind;
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
  final String? fiscalStatus;
  final String? ticketUrl;
  final String? ticketPrintUrl;
  final bool offlineMode;
  final String? webkassaCheckNumber;
  final String? externalCheckNumber;
  final String? customerXin;
  final String? paymentMethod;
  final SalePosTransaction? posTransaction;
  final List<SalePosTransaction> posTransactions;
  final List<Sale> returnSales;
  final double returnedTotal;

  const Sale({
    required this.id,
    this.originalSaleId,
    this.returnKind,
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
    this.fiscalStatus,
    this.ticketUrl,
    this.ticketPrintUrl,
    this.offlineMode = false,
    this.webkassaCheckNumber,
    this.externalCheckNumber,
    this.customerXin,
    this.paymentMethod,
    this.posTransaction,
    this.posTransactions = const [],
    this.returnSales = const [],
    this.returnedTotal = 0,
  });

  bool get isReturnRecord => originalSaleId != null;

  bool get isReturned => status == statusReturned;

  bool get isPartiallyReturned => status == statusPartiallyReturned;

  bool get canAcceptReturns =>
      !isReturnRecord &&
      (status == statusCompleted || status == statusPartiallyReturned);

  bool get isOfdSale {
    final method = SalePaymentMethod.tryParse(paymentMethod);
    return method?.requiresFiscalization ?? false;
  }

  double get remainingDebt {
    if (!isOnCredit) return 0;
    return (totalPrice - paidAmount).clamp(0, double.infinity);
  }

  /// Сумма чека после возвратов (для частичного возврата).
  double get remainingTotalAfterReturns {
    if (!isPartiallyReturned) return totalPrice;
    return (totalPrice - totalReturnedAmount).clamp(0, double.infinity);
  }

  /// Общая сумма уже оформленных возвратов по продаже.
  double get totalReturnedAmount => returnedTotal > 0
      ? returnedTotal
      : returnSales.fold<double>(0, (s, r) => s + r.totalPrice);

  factory Sale.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>?;
    return Sale(
      id: _parseInt(json['id']),
      originalSaleId: json['original_sale_id'] != null
          ? _parseInt(json['original_sale_id'])
          : null,
      returnKind: json['return_kind']?.toString(),
      shiftId: json['shift_id'] != null ? _parseInt(json['shift_id']) : null,
      cashierId:
          json['cashier_id'] != null ? _parseInt(json['cashier_id']) : null,
      counterpartyId: json['counterparty_id'] != null
          ? _parseInt(json['counterparty_id'])
          : null,
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
      fiscalStatus: json['fiscal_status']?.toString(),
      ticketUrl: json['ticket_url']?.toString(),
      ticketPrintUrl: json['ticket_print_url']?.toString(),
      offlineMode: json['offline_mode'] == true,
      webkassaCheckNumber: json['webkassa_check_number']?.toString(),
      externalCheckNumber: json['external_check_number']?.toString(),
      customerXin: json['customer_xin']?.toString(),
      paymentMethod: json['payment_method']?.toString(),
      posTransactions: _parsePosTransactions(json),
      posTransaction: _parsePosTransaction(json),
      returnSales: json['return_sales'] is List
          ? (json['return_sales'] as List)
              .whereType<Map<String, dynamic>>()
              .map(Sale.fromJson)
              .toList()
          : const [],
      returnedTotal: _parseDouble(json['returned_total']),
    );
  }

  static List<SalePosTransaction> _parsePosTransactions(Map<String, dynamic> json) {
    final raw = json['pos_transactions'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(SalePosTransaction.fromJson)
          .toList();
    }
    final single = _parsePosTransaction(json);
    return single != null ? [single] : const [];
  }

  static SalePosTransaction? _parsePosTransaction(Map<String, dynamic> json) {
    if (json['pos_transaction'] is Map<String, dynamic>) {
      return SalePosTransaction.fromJson(
        json['pos_transaction'] as Map<String, dynamic>,
      );
    }
    return null;
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
