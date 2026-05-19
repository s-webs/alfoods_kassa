import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/sale_payment_method.dart';

class PosPaymentMethodDialog extends StatelessWidget {
  const PosPaymentMethodDialog({
    super.key,
    required this.kaspiEnabled,
  });

  final bool kaspiEnabled;

  static Future<SalePaymentMethod?> show(
    BuildContext context, {
    required bool kaspiEnabled,
  }) {
    return showDialog<SalePaymentMethod>(
      context: context,
      builder: (ctx) => PosPaymentMethodDialog(kaspiEnabled: kaspiEnabled),
    );
  }

  static const _options = <_PaymentOption>[
    _PaymentOption(
      method: SalePaymentMethod.cashOfd,
      asset: 'assets/payments_type/cash.png',
    ),
    _PaymentOption(
      method: SalePaymentMethod.cardOfd,
      asset: 'assets/payments_type/card.png',
    ),
    _PaymentOption(
      method: SalePaymentMethod.mobileOfd,
      asset: 'assets/payments_type/mobile.png',
    ),
    _PaymentOption(
      method: SalePaymentMethod.kaspiCard,
      asset: 'assets/payments_type/kaspi_card.png',
      requiresKaspi: true,
    ),
    _PaymentOption(
      method: SalePaymentMethod.kaspiQr,
      asset: 'assets/payments_type/kaspi_qr.png',
      requiresKaspi: true,
    ),
  ];

  static double _dialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth.clamp(560.0, 920.0) * 0.82;
  }

  @override
  Widget build(BuildContext context) {
    final width = _dialogWidth(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: const Text('POS Оплата'),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.15,
              ),
              itemCount: _options.length,
              itemBuilder: (context, index) {
                final option = _options[index];
                final enabled =
                    !option.requiresKaspi || kaspiEnabled;
                return _OptionTile(
                  asset: option.asset,
                  label: option.method.label,
                  enabled: enabled,
                  onTap: enabled
                      ? () => Navigator.pop(context, option.method)
                      : null,
                );
              },
            ),
            if (!kaspiEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Kaspi: настройте терминал в параметрах кассы',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}

class _PaymentOption {
  const _PaymentOption({
    required this.method,
    required this.asset,
    this.requiresKaspi = false,
  });

  final SalePaymentMethod method;
  final String asset;
  final bool requiresKaspi;
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.asset,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String asset;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Image.asset(
              asset,
              width: double.infinity,
              fit: BoxFit.fitWidth,
              semanticLabel: label,
            ),
          ),
        ),
      ),
    );
  }
}
