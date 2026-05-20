import 'package:flutter/material.dart';

import '../models/cart_item.dart';

/// Состояние одной параллельной кассы (корзина + флаги активной продажи).
/// Служебная структура для [CashierState]; снаружи не используется напрямую.
class RegisterCart {
  final List<CartItem> cart = [];
  int? lastSavedSaleId;
  bool saleNeedsSync = false;
  int nextOrderIndex = 1;
}

/// Состояние кассы (одной или нескольких параллельных).
///
/// Живёт в Shell и не сбрасывается при переходе на другие экраны.
/// Поддерживает несколько параллельных касс: например, кассир может отложить
/// текущего покупателя, переключиться на «Кассу 2», быстро обслужить клиента
/// с парой товаров и вернуться к первой корзине — состояние обеих сохранится.
///
/// Внешний API построен так, что бо́льшая часть методов работает с *активным*
/// регистром. Старый код, написанный под одну корзину, продолжает работать
/// без изменений — он просто оперирует активной кассой.
class CashierState extends ChangeNotifier {
  CashierState({int registerCount = 2})
      : assert(registerCount >= 1),
        _registers = List.generate(registerCount, (_) => RegisterCart());

  final List<RegisterCart> _registers;
  int _activeIndex = 0;

  // ---------------------------------------------------------------------------
  // Управление активной кассой
  // ---------------------------------------------------------------------------

  /// Сколько параллельных касс всего.
  int get registerCount => _registers.length;

  /// Индекс активной кассы (0..registerCount-1).
  int get activeIndex => _activeIndex;

  /// Переключить активную кассу. Обе корзины при этом сохраняются.
  void setActiveIndex(int index) {
    if (index < 0 || index >= _registers.length) return;
    if (_activeIndex == index) return;
    _activeIndex = index;
    notifyListeners();
  }

  RegisterCart get _active => _registers[_activeIndex];

  /// Количество позиций в корзине указанной кассы (для бейджа на вкладке).
  int cartLengthAt(int index) {
    if (index < 0 || index >= _registers.length) return 0;
    return _registers[index].cart.length;
  }

  /// Сумма корзины указанной кассы (может пригодиться для бейджа/подсказки).
  double cartTotalAt(int index) {
    if (index < 0 || index >= _registers.length) return 0.0;
    return _registers[index].cart.fold(0.0, (sum, it) => sum + it.total);
  }

  /// Есть ли хоть в одной из касс непустая корзина (например, для
  /// предупреждения «есть незавершённые продажи»).
  bool get hasAnyCartItems => _registers.any((r) => r.cart.isNotEmpty);

  // ---------------------------------------------------------------------------
  // API активной кассы (совместим с прежней однокассовой версией)
  // ---------------------------------------------------------------------------

  List<CartItem> get cart => _active.cart;
  int? get lastSavedSaleId => _active.lastSavedSaleId;
  bool get saleNeedsSync => _active.saleNeedsSync;

  void addItem(CartItem item) {
    final r = _active;
    r.saleNeedsSync = true;
    final indexed = item.copyWith(orderIndex: r.nextOrderIndex++);
    r.cart.insert(0, indexed);
    notifyListeners();
  }

  void addOrIncrementQuantity(
    int productId,
    double step,
    CartItem newItem, {
    int? setId,
  }) {
    final r = _active;
    r.saleNeedsSync = true;
    final i = r.cart.indexWhere((c) {
      if (setId != null) {
        return c.setId == setId;
      }
      return c.productId == productId;
    });
    if (i >= 0) {
      r.cart[i].quantity += step;
    } else {
      final indexed = newItem.copyWith(orderIndex: r.nextOrderIndex++);
      r.cart.insert(0, indexed);
    }
    notifyListeners();
  }

  void removeAt(int index) {
    final r = _active;
    if (index < 0 || index >= r.cart.length) return;
    r.saleNeedsSync = true;
    r.cart.removeAt(index);
    notifyListeners();
  }

  void updateQuantityAt(int index, double value) {
    final r = _active;
    if (index < 0 || index >= r.cart.length) return;
    r.saleNeedsSync = true;
    if (value <= 0) {
      r.cart.removeAt(index);
    } else {
      r.cart[index].quantity = value;
    }
    notifyListeners();
  }

  void updateNameAt(int index, String name) {
    final r = _active;
    if (index < 0 || index >= r.cart.length) return;
    r.saleNeedsSync = true;
    r.cart[index].name = name;
    notifyListeners();
  }

  void updatePriceAt(int index, double price) {
    final r = _active;
    if (index < 0 || index >= r.cart.length) return;
    r.saleNeedsSync = true;
    r.cart[index].price = price;
    notifyListeners();
  }

  void setLastSavedSaleId(int? id) {
    final r = _active;
    if (r.lastSavedSaleId == id) return;
    r.lastSavedSaleId = id;
    r.saleNeedsSync = false;
    notifyListeners();
  }

  /// Полностью очистить активную корзину (cart + lastSavedSaleId).
  void clearCart() {
    final r = _active;
    r.cart.clear();
    r.lastSavedSaleId = null;
    r.saleNeedsSync = false;
    r.nextOrderIndex = 1;
    notifyListeners();
  }

  double get cartTotal =>
      _active.cart.fold(0.0, (sum, item) => sum + item.total);

  double get cartTotalQty =>
      _active.cart.fold(0.0, (sum, item) => sum + item.quantity);

  /// Вызвать после изменения элемента корзины «на месте» (например, quantity
  /// через +/-), чтобы подписчики перерисовались и сработала синхронизация.
  void notifyCartChanged() {
    _active.saleNeedsSync = true;
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
