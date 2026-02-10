import 'package:flutter/material.dart';

import '../models/cart_item.dart';

/// Состояние кассы (корзина и id последней сохранённой продажи).
/// Живёт в Shell и не сбрасывается при переходе на другие экраны.
class CashierState extends ChangeNotifier {
  final List<CartItem> _cart = [];
  int? _lastSavedSaleId;

  List<CartItem> get cart => _cart;
  int? get lastSavedSaleId => _lastSavedSaleId;

  void addItem(CartItem item) {
    _lastSavedSaleId = null;
    _cart.add(item);
    notifyListeners();
  }

  void addOrIncrementQuantity(int productId, double step, CartItem newItem) {
    _lastSavedSaleId = null;
    final i = _cart.indexWhere((c) => c.productId == productId);
    if (i >= 0) {
      _cart[i].quantity += step;
    } else {
      _cart.add(newItem);
    }
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _cart.length) return;
    _lastSavedSaleId = null;
    _cart.removeAt(index);
    notifyListeners();
  }

  void updateQuantityAt(int index, double value) {
    if (index < 0 || index >= _cart.length) return;
    _lastSavedSaleId = null;
    if (value <= 0) {
      _cart.removeAt(index);
    } else {
      _cart[index].quantity = value;
    }
    notifyListeners();
  }

  void updateNameAt(int index, String name) {
    if (index < 0 || index >= _cart.length) return;
    _lastSavedSaleId = null;
    _cart[index].name = name;
    notifyListeners();
  }

  void updatePriceAt(int index, double price) {
    if (index < 0 || index >= _cart.length) return;
    _lastSavedSaleId = null;
    _cart[index].price = price;
    notifyListeners();
  }

  void setLastSavedSaleId(int? id) {
    if (_lastSavedSaleId == id) return;
    _lastSavedSaleId = id;
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _lastSavedSaleId = null;
    notifyListeners();
  }

  double get cartTotal => _cart.fold(0.0, (sum, item) => sum + item.total);

  /// Вызвать после изменения элемента корзины «на месте» (например, quantity через +/-).
  void notifyCartChanged() {
    _lastSavedSaleId = null;
    notifyListeners();
  }
}

/// Прокидывает [CashierState] вниз по дереву (из Shell).
class CashierStateScope extends InheritedWidget {
  const CashierStateScope({
    super.key,
    required this.state,
    required super.child,
  });

  final CashierState state;

  static CashierState of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CashierStateScope>();
    assert(scope != null, 'CashierStateScope not found');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(CashierStateScope oldWidget) =>
      state != oldWidget.state;
}
