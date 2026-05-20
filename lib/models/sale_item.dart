class SaleItem {
  final int productId;
  final String name;
  final double price;
  final double quantity;
  final String unit;
  final int? setId;
  final double returnedQuantity;

  const SaleItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.unit,
    this.setId,
    this.returnedQuantity = 0,
  });

  double get remainingQuantity =>
      (quantity - returnedQuantity).clamp(0, double.infinity);

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      productId: _parseInt(json['product_id']),
      setId: json['set_id'] != null ? _parseInt(json['set_id']) : null,
      name: json['name']?.toString() ?? '',
      price: _parseDouble(json['price']),
      quantity: _parseDouble(json['quantity']),
      unit: json['unit']?.toString() ?? 'pcs',
      returnedQuantity: _parseDouble(json['returned_quantity']),
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

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        if (setId != null) 'set_id': setId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'unit': unit,
      };

  double get total => price * quantity;
}
