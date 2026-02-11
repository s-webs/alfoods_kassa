/// Позиция в корзине — снимок данных на момент добавления (название, цена).
/// Редактирование name/price в корзине не затрагивает модель Product.
/// Для сетов: productId = 0, setId != null.
class CartItem {
  final int productId;
  final int? setId;
  String name;
  double price;
  double quantity;
  final String unit;

  CartItem({
    required this.productId,
    this.setId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.unit,
  });

  double get total => price * quantity;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'product_id': productId,
      'name': name,
      'price': price,
      'quantity': quantity,
      'unit': unit,
    };
    if (setId != null) {
      map['set_id'] = setId;
    }
    return map;
  }
}
