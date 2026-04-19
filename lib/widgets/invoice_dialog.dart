import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/counterparty.dart';
import '../services/api_service.dart';
import '../services/invoice_pdf_service.dart';
import '../utils/toast.dart';

/// Модальное окно для заполнения данных накладной и генерации PDF.
/// [items] — позиции из корзины кассы или из продажи.
/// [initialDocumentNumber] — начальный номер документа (опционально).
/// [storage] — при наличии подставляются данные предпринимателя из настроек (название ИП, БИН, руководитель, адрес).
void showInvoiceDialog({
  required BuildContext context,
  required ApiService apiService,
  required List<CartItem> items,
  String? initialDocumentNumber,
  Storage? storage,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _InvoiceDialog(
      apiService: apiService,
      items: items,
      initialDocumentNumber: initialDocumentNumber,
      storage: storage,
    ),
  );
}

class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog({
    required this.apiService,
    required this.items,
    this.initialDocumentNumber,
    this.storage,
  });

  final ApiService apiService;
  final List<CartItem> items;
  final String? initialDocumentNumber;
  final Storage? storage;

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  List<Counterparty> _counterparties = [];
  bool _loadingCounterparties = true;
  String? _counterpartyError;
  Counterparty? _selectedCounterparty;

  late TextEditingController _senderNameController;
  late TextEditingController _senderIinController;
  late TextEditingController _documentNumberController;
  late TextEditingController _receiverNameController;
  late TextEditingController _receiverIinController;
  late TextEditingController _receiverAddressController;
  late TextEditingController _responsibleController;
  late TextEditingController _transportController;
  late TextEditingController _ttnNumberController;
  late TextEditingController _ttnDateController;
  late TextEditingController _approvedByController;
  late TextEditingController _warrantNumberController;
  late TextEditingController _warrantIssuedByController;
  late TextEditingController _chiefAccountantController;
  late TextEditingController _releasedByController;

  DateTime _documentDate = DateTime.now();
  bool _isGenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final st = widget.storage;
    final senderName = st != null && (st.entrepreneurName != null)
        ? [
            if (st.entrepreneurName != null && st.entrepreneurName!.isNotEmpty)
              st.entrepreneurName!,
          ].join(', ')
        : '';
    _senderNameController = TextEditingController(text: senderName);
    _senderIinController = TextEditingController(
      text: st?.entrepreneurBin ?? '',
    );
    _documentNumberController = TextEditingController(
      text: widget.initialDocumentNumber ?? '',
    );
    _receiverNameController = TextEditingController(text: '');
    _receiverIinController = TextEditingController(text: '');
    _receiverAddressController = TextEditingController(text: '');
    _responsibleController = TextEditingController(text: '');
    _transportController = TextEditingController(text: '');
    _ttnNumberController = TextEditingController(text: '');
    _ttnDateController = TextEditingController(text: '');
    _approvedByController = TextEditingController(
      text: st?.entrepreneurManager ?? '',
    );
    _warrantNumberController = TextEditingController(text: '');
    _warrantIssuedByController = TextEditingController(text: '');
    _chiefAccountantController = TextEditingController(text: 'не предусмотрен');
    _releasedByController = TextEditingController(
      text: st?.entrepreneurManager ?? '',
    );
    _loadCounterparties();
  }

  Future<void> _loadCounterparties() async {
    setState(() {
      _loadingCounterparties = true;
      _counterpartyError = null;
    });
    try {
      final list = await widget.apiService.getCounterparties();
      if (!mounted) return;
      setState(() {
        _counterparties = list;
        _loadingCounterparties = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _counterpartyError = 'Не удалось загрузить покупателей';
        _loadingCounterparties = false;
      });
    }
  }

  void _onCounterpartySelected(Counterparty? c) {
    setState(() {
      _selectedCounterparty = c;
      if (c != null) {
        _receiverNameController.text = c.name;
        _receiverIinController.text = c.iin ?? '';
        _receiverAddressController.text = c.address ?? '';
      }
    });
  }

  @override
  void dispose() {
    _senderNameController.dispose();
    _senderIinController.dispose();
    _documentNumberController.dispose();
    _receiverNameController.dispose();
    _receiverIinController.dispose();
    _receiverAddressController.dispose();
    _responsibleController.dispose();
    _transportController.dispose();
    _ttnNumberController.dispose();
    _ttnDateController.dispose();
    _approvedByController.dispose();
    _warrantNumberController.dispose();
    _warrantIssuedByController.dispose();
    _chiefAccountantController.dispose();
    _releasedByController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _documentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() => _documentDate = picked);
    }
  }

  Future<void> _generateAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final invoiceData = InvoiceData(
        senderName: _senderNameController.text.trim(),
        senderIinBin: _senderIinController.text.trim(),
        documentNumber: _documentNumberController.text.trim(),
        documentDate: _documentDate,
        receiverName: _receiverNameController.text.trim(),
        receiverIin: _receiverIinController.text.trim().isEmpty
            ? null
            : _receiverIinController.text.trim(),
        receiverAddress: _receiverAddressController.text.trim().isEmpty
            ? null
            : _receiverAddressController.text.trim(),
        responsiblePerson: _responsibleController.text.trim().isEmpty
            ? null
            : _responsibleController.text.trim(),
        transportOrg: _transportController.text.trim().isEmpty
            ? null
            : _transportController.text.trim(),
        ttnNumber: _ttnNumberController.text.trim().isEmpty
            ? null
            : _ttnNumberController.text.trim(),
        ttnDate: _ttnDateController.text.trim().isEmpty
            ? null
            : _ttnDateController.text.trim(),
        approvedBy: _approvedByController.text.trim().isEmpty
            ? null
            : _approvedByController.text.trim(),
        warrantNumber: _warrantNumberController.text.trim().isEmpty
            ? null
            : _warrantNumberController.text.trim(),
        warrantIssuedBy: _warrantIssuedByController.text.trim().isEmpty
            ? null
            : _warrantIssuedByController.text.trim(),
        chiefAccountant: _chiefAccountantController.text.trim().isEmpty
            ? null
            : _chiefAccountantController.text.trim(),
        releasedBy: _releasedByController.text.trim().isEmpty
            ? null
            : _releasedByController.text.trim(),
        items: widget.items
            .map((e) => InvoiceLineItem.fromCartItem(e))
            .toList(),
      );
      final pdfBytes = await InvoicePdfService.buildPdf(invoiceData);
      if (!mounted) return;
      final path = await FilePicker.platform.saveFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        fileName:
            'Накладная_${invoiceData.documentNumber}_${_documentDate.day.toString().padLeft(2, '0')}-${_documentDate.month.toString().padLeft(2, '0')}-${_documentDate.year}.pdf',
      );
      if (path != null && path.isNotEmpty && mounted) {
        final savePath = path.endsWith('.pdf') ? path : '$path.pdf';
        await File(savePath).writeAsBytes(pdfBytes);
        if (mounted) {
          showToast(context, 'Накладная сохранена: $savePath');
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _error = e.toString();
        });
        showToast(context, 'Ошибка: $e');
      }
    }
    if (mounted) setState(() => _isGenerating = false);
  }

  Future<void> _printPdf() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final invoiceData = InvoiceData(
        senderName: _senderNameController.text.trim(),
        senderIinBin: _senderIinController.text.trim(),
        documentNumber: _documentNumberController.text.trim(),
        documentDate: _documentDate,
        receiverName: _receiverNameController.text.trim(),
        receiverIin: _receiverIinController.text.trim().isEmpty
            ? null
            : _receiverIinController.text.trim(),
        receiverAddress: _receiverAddressController.text.trim().isEmpty
            ? null
            : _receiverAddressController.text.trim(),
        responsiblePerson: _responsibleController.text.trim().isEmpty
            ? null
            : _responsibleController.text.trim(),
        transportOrg: _transportController.text.trim().isEmpty
            ? null
            : _transportController.text.trim(),
        ttnNumber: _ttnNumberController.text.trim().isEmpty
            ? null
            : _ttnNumberController.text.trim(),
        ttnDate: _ttnDateController.text.trim().isEmpty
            ? null
            : _ttnDateController.text.trim(),
        approvedBy: _approvedByController.text.trim().isEmpty
            ? null
            : _approvedByController.text.trim(),
        warrantNumber: _warrantNumberController.text.trim().isEmpty
            ? null
            : _warrantNumberController.text.trim(),
        warrantIssuedBy: _warrantIssuedByController.text.trim().isEmpty
            ? null
            : _warrantIssuedByController.text.trim(),
        chiefAccountant: _chiefAccountantController.text.trim().isEmpty
            ? null
            : _chiefAccountantController.text.trim(),
        releasedBy: _releasedByController.text.trim().isEmpty
            ? null
            : _releasedByController.text.trim(),
        items: widget.items
            .map((e) => InvoiceLineItem.fromCartItem(e))
            .toList(),
      );
      final pdfBytes = await InvoicePdfService.buildPdf(invoiceData);
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
      );
      if (mounted) {
        showToast(context, 'Открыт диалог печати');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        showToast(context, 'Ошибка печати: $e');
      }
    }
    if (mounted) setState(() => _isGenerating = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Накладная (форма 3-2)'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'Отправитель',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _senderNameController,
                  decoration: const InputDecoration(
                    labelText: 'Организация / ИП',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Укажите отправителя'
                      : null,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _senderIinController,
                  decoration: const InputDecoration(
                    labelText: 'ИИН / БИН',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Укажите ИИН/БИН'
                      : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _documentNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Номер документа',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Укажите номер'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Дата составления',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(
                            '${_documentDate.day.toString().padLeft(2, '0')}.${_documentDate.month.toString().padLeft(2, '0')}.${_documentDate.year}',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Получатель',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                if (_loadingCounterparties)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      height: 24,
                      child: LinearProgressIndicator(),
                    ),
                  )
                else if (_counterpartyError != null)
                  Text(
                    _counterpartyError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  )
                else
                  DropdownButtonFormField<Counterparty?>(
                    value: _selectedCounterparty,
                    decoration: const InputDecoration(
                      labelText: 'Покупатель (выберите для автозаполнения)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('— Не выбран —'),
                      ),
                      ..._counterparties.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                      ),
                    ],
                    onChanged: _onCounterpartySelected,
                  ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _receiverNameController,
                  decoration: const InputDecoration(
                    labelText: 'Наименование получателя',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Укажите получателя'
                      : null,
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _receiverIinController,
                  decoration: const InputDecoration(
                    labelText: 'ИИН / БИН получателя',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _receiverAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Адрес получателя',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Ответственный и транспорт',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _responsibleController,
                  decoration: const InputDecoration(
                    labelText: 'Ответственный за поставку (Ф.И.О.)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _transportController,
                  decoration: const InputDecoration(
                    labelText: 'Транспортная организация',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ttnNumberController,
                        decoration: const InputDecoration(
                          labelText: 'ТТН номер',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ttnDateController,
                        decoration: const InputDecoration(
                          labelText: 'ТТН дата',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Подписи',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _approvedByController,
                  decoration: const InputDecoration(
                    labelText: 'Отпуск разрешил (Ф.И.О.)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _warrantNumberController,
                        decoration: const InputDecoration(
                          labelText: 'По доверенности №',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _warrantIssuedByController,
                        decoration: const InputDecoration(
                          labelText: 'выданной',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _chiefAccountantController,
                  decoration: const InputDecoration(
                    labelText: 'Главный бухгалтер (Ф.И.О.)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _releasedByController,
                  decoration: const InputDecoration(
                    labelText: 'Отпустил (Ф.И.О.)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Позиций в накладной: ${widget.items.length}. Итого: ${widget.items.fold<double>(0, (s, e) => s + e.total).toStringAsFixed(2)} ₸',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isGenerating ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        if (Platform.isWindows)
          FilledButton.icon(
            onPressed: _isGenerating ? null : _printPdf,
            icon: _isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.print, size: 20),
            label: const Text('Печать'),
          ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _isGenerating ? null : _generateAndSave,
          icon: _isGenerating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf, size: 20),
          label: const Text('Сформировать PDF'),
        ),
      ],
    );
  }
}
