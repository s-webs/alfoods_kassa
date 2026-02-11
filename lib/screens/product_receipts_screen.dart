import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/product_receipt.dart';
import '../services/api_service.dart';

class ProductReceiptsScreen extends StatefulWidget {
  const ProductReceiptsScreen({
    super.key,
    required this.apiService,
  });

  final ApiService apiService;

  @override
  State<ProductReceiptsScreen> createState() => _ProductReceiptsScreenState();
}

class _ProductReceiptsScreenState extends State<ProductReceiptsScreen> {
  List<ProductReceipt> _receipts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final receipts = await widget.apiService.getProductReceipts();
      final sorted = List<ProductReceipt>.from(receipts)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _receipts = sorted;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить поступления';
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.muted.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Поступления товара',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => context.push('/product-receipts/create'),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Добавить'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(color: AppColors.danger),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _receipts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 64,
                                    color: AppColors.muted,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Нет поступлений',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _receipts.length,
                              itemBuilder: (context, index) {
                                final receipt = _receipts[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                                      child: Icon(
                                        Icons.inventory_2,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                    title: Text(
                                      '${receipt.totalPrice.toStringAsFixed(2)} ₸',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(receipt.supplierDisplayName),
                                        Text(
                                          _formatDate(receipt.createdAt),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Text(
                                      '${receipt.items.length} шт.',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    onTap: () => context.push(
                                      '/product-receipts/${receipt.id}',
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}
