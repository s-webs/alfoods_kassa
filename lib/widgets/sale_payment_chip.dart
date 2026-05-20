import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/sale.dart';
import '../models/sale_payment_method.dart';

class SalePaymentChip extends StatelessWidget {
  const SalePaymentChip({
    super.key,
    required this.sale,
    this.compact = false,
  });

  final Sale sale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final method = SalePaymentMethod.tryParse(sale.paymentMethod);
    final label = method?.label ?? (sale.paymentMethod ?? '—');
    final isOfd = method?.requiresFiscalization ?? false;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _chip(
          label,
          isOfd ? AppColors.primary : AppColors.muted,
          isOfd ? AppColors.primaryLight.withValues(alpha: 0.5) : AppColors.muted.withValues(alpha: 0.15),
        ),
        if (isOfd)
          _chip(
            'ОФД',
            AppColors.primary,
            AppColors.primaryLight.withValues(alpha: 0.35),
          ),
        if (!compact && sale.webkassaCheckNumber != null && sale.webkassaCheckNumber!.isNotEmpty)
          _chip(
            'Фиск. ${sale.webkassaCheckNumber}',
            AppColors.muted,
            AppColors.muted.withValues(alpha: 0.12),
          ),
      ],
    );
  }

  Widget _chip(String text, Color fg, Color bg) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class SaleListAmountTitle extends StatelessWidget {
  const SaleListAmountTitle({
    super.key,
    required this.sale,
    this.prominent = false,
    this.amount,
  });

  final Sale sale;

  /// Крупный вариант для блока «Итого» на карточке продажи.
  final bool prominent;

  /// Переопределение суммы (например, черновик корзины до сохранения).
  final double? amount;

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.w600);
    final total = amount ?? sale.totalPrice;

    if (sale.isPartiallyReturned && !sale.isReturnRecord) {
      final remaining = (total - sale.totalReturnedAmount).clamp(0, double.infinity);
      final struckStyle = prominent
          ? Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.muted,
                decoration: TextDecoration.lineThrough,
                fontWeight: FontWeight.w500,
              )
          : bold.copyWith(
              color: AppColors.muted,
              decoration: TextDecoration.lineThrough,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            );
      final remainingStyle = prominent
          ? Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              )
          : bold;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${total.toStringAsFixed(2)} ₸', style: struckStyle),
          const SizedBox(width: 8),
          Text(
            '${remaining.toStringAsFixed(2)} ₸',
            style: remainingStyle,
          ),
        ],
      );
    }

    if (prominent) {
      return Text(
        '${total.toStringAsFixed(2)} ₸',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
      );
    }
    return Text('${total.toStringAsFixed(2)} ₸', style: bold);
  }
}

class SaleStatusChip extends StatelessWidget {
  const SaleStatusChip({super.key, required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (sale.status) {
      Sale.statusReturned when sale.isReturnRecord => (
          'Возврат',
          AppColors.accent,
          AppColors.accent.withValues(alpha: 0.15),
        ),
      Sale.statusReturned => (
          'Полный возврат',
          const Color(0xFF8A6D00),
          const Color(0xFFFFF3CD),
        ),
      Sale.statusPartiallyReturned => (
          'Частичный возврат',
          AppColors.accent,
          AppColors.accent.withValues(alpha: 0.12),
        ),
      _ => (
          'Продажа',
          AppColors.primary,
          AppColors.primaryLight.withValues(alpha: 0.5),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
