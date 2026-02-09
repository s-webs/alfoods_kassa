class CartItem {
  final int productId;
  final String name;
  final double price;
  double quantity;
  final String unit;

  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.unit,
  });

  double get total => price * quantity;

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'name': name,
        'price': price,
        'quantity': quantity,
        'unit': unit,
      };
}
