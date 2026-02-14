import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/label_pdf_service.dart';
import '../utils/barcode_image_helper.dart';

/// Холст этикетки/ценника: блоки можно перетаскивать (менять x, y).
class LabelCanvas extends StatefulWidget {
  const LabelCanvas({
    super.key,
    required this.product,
    required this.blockLayout,
    required this.widthMm,
    required this.heightMm,
    required this.onLayoutChanged,
    this.style = const LabelStyle(),
  });

  final Product? product;
  final List<LabelBlockLayout> blockLayout;
  final double widthMm;
  final double heightMm;
  final void Function(List<LabelBlockLayout>) onLayoutChanged;
  final LabelStyle style;

  @override
  State<LabelCanvas> createState() => _LabelCanvasState();
}

class _LabelCanvasState extends State<LabelCanvas> {
  Uint8List? _barcodePng;

  static const double _scale = 3.5;

  @override
  void initState() {
    super.initState();
    _loadBarcode();
  }

  @override
  void didUpdateWidget(LabelCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product?.barcode != widget.product?.barcode ||
        oldWidget.style.barcodeWidthFactor != widget.style.barcodeWidthFactor ||
        oldWidget.style.barcodeHeightFactor != widget.style.barcodeHeightFactor) {
      _loadBarcode();
    }
  }

  Future<void> _loadBarcode() async {
    final barcode = widget.product?.barcode?.trim();
    if (barcode == null || barcode.isEmpty) {
      setState(() => _barcodePng = null);
      return;
    }
    final w = (_w * widget.style.barcodeWidthFactor * 2).round().clamp(50, 800);
    final h = (_h * widget.style.barcodeHeightFactor * 2).round().clamp(20, 400);
    final bytes = await barcodeToPngBytes(barcode, width: w, height: h);
    if (mounted) setState(() => _barcodePng = bytes);
  }

  double get _w => widget.widthMm * _scale;
  double get _h => widget.heightMm * _scale;

  void _onBlockDrag(int index, Offset delta) {
    if (index < 0 || index >= widget.blockLayout.length) return;
    final layout = widget.blockLayout[index];
    var nx = layout.x + delta.dx / _w;
    var ny = layout.y + delta.dy / _h;
    nx = nx.clamp(0.0, 0.92);
    ny = ny.clamp(0.0, 0.92);
    final newLayout = List<LabelBlockLayout>.from(widget.blockLayout);
    newLayout[index] = layout.copyWith(x: nx, y: ny);
    widget.onLayoutChanged(newLayout);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.muted),
        borderRadius: BorderRadius.circular(8),
      ),
      child: product == null
          ? const Center(child: Text('Нет товара для превью'))
          : Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < widget.blockLayout.length; i++)
                  _buildBlockAt(i, product),
              ],
            ),
    );
  }

  Widget _buildBlockAt(int index, Product product) {
    final layout = widget.blockLayout[index];
    final left = layout.x * _w;
    final top = layout.y * _h;

    final fs = widget.style.nameFontSize * 1.25; // pt → Flutter logical px
    final fp = widget.style.priceFontSize * 1.25;
    final fd = widget.style.descriptionFontSize * 1.25;

    Widget content;
    switch (layout.type) {
      case LabelBlockType.name:
        content = Container(
          padding: const EdgeInsets.all(4),
          constraints: BoxConstraints(maxWidth: _w * 0.9),
          child: Text(
            product.name,
            style: TextStyle(fontSize: fs),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
        break;
      case LabelBlockType.barcode:
        if (_barcodePng != null) {
          content = SizedBox(
            width: _w * widget.style.barcodeWidthFactor,
            height: _h * widget.style.barcodeHeightFactor,
            child: Image.memory(_barcodePng!, fit: BoxFit.contain),
          );
        } else {
          content = SizedBox(
            width: 80,
            height: 24,
            child: Text('Штрихкод', style: TextStyle(fontSize: fs * 0.8)),
          );
        }
        break;
      case LabelBlockType.price:
        content = Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            product.effectivePrice.toStringAsFixed(2),
            style: TextStyle(fontSize: fp, fontWeight: FontWeight.bold),
          ),
        );
        break;
      case LabelBlockType.description:
        final desc = product.meta?['description']?.toString() ?? '';
        content = Container(
          padding: const EdgeInsets.all(4),
          constraints: BoxConstraints(maxWidth: _w * 0.9),
          child: Text(
            desc.isNotEmpty ? desc : 'Описание',
            style: TextStyle(fontSize: fd, color: desc.isEmpty ? AppColors.muted : null),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        );
        break;
    }

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) => _onBlockDrag(index, details.delta),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.2),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
