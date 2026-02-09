import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/storage.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/shift.dart';
import '../services/api_service.dart';
import '../widgets/add_product_dialog.dart';

class CashierScreen extends StatefulWidget {
  const CashierScreen({
    super.key,
    required this.storage,
    required this.apiService,
  });

  final Storage storage;
  final ApiService apiService;

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  List<Shift> _shifts = [];
  List<CartItem> _cart = [];
  bool _isLoading = true;
  bool _isOpeningShift = false;
  bool _isClosingShift = false;
  bool _isSelling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final shifts = await widget.apiService.getShifts();
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить смены';
        _isLoading = false;
      });
    }
  }

  Future<void> _openShift() async {
    setState(() {
      _isOpeningShift = true;
      _error = null;
    });
    try {
      await widget.apiService.createShift();
      await _loadShifts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось открыть смену';
        _isOpeningShift = false;
      });
    }
  }

  Future<void> _closeShift() async {
    final shift = _currentOpenShift;
    if (shift == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Закрыть смену?'),
        content: const Text(
          'Вы уверены, что хотите закрыть текущую смену?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _isClosingShift = true;
      _error = null;
    });
    try {
      await widget.apiService.closeShift(shift.id);
      await _loadShifts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось закрыть смену';
        _isClosingShift = false;
      });
    }
  }

  void _addProduct(Product product) {
    setState(() {
      final existingIndex =
          _cart.indexWhere((c) => c.productId == product.id);
      if (existingIndex >= 0) {
        _cart[existingIndex].quantity += 1;
      } else {
        _cart.add(CartItem(
          productId: product.id,
          name: product.name,
          price: product.effectivePrice,
          quantity: 1,
          unit: product.unit,
        ));
      }
    });
  }

  void _updateQuantity(int index, double delta) {
    setState(() {
      final item = _cart[index];
      item.quantity += delta;
      if (item.quantity <= 0) {
        _cart.removeAt(index);
      }
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  Future<void> _showAddProductDialog() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (ctx) => AddProductDialog(apiService: widget.apiService),
    );
    if (product != null && mounted) {
      _addProduct(product);
    }
  }

  Future<void> _sell() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Корзина пуста')),
      );
      return;
    }
    final shift = _currentOpenShift;
    if (shift == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Смена не открыта')),
      );
      return;
    }

    setState(() {
      _isSelling = true;
      _error = null;
    });
    try {
      final items = _cart.map((c) => c.toJson()).toList();
      await widget.apiService.createSale(
        shiftId: shift.id,
        items: items,
      );
      if (!mounted) return;
      setState(() {
        _cart = [];
        _isSelling = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Продажа оформлена')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось оформить продажу';
        _isSelling = false;
      });
    }
  }

  Shift? get _currentOpenShift {
    for (final s in _shifts) {
      if (s.isOpen) return s;
    }
    return null;
  }

  double get _cartTotal {
    return _cart.fold(0, (sum, item) => sum + item.total);
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildShiftBlock(context),
        if (_error != null) _buildErrorBlock(context),
        Expanded(child: _buildCartBlock(context)),
        _buildActionBlock(context),
      ],
    );
  }

  Widget _buildShiftBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
        ),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentOpenShift == null
              ? Row(
                  children: [
                    Icon(Icons.schedule, color: AppColors.muted, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Смена не открыта',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _isOpeningShift ? null : _openShift,
                      icon: _isOpeningShift
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow, size: 20),
                      label: Text(_isOpeningShift ? 'Открытие...' : 'Открыть смену'),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: AppColors.accent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Смена открыта',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'С ${_formatDate(_currentOpenShift!.openedAt)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isClosingShift ? null : _closeShift,
                      icon: _isClosingShift
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.stop_circle, size: 20),
                      label: Text(_isClosingShift ? 'Закрытие...' : 'Закрыть смену'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildErrorBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.danger.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
  }

  Widget _buildCartBlock(BuildContext context) {
    return Container(
      color: AppColors.primaryLight.withValues(alpha: 0.3),
      child: _cart.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 64, color: AppColors.muted),
                  const SizedBox(height: 16),
                  Text(
                    'Корзина пуста',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Добавьте товары через кнопку ниже',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _cart.length,
              itemBuilder: (context, index) {
                final item = _cart[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.price.toStringAsFixed(2)} ₽ × ${item.quantity} ${item.unit}',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _updateQuantity(index, -1),
                              iconSize: 22,
                            ),
                            Text(
                              item.quantity.toStringAsFixed(
                                item.unit == 'pcs' ? 0 : 2,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => _updateQuantity(index, 1),
                              iconSize: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${item.total.toStringAsFixed(2)} ₽',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  color: AppColors.danger, size: 22),
                              onPressed: () => _removeFromCart(index),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildActionBlock(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Итого: ${_cartTotal.toStringAsFixed(2)} ₽',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
              ),
            ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _currentOpenShift != null && !_isSelling
                ? _showAddProductDialog
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Добавить вручную'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _currentOpenShift != null &&
                    _cart.isNotEmpty &&
                    !_isSelling
                ? _sell
                : null,
            icon: _isSelling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.point_of_sale),
            label: Text(_isSelling ? 'Оформление...' : 'Продать'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      ),
    );
  }
}
