import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';

String nktExtractDioError(DioException e, {required String fallback}) {
  final data = e.response?.data;
  if (data is Map) {
    final msg = data['message']?.toString();
    if (msg != null && msg.isNotEmpty) return msg;
  }
  return fallback;
}

class NktLoadingDialog extends StatelessWidget {
  const NktLoadingDialog({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Text(text),
          ],
        ),
      ),
    );
  }
}

class NktVariantTile extends StatelessWidget {
  const NktVariantTile({
    super.key,
    required this.variant,
    this.selected = false,
    this.isLinked = false,
    this.onTap,
    this.showRadio = false,
    String? groupValue,
    ValueChanged<String?>? onRadioChanged,
  })  : _groupValue = groupValue,
        _onRadioChanged = onRadioChanged;

  final NktVariant variant;
  final bool selected;
  final bool isLinked;
  final VoidCallback? onTap;
  final bool showRadio;
  final String? _groupValue;
  final ValueChanged<String?>? _onRadioChanged;

  @override
  Widget build(BuildContext context) {
    final v = variant;
    final ntin = v.ntinCode ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected || isLinked
                ? AppColors.primary
                : AppColors.muted.withValues(alpha: 0.4),
            width: selected || isLinked ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: selected
              ? AppColors.primaryLight.withValues(alpha: 0.4)
              : isLinked
                  ? AppColors.accent.withValues(alpha: 0.08)
                  : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showRadio)
              Radio<String>(
                value: ntin,
                groupValue: _groupValue ?? '',
                onChanged: _onRadioChanged,
              ),
            if (showRadio) const SizedBox(width: 4),
            Expanded(child: _NktVariantBody(variant: v, isLinked: isLinked)),
          ],
        ),
      ),
    );
  }
}

class _NktVariantBody extends StatelessWidget {
  const _NktVariantBody({required this.variant, this.isLinked = false});

  final NktVariant variant;
  final bool isLinked;

  @override
  Widget build(BuildContext context) {
    final v = variant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                v.nameRu ?? v.nameKk ?? '(без названия)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isLinked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Привязан',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        if (v.nameKk != null &&
            v.nameKk != v.nameRu &&
            v.nameKk!.isNotEmpty)
          Text(
            v.nameKk!,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        const SizedBox(height: 4),
        Text(
          'NTIN: ${v.ntinCode ?? '—'}'
          '${v.gtin != null ? '   GTIN: ${v.gtin}' : ''}'
          '${v.measureName != null ? '   Ед: ${v.measureName}' : ''}',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (v.isMarkedeac == true)
              const NktVariantBadge(
                label: 'Маркировка',
                color: AppColors.accent,
                icon: Icons.qr_code_2,
              ),
            if (v.isSocial == true)
              const NktVariantBadge(label: 'СЗПТ', color: AppColors.primary),
            if (v.isDeactivated == true)
              const NktVariantBadge(
                label: 'Деактивирован',
                color: AppColors.danger,
              ),
          ],
        ),
      ],
    );
  }
}

class NktVariantBadge extends StatelessWidget {
  const NktVariantBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Диалог выбора варианта из ответа НКТ. Возвращает NTIN или null.
Future<String?> showNktVariantPickerDialog({
  required BuildContext context,
  required Product product,
  required NktSearchResult result,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _NktVariantPickerDialog(product: product, result: result),
  );
}

class _NktVariantPickerDialog extends StatefulWidget {
  const _NktVariantPickerDialog({
    required this.product,
    required this.result,
  });

  final Product product;
  final NktSearchResult result;

  @override
  State<_NktVariantPickerDialog> createState() => _NktVariantPickerDialogState();
}

class _NktVariantPickerDialogState extends State<_NktVariantPickerDialog> {
  String? _picked;

  @override
  void initState() {
    super.initState();
    final variants = widget.result.variants;
    if (variants.length == 1) {
      _picked = variants.first.ntinCode;
    } else if (widget.product.nktNtin != null &&
        widget.product.nktNtin!.isNotEmpty) {
      _picked = widget.product.nktNtin;
    }
  }

  @override
  Widget build(BuildContext context) {
    final variants = widget.result.variants;
    final single = variants.length == 1;
    final barcode =
        widget.product.barcode ?? widget.result.barcode ?? '—';

    return AlertDialog(
      title: Text(single ? 'Найден товар в НКТ' : 'Варианты в НКТ'),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Локальный товар: ${widget.product.name}\nШтрихкод: $barcode',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (widget.result.cached)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Данные из кэша',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: variants.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (_, i) {
                  final v = variants[i];
                  final ntin = v.ntinCode ?? '';
                  return NktVariantTile(
                    variant: v,
                    selected: _picked == ntin,
                    isLinked: widget.product.nktNtin == ntin,
                    showRadio: true,
                    groupValue: _picked ?? '',
                    onRadioChanged: (val) => setState(() => _picked = val),
                    onTap: () => setState(() => _picked = ntin),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        FilledButton(
          onPressed: (_picked != null && _picked!.isNotEmpty)
              ? () => Navigator.pop(context, _picked)
              : null,
          child: const Text('Привязать'),
        ),
      ],
    );
  }
}
