import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/storage.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/label_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../utils/toast.dart';
import '../widgets/label_canvas.dart';
import '../widgets/label_style_controls.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.storage,
    required this.apiService,
  });

  final Storage storage;
  final ApiService apiService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _printers = [];
  String? _selectedPrinterName;
  String _printMode = 'raw';
  String _rawEncoding = 'cp866_17';
  bool _rawXprinterPreamble = false;
  bool _isLoading = true;
  String? _error;
  String? _errorDetail;

  final _entrepreneurNameController = TextEditingController();
  final _entrepreneurBinController = TextEditingController();
  final _entrepreneurManagerController = TextEditingController();
  final _entrepreneurAddressController = TextEditingController();

  LabelTemplate _labelTemplate = LabelTemplate.defaultLabel();
  LabelTemplate _priceTagTemplate = LabelTemplate.defaultPriceTag();
  Product? _previewProduct;
  static const double _minSizeMm = 10;
  static const double _maxSizeMm = 200;


  @override
  void initState() {
    super.initState();
    _selectedPrinterName = widget.storage.receiptPrinterName;
    _printMode = widget.storage.receiptPrintMode;
    _rawEncoding = widget.storage.receiptRawEncoding;
    _rawXprinterPreamble = widget.storage.receiptRawXprinterPreamble;
    _entrepreneurNameController.text = widget.storage.entrepreneurName ?? '';
    _entrepreneurBinController.text = widget.storage.entrepreneurBin ?? '';
    _entrepreneurManagerController.text =
        widget.storage.entrepreneurManager ?? '';
    _entrepreneurAddressController.text =
        widget.storage.entrepreneurAddress ?? '';
    _loadTemplates();
    _loadPreviewProduct();
    _loadPrinters();
  }

  @override
  void dispose() {
    _entrepreneurNameController.dispose();
    _entrepreneurBinController.dispose();
    _entrepreneurManagerController.dispose();
    _entrepreneurAddressController.dispose();
    super.dispose();
  }

  void _loadTemplates() {
    final labelJson = widget.storage.labelTemplateJson;
    final priceTagJson = widget.storage.priceTagTemplateJson;
    setState(() {
      _labelTemplate = LabelTemplate.fromJson(labelJson);
      _priceTagTemplate = LabelTemplate.fromJson(priceTagJson);
    });
  }

  Future<void> _loadPreviewProduct() async {
    try {
      final products = await widget.apiService.getProducts();
      if (mounted && products.isNotEmpty) {
        setState(() => _previewProduct = products.first);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _previewProduct = Product(
            id: 0,
            name: 'Пример товара',
            slug: 'primer',
            barcode: '4601234567890',
            price: 99.99,
            unit: 'pcs',
          ),
        );
      }
    }
  }

  Future<void> _loadPrinters() async {
    if (!Platform.isWindows) {
      setState(() {
        _isLoading = false;
        _error = 'Выбор принтера доступен только на Windows';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await ReceiptPrinterService.getAvailablePrinters();
      if (!mounted) return;
      setState(() {
        _printers = list;
        if (_selectedPrinterName != null &&
            !list.contains(_selectedPrinterName)) {
          _selectedPrinterName = list.isNotEmpty ? list.first : null;
        } else if (_selectedPrinterName == null && list.isNotEmpty) {
          _selectedPrinterName = list.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Не удалось получить список принтеров. '
            'Убедитесь, что в Windows установлены принтеры (Параметры → Устройства → Принтеры). '
            'Чек можно сохранить в PDF с экрана продажи (кнопка «Сохранить в PDF»).';
        _errorDetail = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _savePrinter(String? name) async {
    await widget.storage.setReceiptPrinterName(name);
    setState(() => _selectedPrinterName = name);
    if (mounted) {
      showToast(context, 'Принтер для чеков сохранён');
    }
  }

  Future<void> _savePrintMode(String mode) async {
    await widget.storage.setReceiptPrintMode(mode);
    setState(() => _printMode = mode);
    if (mounted) {
      showToast(
        context,
        mode == 'pdf'
            ? 'Установлена обычная печать (PDF с диалогом)'
            : mode == 'pdf_direct'
            ? 'Установлена прямая печать PDF (без диалога)'
            : 'Установлена RAW печать',
      );
    }
  }

  Future<void> _saveRawEncoding(String encoding) async {
    await widget.storage.setReceiptRawEncoding(encoding);
    setState(() => _rawEncoding = encoding);
    if (mounted) {
      showToast(context, 'Кодировка RAW-чека сохранена');
    }
  }

  Future<void> _saveRawXprinterPreamble(bool value) async {
    await widget.storage.setReceiptRawXprinterPreamble(value);
    setState(() => _rawXprinterPreamble = value);
    if (mounted) {
      showToast(
        context,
        value ? 'Преамбула Xprinter включена' : 'Преамбула Xprinter выключена',
      );
    }
  }

  /// Печатает тестовый чек на текущий выбранный RAW-принтер с текущими
  /// настройками кодировки/преамбулы (даже если они ещё не сохранены).
  Future<void> _testRawPrint() async {
    final printerName = _selectedPrinterName;
    if (printerName == null || printerName.isEmpty) {
      if (mounted) {
        showToast(context, 'Сначала выберите принтер');
      }
      return;
    }
    try {
      await ReceiptPrinterService.printTest(
        printerName: printerName,
        rawEncoding: _rawEncoding,
        xprinterCyrillicPreamble: _rawXprinterPreamble,
      );
      if (mounted) {
        showToast(context, 'Тест отправлен на «$printerName»');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Ошибка тест-печати: $e');
      }
    }
  }

  Future<void> _saveEntrepreneur() async {
    await widget.storage.setEntrepreneurName(
      _entrepreneurNameController.text.trim().isEmpty
          ? null
          : _entrepreneurNameController.text.trim(),
    );
    await widget.storage.setEntrepreneurBin(
      _entrepreneurBinController.text.trim().isEmpty
          ? null
          : _entrepreneurBinController.text.trim(),
    );
    await widget.storage.setEntrepreneurManager(
      _entrepreneurManagerController.text.trim().isEmpty
          ? null
          : _entrepreneurManagerController.text.trim(),
    );
    await widget.storage.setEntrepreneurAddress(
      _entrepreneurAddressController.text.trim().isEmpty
          ? null
          : _entrepreneurAddressController.text.trim(),
    );
    if (mounted) {
      showToast(context, 'Данные предпринимателя сохранены');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Настройки',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Печать чеков',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _printMode,
                    decoration: const InputDecoration(
                      labelText: 'Тип печати',
                      border: OutlineInputBorder(),
                      helperText: ' ',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'raw',
                        child: Text('RAW (термопринтер)'),
                      ),
                      DropdownMenuItem(
                        value: 'pdf',
                        child: Text('PDF (с диалогом)'),
                      ),
                      DropdownMenuItem(
                        value: 'pdf_direct',
                        child: Text('PDF Direct (без диалога)'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) _savePrintMode(v);
                    },
                  ),
                  if (_printMode == 'raw') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _rawEncoding,
                      decoration: const InputDecoration(
                        labelText: 'Кодировка принтера (RAW)',
                        border: OutlineInputBorder(),
                        helperText: ' ',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'cp866_17',
                          child: Text('CP866, код. стр. 17 — стандарт'),
                        ),
                        DropdownMenuItem(
                          value: 'cp1251_22',
                          child: Text('Windows-1251, код. стр. 22'),
                        ),
                        DropdownMenuItem(
                          value: 'cp866_25',
                          child: Text('CP866, код. стр. 25'),
                        ),
                        DropdownMenuItem(
                          value: 'cp1251_16',
                          child: Text('Windows-1251, код. стр. 16'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) _saveRawEncoding(v);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Xprinter'),
                      subtitle: const Text(
                        'Для термопринтеров Xprinter и аналогов: если RAW даёт «китайские» символы при русском тексте, включите.',
                      ),
                      value: _rawXprinterPreamble,
                      onChanged: _saveRawXprinterPreamble,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                    if (_errorDetail != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _errorDetail!,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  if ((_printMode == 'raw' || _printMode == 'pdf_direct') &&
                      !Platform.isWindows)
                    Text(
                      'RAW и PDF Direct печать доступны только на Windows. Используйте PDF печать с диалогом.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    )
                  else if (_printMode == 'raw' && _isLoading)
                    const SizedBox(
                      height: 48,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_printMode == 'raw') ...[
                    DropdownButtonFormField<String>(
                      value: _printers.contains(_selectedPrinterName)
                          ? _selectedPrinterName
                          : (_printers.isNotEmpty ? _printers.first : null),
                      decoration: const InputDecoration(
                        labelText: 'Принтер для чеков (80мм)',
                        border: OutlineInputBorder(),
                        helperText: 'Выбор принтера требуется для RAW печати',
                      ),
                      items: _printers
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => _savePrinter(v),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _printers.isEmpty ? null : _testRawPrint,
                        icon: const Icon(Icons.print, size: 18),
                        label: const Text('Тест печати'),
                      ),
                    ),
                  ]
                  else if (_printMode == 'pdf_direct')
                    DropdownButtonFormField<String>(
                      value: _printers.contains(_selectedPrinterName)
                          ? _selectedPrinterName
                          : (_printers.isNotEmpty ? _printers.first : null),
                      decoration: const InputDecoration(
                        labelText: 'Принтер для печати',
                        border: OutlineInputBorder(),
                        helperText: ' ',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('(Принтер по умолчанию)'),
                        ),
                        ..._printers
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                      ],
                      onChanged: (v) => _savePrinter(v),
                    )
                  else
                    Text(
                      ' ',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Данные предпринимателя',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _entrepreneurNameController,
                    decoration: const InputDecoration(
                      labelText: 'Название ИП',
                      border: OutlineInputBorder(),
                      hintText: 'Индивидуальный предприниматель «Название»',
                    ),
                    onFieldSubmitted: (_) => _saveEntrepreneur(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _entrepreneurBinController,
                    decoration: const InputDecoration(
                      labelText: 'БИН',
                      border: OutlineInputBorder(),
                      hintText: '12 цифр',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    onFieldSubmitted: (_) => _saveEntrepreneur(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _entrepreneurManagerController,
                    decoration: const InputDecoration(
                      labelText: 'Руководитель',
                      border: OutlineInputBorder(),
                      hintText: 'Ф.И.О. руководителя',
                    ),
                    onFieldSubmitted: (_) => _saveEntrepreneur(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _entrepreneurAddressController,
                    decoration: const InputDecoration(
                      labelText: 'Адрес',
                      border: OutlineInputBorder(),
                      hintText: 'Юридический адрес или адрес деятельности',
                    ),
                    maxLines: 2,
                    onFieldSubmitted: (_) => _saveEntrepreneur(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saveEntrepreneur,
                    child: const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Этикетки и ценники',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ExpansionTile(
                    title: const Text('Конструктор этикеток'),
                    subtitle: const Text('Базовый макет по умолчанию'),
                    children: [
                      LabelStyleControls(
                        style: _labelTemplate.style,
                        onChanged: (s) => setState(
                          () => _labelTemplate = LabelTemplate(
                            blockLayout: _labelTemplate.blockLayout,
                            style: s,
                            widthMm: _labelTemplate.widthMm,
                            heightMm: _labelTemplate.heightMm,
                          ),
                        ),
                        blockLayout: _labelTemplate.blockLayout,
                        onLayoutChanged: (layout) => setState(
                          () => _labelTemplate = LabelTemplate(
                            blockLayout: layout,
                            style: _labelTemplate.style,
                            widthMm: _labelTemplate.widthMm,
                            heightMm: _labelTemplate.heightMm,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                initialValue: _labelTemplate.widthMm
                                    .toStringAsFixed(0),
                                decoration: const InputDecoration(
                                  labelText: 'Ширина (мм)',
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final n = double.tryParse(v);
                                  if (n != null &&
                                      n >= _minSizeMm &&
                                      n <= _maxSizeMm) {
                                    setState(
                                      () => _labelTemplate = LabelTemplate(
                                        blockLayout: _labelTemplate.blockLayout,
                                        style: _labelTemplate.style,
                                        widthMm: n,
                                        heightMm: _labelTemplate.heightMm,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                initialValue: _labelTemplate.heightMm
                                    .toStringAsFixed(0),
                                decoration: const InputDecoration(
                                  labelText: 'Высота (мм)',
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final n = double.tryParse(v);
                                  if (n != null &&
                                      n >= _minSizeMm &&
                                      n <= _maxSizeMm) {
                                    setState(
                                      () => _labelTemplate = LabelTemplate(
                                        blockLayout: _labelTemplate.blockLayout,
                                        style: _labelTemplate.style,
                                        widthMm: _labelTemplate.widthMm,
                                        heightMm: n,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_labelTemplate.blockLayout.any(
                        (b) => b.type == LabelBlockType.description,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _labelTemplate = LabelTemplate(
                                  blockLayout: [
                                    ..._labelTemplate.blockLayout,
                                    const LabelBlockLayout(
                                      type: LabelBlockType.description,
                                      x: 0.05,
                                      y: 0.55,
                                    ),
                                  ],
                                  style: _labelTemplate.style,
                                  widthMm: _labelTemplate.widthMm,
                                  heightMm: _labelTemplate.heightMm,
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Добавить блок: Описание'),
                          ),
                        ),
                      LabelCanvas(
                        product: _previewProduct,
                        blockLayout: _labelTemplate.blockLayout,
                        widthMm: _labelTemplate.widthMm,
                        heightMm: _labelTemplate.heightMm,
                        style: _labelTemplate.style,
                        onLayoutChanged: (layout) => setState(
                          () => _labelTemplate = LabelTemplate(
                            blockLayout: layout,
                            style: _labelTemplate.style,
                            widthMm: _labelTemplate.widthMm,
                            heightMm: _labelTemplate.heightMm,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () async {
                          await widget.storage.setLabelTemplateJson(
                            _labelTemplate.toJson(),
                          );
                          if (mounted) {
                            showToast(context, 'Макет этикеток сохранён');
                          }
                        },
                        child: const Text('Сохранить как макет по умолчанию'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  ExpansionTile(
                    title: const Text('Конструктор ценников'),
                    subtitle: const Text('Базовый макет по умолчанию'),
                    children: [
                      LabelStyleControls(
                        style: _priceTagTemplate.style,
                        onChanged: (s) => setState(
                          () => _priceTagTemplate = LabelTemplate(
                            blockLayout: _priceTagTemplate.blockLayout,
                            style: s,
                            widthMm: _priceTagTemplate.widthMm,
                            heightMm: _priceTagTemplate.heightMm,
                          ),
                        ),
                        blockLayout: _priceTagTemplate.blockLayout,
                        onLayoutChanged: (layout) => setState(
                          () => _priceTagTemplate = LabelTemplate(
                            blockLayout: layout,
                            style: _priceTagTemplate.style,
                            widthMm: _priceTagTemplate.widthMm,
                            heightMm: _priceTagTemplate.heightMm,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                initialValue: _priceTagTemplate.widthMm
                                    .toStringAsFixed(0),
                                decoration: const InputDecoration(
                                  labelText: 'Ширина (мм)',
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final n = double.tryParse(v);
                                  if (n != null &&
                                      n >= _minSizeMm &&
                                      n <= _maxSizeMm) {
                                    setState(
                                      () => _priceTagTemplate = LabelTemplate(
                                        blockLayout:
                                            _priceTagTemplate.blockLayout,
                                        style: _priceTagTemplate.style,
                                        widthMm: n,
                                        heightMm: _priceTagTemplate.heightMm,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                initialValue: _priceTagTemplate.heightMm
                                    .toStringAsFixed(0),
                                decoration: const InputDecoration(
                                  labelText: 'Высота (мм)',
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final n = double.tryParse(v);
                                  if (n != null &&
                                      n >= _minSizeMm &&
                                      n <= _maxSizeMm) {
                                    setState(
                                      () => _priceTagTemplate = LabelTemplate(
                                        blockLayout:
                                            _priceTagTemplate.blockLayout,
                                        style: _priceTagTemplate.style,
                                        widthMm: _priceTagTemplate.widthMm,
                                        heightMm: n,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_priceTagTemplate.blockLayout.any(
                        (b) => b.type == LabelBlockType.description,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _priceTagTemplate = LabelTemplate(
                                  blockLayout: [
                                    ..._priceTagTemplate.blockLayout,
                                    const LabelBlockLayout(
                                      type: LabelBlockType.description,
                                      x: 0.05,
                                      y: 0.55,
                                    ),
                                  ],
                                  style: _priceTagTemplate.style,
                                  widthMm: _priceTagTemplate.widthMm,
                                  heightMm: _priceTagTemplate.heightMm,
                                );
                              });
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Добавить блок: Описание'),
                          ),
                        ),
                      LabelCanvas(
                        product: _previewProduct,
                        blockLayout: _priceTagTemplate.blockLayout,
                        widthMm: _priceTagTemplate.widthMm,
                        heightMm: _priceTagTemplate.heightMm,
                        style: _priceTagTemplate.style,
                        onLayoutChanged: (layout) => setState(
                          () => _priceTagTemplate = LabelTemplate(
                            blockLayout: layout,
                            style: _priceTagTemplate.style,
                            widthMm: _priceTagTemplate.widthMm,
                            heightMm: _priceTagTemplate.heightMm,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () async {
                          await widget.storage.setPriceTagTemplateJson(
                            _priceTagTemplate.toJson(),
                          );
                          if (mounted) {
                            showToast(context, 'Макет ценников сохранён');
                          }
                        },
                        child: const Text('Сохранить как макет по умолчанию'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
