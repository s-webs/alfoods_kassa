import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/product.dart';
import '../models/product_set.dart';
import '../services/api_service.dart';
import '../utils/toast.dart';
import '../services/label_pdf_service.dart';
import '../utils/barcode_generator.dart';
import '../utils/barcode_image_helper.dart';
import '../widgets/add_product_to_set_dialog.dart';
import '../widgets/label_canvas.dart';
import '../widgets/label_style_controls.dart';

class SetFormScreen extends StatefulWidget {
  const SetFormScreen({
    super.key,
    required this.storage,
    required this.apiService,
    this.setId,
    this.mode = SetFormMode.create,
  });

  final Storage storage;
  final ApiService apiService;
  final int? setId;
  final SetFormMode mode;

  @override
  State<SetFormScreen> createState() => _SetFormScreenState();
}

enum SetFormMode { create, edit }

class _SetItem {
  _SetItem({required this.productId, required this.productName, required this.quantity});

  final int productId;
  final String productName;
  double quantity;
}

class _SetFormScreenState extends State<SetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _discountPriceController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _labelDescriptionController = TextEditingController();

  ProductSet? _set;
  List<_SetItem> _items = [];
  bool _isActive = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  Uint8List? _barcodePreviewBytes;
  Timer? _barcodePreviewTimer;
  List<LabelBlockLayout> _labelBlockLayout = LabelBlockLayout.defaultLayout;
  double _labelWidthMm = 40;
  double _labelHeightMm = 30;
  LabelStyle _labelStyle = const LabelStyle();
  List<LabelBlockLayout> _priceTagBlockLayout = LabelBlockLayout.defaultLayout;
  double _priceTagWidthMm = 58;
  double _priceTagHeightMm = 30;
  LabelStyle _priceTagStyle = const LabelStyle();
  bool _isSavingLabel = false;
  bool _isSavingPriceTag = false;
  bool _isPrintingLabel = false;
  bool _isPrintingPriceTag = false;

  static const double _minLabelSizeMm = 10;
  static const double _maxLabelSizeMm = 200;

  @override
  void initState() {
    super.initState();
    _loadData();
    _barcodeController.addListener(_scheduleBarcodePreview);
  }

  void _scheduleBarcodePreview() {
    _barcodePreviewTimer?.cancel();
    _barcodePreviewTimer = Timer(const Duration(milliseconds: 400), _refreshBarcodePreview);
  }

  Future<void> _refreshBarcodePreview() async {
    final s = _barcodeController.text.trim();
    if (s.isEmpty) {
      if (mounted) setState(() => _barcodePreviewBytes = null);
      return;
    }
    final bytes = await barcodeToPngBytes(s, width: 200, height: 80);
    if (mounted) setState(() => _barcodePreviewBytes = bytes);
  }

  Product get _currentSetForLabel {
    final desc = _labelDescriptionController.text.trim();
    if (_set != null) {
      final merged = Map<String, dynamic>.from(_set!.meta ?? {});
      if (desc.isNotEmpty) merged['description'] = desc;
      else merged.remove('description');
      return Product(
        id: 0,
        name: _set!.name,
        slug: '',
        barcode: _set!.barcode,
        price: _set!.price,
        discountPrice: _set!.discountPrice,
        unit: 'pcs',
        meta: merged.isEmpty ? null : merged,
      );
    }
    final metaWithDesc = desc.isEmpty ? null : <String, dynamic>{'description': desc};
    final price = double.tryParse(_priceController.text) ?? 0;
    final discountPrice = double.tryParse(_discountPriceController.text);
    final barcodeStr = _barcodeController.text.trim();
    return Product(
      id: 0,
      name: _nameController.text.trim().isEmpty ? '—' : _nameController.text.trim(),
      slug: '',
      barcode: barcodeStr.isEmpty ? null : barcodeStr,
      price: price,
      discountPrice: discountPrice,
      unit: 'pcs',
      meta: metaWithDesc,
    );
  }

  Future<void> _saveLabelJpg() async {
    setState(() => _isSavingLabel = true);
    try {
      final product = _currentSetForLabel;
      final bytes = await LabelPdfService.buildLabelJpg(
        product: product,
        blockLayout: _labelBlockLayout,
        widthMm: _labelWidthMm,
        heightMm: _labelHeightMm,
        style: _labelStyle,
      );
      if (!mounted) return;
      final fileName = LabelPdfService.labelFileName(product);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить этикетку',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg'],
      );
      if (path != null) {
        final savePath = path.toLowerCase().endsWith('.jpg') ||
                path.toLowerCase().endsWith('.jpeg')
            ? path
            : '$path.jpg';
        await File(savePath).writeAsBytes(bytes);
        if (!mounted) return;
        showToast(context, 'Сохранено: $savePath');
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isSavingLabel = false);
    }
  }

  Future<void> _savePriceTagJpg() async {
    setState(() => _isSavingPriceTag = true);
    try {
      final product = _currentSetForLabel;
      final bytes = await LabelPdfService.buildLabelJpg(
        product: product,
        blockLayout: _priceTagBlockLayout,
        widthMm: _priceTagWidthMm,
        heightMm: _priceTagHeightMm,
        style: _priceTagStyle,
      );
      if (!mounted) return;
      final fileName = LabelPdfService.labelFileName(product);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить ценник',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg'],
      );
      if (path != null) {
        final savePath = path.toLowerCase().endsWith('.jpg') ||
                path.toLowerCase().endsWith('.jpeg')
            ? path
            : '$path.jpg';
        await File(savePath).writeAsBytes(bytes);
        if (!mounted) return;
        showToast(context, 'Сохранено: $savePath');
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _isSavingPriceTag = false);
    }
  }

  Future<void> _printLabel() async {
    setState(() => _isPrintingLabel = true);
    try {
      final product = _currentSetForLabel;
      final bytes = await LabelPdfService.buildLabelPdf(
        products: [product],
        blockLayout: _labelBlockLayout,
        preset: LabelPreset.label,
        widthMm: _labelWidthMm,
        heightMm: _labelHeightMm,
        style: _labelStyle,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Этикетка-${product.name}',
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (mounted) {
        showToast(context, 'Ошибка печати: $e');
      }
    } finally {
      if (mounted) setState(() => _isPrintingLabel = false);
    }
  }

  Future<void> _printPriceTag() async {
    setState(() => _isPrintingPriceTag = true);
    try {
      final product = _currentSetForLabel;
      final bytes = await LabelPdfService.buildLabelPdf(
        products: [product],
        blockLayout: _priceTagBlockLayout,
        preset: LabelPreset.priceTag,
        widthMm: _priceTagWidthMm,
        heightMm: _priceTagHeightMm,
        style: _priceTagStyle,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Ценник-${product.name}',
        format: PdfPageFormat.a4,
      );
    } catch (e) {
      if (mounted) {
        showToast(context, 'Ошибка печати: $e');
      }
    } finally {
      if (mounted) setState(() => _isPrintingPriceTag = false);
    }
  }

  @override
  void dispose() {
    _barcodePreviewTimer?.cancel();
    _barcodeController.removeListener(_scheduleBarcodePreview);
    _nameController.dispose();
    _priceController.dispose();
    _discountPriceController.dispose();
    _barcodeController.dispose();
    _labelDescriptionController.dispose();
    super.dispose();
  }

  LabelTemplate _templateFromMetaOrStorage(
    dynamic metaVal,
    Map<String, dynamic>? storageJson,
    LabelTemplate Function() defaultFn,
  ) {
    if (metaVal is Map<String, dynamic>) {
      return LabelTemplate.fromJson(metaVal);
    }
    if (metaVal is Map) {
      return LabelTemplate.fromJson(Map<String, dynamic>.from(metaVal as Map));
    }
    if (storageJson != null) {
      return LabelTemplate.fromJson(storageJson);
    }
    return defaultFn();
  }

  bool _templateDiffers(LabelTemplate a, LabelTemplate b) {
    if (a.widthMm != b.widthMm || a.heightMm != b.heightMm) return true;
    if (a.style.nameFontSize != b.style.nameFontSize ||
        a.style.priceFontSize != b.style.priceFontSize ||
        a.style.barcodeWidthFactor != b.style.barcodeWidthFactor ||
        a.style.barcodeHeightFactor != b.style.barcodeHeightFactor) {
      return true;
    }
    if (a.blockLayout.length != b.blockLayout.length) return true;
    for (var i = 0; i < a.blockLayout.length; i++) {
      final la = a.blockLayout[i];
      final lb = b.blockLayout[i];
      if (la.type != lb.type || la.x != lb.x || la.y != lb.y) return true;
    }
    return false;
  }

  Map<String, dynamic>? _buildMetaForSave() {
    final defaultLabel = _templateFromMetaOrStorage(
      null,
      widget.storage.labelTemplateJson,
      LabelTemplate.defaultLabel,
    );
    final defaultPriceTag = _templateFromMetaOrStorage(
      null,
      widget.storage.priceTagTemplateJson,
      LabelTemplate.defaultPriceTag,
    );
    final labelTpl = LabelTemplate(
      blockLayout: _labelBlockLayout,
      style: _labelStyle,
      widthMm: _labelWidthMm,
      heightMm: _labelHeightMm,
    );
    final priceTagTpl = LabelTemplate(
      blockLayout: _priceTagBlockLayout,
      style: _priceTagStyle,
      widthMm: _priceTagWidthMm,
      heightMm: _priceTagHeightMm,
    );
    final labelDiff = _templateDiffers(labelTpl, defaultLabel);
    final priceTagDiff = _templateDiffers(priceTagTpl, defaultPriceTag);
    final desc = _labelDescriptionController.text.trim();
    if (!labelDiff && !priceTagDiff && desc.isEmpty) return null;
    final meta = Map<String, dynamic>.from(_set?.meta ?? {});
    if (desc.isNotEmpty) meta['description'] = desc;
    else meta.remove('description');
    if (labelDiff) meta['label'] = labelTpl.toJson();
    if (priceTagDiff) meta['priceTag'] = priceTagTpl.toJson();
    return meta.isEmpty ? null : meta;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (widget.mode == SetFormMode.edit && widget.setId != null) {
        final s = await widget.apiService.getSet(widget.setId!);
        if (!mounted) return;
        final labelTpl = _templateFromMetaOrStorage(
          s.meta?['label'],
          widget.storage.labelTemplateJson,
          LabelTemplate.defaultLabel,
        );
        final priceTagTpl = _templateFromMetaOrStorage(
          s.meta?['priceTag'],
          widget.storage.priceTagTemplateJson,
          LabelTemplate.defaultPriceTag,
        );
        setState(() {
          _set = s;
          _nameController.text = s.name;
          _priceController.text = s.price.toString();
          _discountPriceController.text = s.discountPrice?.toString() ?? '';
          _barcodeController.text = s.barcode ?? '';
          _isActive = s.isActive;
          _items = s.items
              .map((i) => _SetItem(
                    productId: i.productId,
                    productName: i.product?.name ?? 'ID:${i.productId}',
                    quantity: i.quantity,
                  ))
              .toList();
          _labelBlockLayout = labelTpl.blockLayout;
          _labelWidthMm = labelTpl.widthMm;
          _labelHeightMm = labelTpl.heightMm;
          _labelStyle = labelTpl.style;
          _labelDescriptionController.text = s.meta?['description']?.toString() ?? '';
          _priceTagBlockLayout = priceTagTpl.blockLayout;
          _priceTagWidthMm = priceTagTpl.widthMm;
          _priceTagHeightMm = priceTagTpl.heightMm;
          _priceTagStyle = priceTagTpl.style;
          _isLoading = false;
        });
        _refreshBarcodePreview();
      } else {
        final labelTpl = _templateFromMetaOrStorage(
          null,
          widget.storage.labelTemplateJson,
          LabelTemplate.defaultLabel,
        );
        final priceTagTpl = _templateFromMetaOrStorage(
          null,
          widget.storage.priceTagTemplateJson,
          LabelTemplate.defaultPriceTag,
        );
        setState(() {
          _labelBlockLayout = labelTpl.blockLayout;
          _labelWidthMm = labelTpl.widthMm;
          _labelHeightMm = labelTpl.heightMm;
          _labelStyle = labelTpl.style;
          _priceTagBlockLayout = priceTagTpl.blockLayout;
          _priceTagWidthMm = priceTagTpl.widthMm;
          _priceTagHeightMm = priceTagTpl.heightMm;
          _priceTagStyle = priceTagTpl.style;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить данные';
        _isLoading = false;
      });
    }
  }

  Future<void> _addProduct() async {
    final result = await showDialog<AddProductToSetResult>(
      context: context,
      builder: (ctx) => AddProductToSetDialog(
        apiService: widget.apiService,
        excludedProductIds: {},
      ),
    );
    if (result != null && mounted) {
      setState(() {
        final existing = _items.indexWhere((i) => i.productId == result.product.id);
        if (existing >= 0) {
          _items[existing].quantity += result.quantity;
        } else {
          _items.add(_SetItem(
            productId: result.product.id,
            productName: result.product.name,
            quantity: result.quantity,
          ));
        }
      });
    }
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  List<Map<String, dynamic>> _mergeItemsByProductId() {
    final map = <int, double>{};
    for (final item in _items) {
      map[item.productId] = (map[item.productId] ?? 0) + item.quantity;
    }
    return map.entries
        .map((e) => {
              'product_id': e.key,
              'quantity': e.value,
            })
        .toList();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text);
    if (name.isEmpty) return;
    if (price == null || price < 0) {
      showToast(context, 'Введите корректную цену');
      return;
    }
    if (_items.isEmpty) {
      showToast(context, 'Добавьте хотя бы один товар в сет');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{
        'name': name,
        'price': price,
        'barcode': _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        'is_active': _isActive,
        'items': _mergeItemsByProductId(),
      };
      final dp = double.tryParse(_discountPriceController.text);
      if (dp != null && dp > 0) {
        data['discount_price'] = dp;
      }
      final desc = _labelDescriptionController.text.trim();
      if (desc.isNotEmpty) {
        data['meta'] = {'description': desc};
      }
      if (widget.mode == SetFormMode.edit && widget.setId != null) {
        final meta = _buildMetaForSave();
        if (meta != null && meta.isNotEmpty) {
          data['meta'] = meta;
        }
        await widget.apiService.updateSet(widget.setId!, data);
      } else {
        await widget.apiService.createSet(data);
      }
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = e.toString().contains('422')
            ? 'Ошибка валидации'
            : 'Не удалось сохранить';
      });
    }
  }

  Future<void> _delete() async {
    if (widget.setId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сет?'),
        content: Text(
          'Сет «${_set?.name ?? ''}» будет удалён безвозвратно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.deleteSet(widget.setId!);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось удалить';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Сет')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null &&
        _set == null &&
        widget.mode == SetFormMode.edit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Сет')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.danger),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == SetFormMode.edit ? 'Редактирование сета' : 'Новый сет',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'Введите название',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Активен'),
                  const SizedBox(width: 12),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Цена',
                  hintText: '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Обязательное поле';
                  if (double.tryParse(v) == null || double.parse(v) < 0) {
                    return 'Введите корректную цену';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _discountPriceController,
                decoration: const InputDecoration(
                  labelText: 'Цена со скидкой',
                  hintText: '0.00 (необязательно)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      decoration: const InputDecoration(
                        labelText: 'Штрихкод',
                        hintText: '(необязательно)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      onPressed: () {
                        _barcodeController.text = generateBarcode();
                        _refreshBarcodePreview();
                      },
                      child: const Text('Сгенерировать'),
                    ),
                  ),
                ],
              ),
              if (_barcodePreviewBytes != null) ...[
                const SizedBox(height: 12),
                const Text('Превью штрихкода', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 4),
                Image.memory(
                  _barcodePreviewBytes!,
                  height: 56,
                  fit: BoxFit.contain,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'Состав сета',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить товар'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.muted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.muted.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Text(
                      'Нет товаров в сете',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                )
              else
                ..._items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(item.productName),
                      subtitle: Text(
                        '× ${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2)}',
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle_outline, color: AppColors.danger),
                        onPressed: () => _removeItem(i),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 24),
              ExpansionTile(
                title: const Text('Конструктор этикетки', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('По умолчанию — макет из настроек'),
                initiallyExpanded: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _labelDescriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Описание для этикетки',
                        hintText: 'Текст для блока «Описание» на этикетке (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  LabelStyleControls(
                    style: _labelStyle,
                    onChanged: (s) => setState(() => _labelStyle = s),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: _labelWidthMm.toStringAsFixed(0),
                            decoration: const InputDecoration(
                              labelText: 'Ширина (мм)',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final n = double.tryParse(v);
                              if (n != null && n >= _minLabelSizeMm && n <= _maxLabelSizeMm) {
                                setState(() => _labelWidthMm = n);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: _labelHeightMm.toStringAsFixed(0),
                            decoration: const InputDecoration(
                              labelText: 'Высота (мм)',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final n = double.tryParse(v);
                              if (n != null && n >= _minLabelSizeMm && n <= _maxLabelSizeMm) {
                                setState(() => _labelHeightMm = n);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_labelBlockLayout.any((b) => b.type == LabelBlockType.description))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _labelBlockLayout = [
                              ..._labelBlockLayout,
                              const LabelBlockLayout(type: LabelBlockType.description, x: 0.05, y: 0.55),
                            ];
                          });
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Добавить блок: Описание'),
                      ),
                    ),
                  LabelCanvas(
                    product: _currentSetForLabel,
                    blockLayout: _labelBlockLayout,
                    widthMm: _labelWidthMm,
                    heightMm: _labelHeightMm,
                    style: _labelStyle,
                    onLayoutChanged: (layout) =>
                        setState(() => _labelBlockLayout = layout),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _isSavingLabel ? null : _saveLabelJpg,
                        icon: _isSavingLabel
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.image),
                        label: Text(_isSavingLabel ? 'Сохранение…' : 'Сохранить JPG'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _isPrintingLabel ? null : _printLabel,
                        icon: _isPrintingLabel
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print),
                        label: Text(_isPrintingLabel ? 'Печать…' : 'Печать'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              ExpansionTile(
                title: const Text('Конструктор ценника', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('По умолчанию — макет из настроек'),
                initiallyExpanded: false,
                children: [
                  LabelStyleControls(
                    style: _priceTagStyle,
                    onChanged: (s) => setState(() => _priceTagStyle = s),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: _priceTagWidthMm.toStringAsFixed(0),
                            decoration: const InputDecoration(
                              labelText: 'Ширина (мм)',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final n = double.tryParse(v);
                              if (n != null && n >= _minLabelSizeMm && n <= _maxLabelSizeMm) {
                                setState(() => _priceTagWidthMm = n);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: _priceTagHeightMm.toStringAsFixed(0),
                            decoration: const InputDecoration(
                              labelText: 'Высота (мм)',
                              isDense: true,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final n = double.tryParse(v);
                              if (n != null && n >= _minLabelSizeMm && n <= _maxLabelSizeMm) {
                                setState(() => _priceTagHeightMm = n);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  LabelCanvas(
                    product: _currentSetForLabel,
                    blockLayout: _priceTagBlockLayout,
                    widthMm: _priceTagWidthMm,
                    heightMm: _priceTagHeightMm,
                    style: _priceTagStyle,
                    onLayoutChanged: (layout) =>
                        setState(() => _priceTagBlockLayout = layout),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _isSavingPriceTag ? null : _savePriceTagJpg,
                        icon: _isSavingPriceTag
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.image),
                        label: Text(_isSavingPriceTag ? 'Сохранение…' : 'Сохранить JPG'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _isPrintingPriceTag ? null : _printPriceTag,
                        icon: _isPrintingPriceTag
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print),
                        label: Text(_isPrintingPriceTag ? 'Печать…' : 'Печать'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Сохранить'),
              ),
              if (widget.mode == SetFormMode.edit) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _isSaving ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  child: const Text('Удалить'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
