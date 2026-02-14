import 'package:flutter/material.dart';

import '../services/label_pdf_service.dart';

/// Элементы управления оформлением этикетки: размер шрифта, размер штрихкода.
class LabelStyleControls extends StatelessWidget {
  const LabelStyleControls({
    super.key,
    required this.style,
    required this.onChanged,
    this.blockLayout,
    this.onLayoutChanged,
  });

  final LabelStyle style;
  final void Function(LabelStyle) onChanged;
  final List<LabelBlockLayout>? blockLayout;
  final void Function(List<LabelBlockLayout>)? onLayoutChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Показать границу', style: TextStyle(fontSize: 14)),
              value: style.showBorder,
              onChanged: (v) => onChanged(style.copyWith(showBorder: v)),
              contentPadding: EdgeInsets.zero,
            ),
            if (blockLayout != null && onLayoutChanged != null) ...[
              const SizedBox(height: 8),
              const Text('Видимость блоков', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...blockLayout!.asMap().entries.map((e) {
                final i = e.key;
                final layout = e.value;
                return SwitchListTile(
                  title: Text(layout.type.title, style: const TextStyle(fontSize: 13)),
                  value: layout.visible,
                  onChanged: (v) {
                    final newLayout = List<LabelBlockLayout>.from(blockLayout!);
                    newLayout[i] = layout.copyWith(visible: v);
                    onLayoutChanged!(newLayout);
                  },
                  contentPadding: EdgeInsets.zero,
                );
              }),
              const SizedBox(height: 8),
            ],
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
              'Размер шрифта описания: ${style.descriptionFontSize.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12),
            ),
            Slider(
              value: style.descriptionFontSize,
              min: LabelStyle.minFontSize,
              max: LabelStyle.maxFontSize,
              divisions: 16,
              label: style.descriptionFontSize.toStringAsFixed(0),
              onChanged: (v) => onChanged(style.copyWith(descriptionFontSize: v)),
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
