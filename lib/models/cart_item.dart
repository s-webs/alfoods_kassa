/// Позиция в корзине — снимок данных на момент добавления (название, цена).
/// Редактирование name/price в корзине не затрагивает модель Product.
class CartItem {
  final int productId;
  String name;
  double price;
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
