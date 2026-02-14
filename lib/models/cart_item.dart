/// Позиция в корзине — снимок данных на момент добавления (название, цена).
/// Редактирование name/price в корзине не затрагивает модель Product.
/// Для сетов: productId = 0, setId != null.
/// orderIndex — постоянный порядковый номер при добавлении (1, 2, 3...), не меняется при добавлении/удалении других.
class CartItem {
  final int productId;
  final int? setId;
  String name;
  double price;
  double quantity;
  final String unit;
  final int orderIndex;

  CartItem({
    required this.productId,
    this.setId,
    required this.name,
    required this.price,
    required this.quantity,
    required this.unit,
    this.orderIndex = 0,
  });

  CartItem copyWith({
    int? productId,
    int? setId,
    String? name,
    double? price,
    double? quantity,
    String? unit,
    int? orderIndex,
  }) =>
      CartItem(
        productId: productId ?? this.productId,
        setId: setId ?? this.setId,
        name: name ?? this.name,
        price: price ?? this.price,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        orderIndex: orderIndex ?? this.orderIndex,
      );

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
