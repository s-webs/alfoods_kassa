class SaleItem {
  final int productId;
  final String name;
  final double price;
  final double quantity;
  final String unit;

  const SaleItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.unit,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      productId: _parseInt(json['product_id']),
      name: json['name']?.toString() ?? '',
      price: _parseDouble(json['price']),
      quantity: _parseDouble(json['quantity']),
      unit: json['unit']?.toString() ?? 'pcs',
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
        'name': name,
        'price': price,
        'quantity': quantity,
        'unit': unit,
      };

  double get total => price * quantity;
}
