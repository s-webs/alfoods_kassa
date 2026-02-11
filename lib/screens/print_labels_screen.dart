import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/label_pdf_service.dart';
import '../widgets/label_canvas.dart';
import '../widgets/label_style_controls.dart';

/// Экран генератора этикеток и ценников: расположение блоков на холсте (название | штрихкод | цена), превью, экспорт в PDF.
class PrintLabelsScreen extends StatefulWidget {
  const PrintLabelsScreen({
    super.key,
    required this.storage,
    required this.apiService,
    this.initialProductIds,
    this.mode = PrintLabelsMode.labels,
  });

  final Storage storage;
  final ApiService apiService;
  final List<int>? initialProductIds;
  final PrintLabelsMode mode;

  @override
  State<PrintLabelsScreen> createState() => _PrintLabelsScreenState();
}

enum PrintLabelsMode { labels, priceTags }

class _PrintLabelsScreenState extends State<PrintLabelsScreen> {
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  List<LabelBlockLayout> _blockLayout = LabelBlockLayout.defaultLayout;
  double _widthMm = 40;
  double _heightMm = 30;
  LabelStyle _labelStyle = const LabelStyle();
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _loadTemplateFromStorage();
    _widthController = TextEditingController(text: _widthMm.toStringAsFixed(0));
    _heightController = TextEditingController(text: _heightMm.toStringAsFixed(0));
    _loadProducts();
  }

  void _loadTemplateFromStorage() {
    final storageJson = widget.mode == PrintLabelsMode.labels
        ? widget.storage.labelTemplateJson
        : widget.storage.priceTagTemplateJson;
    final defaultTpl = widget.mode == PrintLabelsMode.labels
        ? LabelTemplate.defaultLabel()
        : LabelTemplate.defaultPriceTag();
    final tpl = storageJson != null
        ? LabelTemplate.fromJson(storageJson)
        : defaultTpl;
    _blockLayout = tpl.blockLayout;
    _widthMm = tpl.widthMm;
    _heightMm = tpl.heightMm;
    _labelStyle = tpl.style;
  }

  @override
  void didUpdateWidget(PrintLabelsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _loadTemplateFromStorage();
      _widthController.text = _widthMm.toStringAsFixed(0);
      _heightController.text = _heightMm.toStringAsFixed(0);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ids = widget.initialProductIds;
      if (ids != null && ids.isNotEmpty) {
        final list = <Product>[];
        for (final id in ids) {
          final p = await widget.apiService.getProduct(id);
          list.add(p);
        }
        if (!mounted) return;
        setState(() {
          _products = list;
          _isLoading = false;
        });
      } else {
        final all = await widget.apiService.getProducts();
        if (!mounted) return;
        setState(() {
          _products = all;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить товары';
        _isLoading = false;
      });
    }
  }

  static const double _minSizeMm = 10;
  static const double _maxSizeMm = 200;

  LabelTemplate _templateForProduct(Product product) {
    final metaKey = widget.mode == PrintLabelsMode.labels ? 'label' : 'priceTag';
    final metaVal = product.meta?[metaKey];
    if (metaVal is Map<String, dynamic>) {
      return LabelTemplate.fromJson(metaVal);
    }
    if (metaVal is Map) {
      return LabelTemplate.fromJson(Map<String, dynamic>.from(metaVal as Map));
    }
    return LabelTemplate(
      blockLayout: _blockLayout,
      style: _labelStyle,
      widthMm: _widthMm,
      heightMm: _heightMm,
    );
  }

  Future<void> _saveJpg() async {
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет товаров для печати')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выберите папку для сохранения этикеток',
      );
      if (dirPath == null || !mounted) return;

      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final usedNames = <String>{};
      var saved = 0;
      for (final product in _products) {
        var fileName = LabelPdfService.labelFileName(product);
        var baseName = fileName;
        var suffix = 1;
        while (usedNames.contains(fileName)) {
          final dot = baseName.lastIndexOf('.');
          final nameWithoutExt = dot > 0 ? baseName.substring(0, dot) : baseName;
          final ext = dot > 0 ? baseName.substring(dot) : '.jpg';
          fileName = '${nameWithoutExt}_$suffix$ext';
          suffix++;
        }
        usedNames.add(fileName);

        final tpl = _templateForProduct(product);
        final bytes = await LabelPdfService.buildLabelJpg(
          product: product,
          blockLayout: tpl.blockLayout,
          widthMm: tpl.widthMm,
          heightMm: tpl.heightMm,
          style: tpl.style,
        );
        if (!mounted) return;
        final savePath = '${dir.path}${Platform.pathSeparator}$fileName';
        await File(savePath).writeAsBytes(bytes);
        saved++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено $saved этикеток в $dirPath')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == PrintLabelsMode.labels
        ? 'Печать этикеток'
        : 'Печать ценников';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_products.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Товаров: ${_products.length}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadProducts,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Размер холста (мм)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          DropdownButton<LabelPreset>(
                            value: widget.mode == PrintLabelsMode.labels
                                ? LabelPreset.label
                                : LabelPreset.priceTag,
                            items: const [
                              DropdownMenuItem(
                                value: LabelPreset.label,
                                child: Text('Этикетка 40×30'),
                              ),
                              DropdownMenuItem(
                                value: LabelPreset.priceTag,
                                child: Text('Ценник 58×30'),
                              ),
                            ],
                            onChanged: (p) {
                              if (p != null) {
                                setState(() {
                                  _widthMm = p.widthMm;
                                  _heightMm = p.heightMm;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: _widthController,
                              decoration: const InputDecoration(
                                labelText: 'Ширина (мм)',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final n = double.tryParse(v);
                                if (n != null && n >= _minSizeMm && n <= _maxSizeMm) {
                                  setState(() => _widthMm = n);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: _heightController,
                              decoration: const InputDecoration(
                                labelText: 'Высота (мм)',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final n = double.tryParse(v);
                                if (n != null && n >= _minSizeMm && n <= _maxSizeMm) {
                                  setState(() => _heightMm = n);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Оформление',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LabelStyleControls(
                        style: _labelStyle,
                        onChanged: (s) => setState(() => _labelStyle = s),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Расположение блоков на холсте (перетащите блоки)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LabelCanvas(
                        product: _products.isNotEmpty ? _products.first : null,
                        blockLayout: _blockLayout,
                        widthMm: _widthMm,
                        heightMm: _heightMm,
                        style: _labelStyle,
                        onLayoutChanged: (layout) {
                          setState(() => _blockLayout = layout);
                        },
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isSaving || _products.isEmpty
                            ? null
                            : _saveJpg,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf),
                        label: Text(_isSaving ? 'Сохранение…' : 'Сохранить JPG'),
                      ),
                      if (_products.isEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Нет товаров. Добавьте товары на экране «Товары».',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
