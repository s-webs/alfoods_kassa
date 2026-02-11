import 'package:flutter/material.dart';

import '../services/label_pdf_service.dart';

/// Элементы управления оформлением этикетки: размер шрифта, размер штрихкода.
class LabelStyleControls extends StatelessWidget {
  const LabelStyleControls({
    super.key,
    required this.style,
    required this.onChanged,
  });

  final LabelStyle style;
  final void Function(LabelStyle) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Размер шрифта названия: ${style.nameFontSize.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12),
            ),
            Slider(
              value: style.nameFontSize,
              min: LabelStyle.minFontSize,
              max: LabelStyle.maxFontSize,
              divisions: 16,
              label: style.nameFontSize.toStringAsFixed(0),
              onChanged: (v) => onChanged(style.copyWith(nameFontSize: v)),
            ),
            Text(
              'Размер шрифта цены: ${style.priceFontSize.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12),
            ),
            Slider(
              value: style.priceFontSize,
              min: LabelStyle.minFontSize,
              max: LabelStyle.maxFontSize,
              divisions: 16,
              label: style.priceFontSize.toStringAsFixed(0),
              onChanged: (v) => onChanged(style.copyWith(priceFontSize: v)),
            ),
            Text(
              'Ширина штрихкода: ${(style.barcodeWidthFactor * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
            Slider(
              value: style.barcodeWidthFactor,
              min: LabelStyle.minBarcodeFactor,
              max: LabelStyle.maxBarcodeFactor,
              divisions: 17,
              label: '${(style.barcodeWidthFactor * 100).toStringAsFixed(0)}%',
              onChanged: (v) =>
                  onChanged(style.copyWith(barcodeWidthFactor: v)),
            ),
            Text(
              'Высота штрихкода: ${(style.barcodeHeightFactor * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
            Slider(
              value: style.barcodeHeightFactor,
              min: LabelStyle.minBarcodeFactor,
              max: LabelStyle.maxBarcodeFactor,
              divisions: 17,
              label: '${(style.barcodeHeightFactor * 100).toStringAsFixed(0)}%',
              onChanged: (v) =>
                  onChanged(style.copyWith(barcodeHeightFactor: v)),
            ),
          ],
        ),
      ),
    );
  }
}
