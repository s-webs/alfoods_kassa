import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/cashier.dart';
import '../models/product.dart';
import '../models/product_set.dart';
import '../models/pos_payment_record.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/shift.dart';
import '../services/api_service.dart';
import '../services/api_webkassa_exception.dart';
import '../utils/webkassa_error_display.dart';
import '../widgets/fiscal_receipt_dialog.dart';
import '../services/webkassa_receipt_print_service.dart';
import '../services/kaspi_pos_service.dart';
import '../services/pos_payment_store.dart';
import '../models/counterparty.dart';
import '../models/debt_payment.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/invoice_dialog.dart';
import '../widgets/kaspi_pos_payment_dialog.dart';
import '../widgets/pay_debt_dialog.dart';
import '../widgets/sale_detail_info_section.dart';
import '../widgets/sale_payment_chip.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../utils/time_util.dart';
import '../utils/toast.dart';

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({
    super.key,
    required this.storage,
    required this.apiService,
    required this.saleId,
  });

  final Storage storage;
  final ApiService apiService;
  final int saleId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen>
    with SingleTickerProviderStateMixin {
  late final KaspiPosService _kaspiPosService;
  late final PosPaymentStore _posPaymentStore;
  late final WebkassaReceiptPrintService _webkassaReceiptPrintService;

  Sale? _sale;
  List<SaleItem> _sourceItems = [];
  final Map<int, double> _returnDraftQty = {};
  List<CartItem> _items = [];
  bool _isReturning = false;
  List<Cashier> _cashiers = [];
  List<Shift> _shifts = [];
  Counterparty? _counterparty;
  List<DebtPayment> _debtPayments = [];
  int? _selectedCashierId;
  int? _selectedShiftId;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  int? _editingNameIndex;
  int? _editingPriceIndex;
  TextEditingController? _nameEditController;
  TextEditingController? _priceEditController;
  late final TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      animationDuration: const Duration(milliseconds: 150),
    );
    _kaspiPosService = KaspiPosService(widget.storage);
    _posPaymentStore = PosPaymentStore(widget.storage);
    _webkassaReceiptPrintService = WebkassaReceiptPrintService(widget.storage);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameEditController?.dispose();
    _priceEditController?.dispose();
    super.dispose();
  }

  static double _quantityStep(String unit) =>
      unit == 'pcs' ? 1.0 : 0.1;

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sale = await widget.apiService.getSale(widget.saleId);
      final cashiers = await widget.apiService.getCashiers();
      final shiftsPage = await widget.apiService.getShifts(perPage: 50);
      final shifts = shiftsPage.data;
      
      Counterparty? counterparty;
      List<DebtPayment> debtPayments = [];
      
      if (sale.isOnCredit && sale.counterpartyId != null) {
        try {
          counterparty = await widget.apiService.getCounterparty(sale.counterpartyId!);
          debtPayments = await widget.apiService.getDebtPayments(saleId: sale.id);
        } catch (e) {
          // Ignore errors loading counterparty/debt payments
        }
      }
      
      if (!mounted) return;

      setState(() {
        _sale = sale;
        _sourceItems = sale.items;
        _returnDraftQty.clear();
        _items = sale.items
            .map(
              (e) => CartItem(
                productId: e.productId,
                setId: e.setId,
                name: e.name,
                price: e.price,
                quantity: e.quantity,
                unit: e.unit,
              ),
            )
            .toList();
        _cashiers = cashiers;
        _shifts = shifts;
        _counterparty = counterparty;
        _debtPayments = debtPayments;
        _selectedCashierId = sale.cashierId;
        _selectedShiftId = sale.shiftId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить продажу';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_sale == null) return;
    if (_items.isEmpty) {
      showToast(context, 'Добавьте хотя бы одну позицию');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.apiService.updateSale(
        widget.saleId,
        cashierId: _selectedCashierId,
        shiftId: _selectedShiftId,
        items: _items.map((e) => e.toJson()).toList(),
      );
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось сохранить';
      });
    }
  }

  double get _itemsTotal =>
      _items.fold(0, (sum, item) => sum + item.total);

  double get _itemsTotalQty =>
      _items.fold<double>(0, (sum, item) => sum + item.quantity);

  static String _formatTotalQty(double qty) {
    final rounded = qty.roundToDouble();
    if ((qty - rounded).abs() < 1e-9) return rounded.toInt().toString();
    final s = qty.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  bool _isLineFullyReturned(int index) {
    if (index >= _sourceItems.length) return false;
    return _sourceItems[index].remainingQuantity <= 0;
  }

  bool get _isOfdSale => _sale?.isOfdSale ?? false;

  Future<void> _openWebkassaTicket({required bool printVersion}) async {
    final sale = _sale;
    if (sale == null) return;
    final url = printVersion
        ? (sale.ticketPrintUrl ?? sale.ticketUrl)
        : (sale.ticketUrl ?? sale.ticketPrintUrl);
    if (url == null || url.isEmpty) {
      showToast(context, 'Ссылка чека WebKassa недоступна');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      showToast(context, 'Некорректная ссылка WebKassa');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showToast(context, 'Не удалось открыть чек WebKassa');
    }
  }

  void _updateQuantity(int index, double delta) {
    setState(() {
      final item = _items[index];
      final step = _quantityStep(item.unit);
      item.quantity += delta * step;
      if (item.quantity <= 0) {
        _items.removeAt(index);
      }
    });
  }

  Future<void> _editQuantity(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final isPcs = item.unit == 'pcs';
    final initial = isPcs
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(2);
    final controller = TextEditingController(text: initial);
    double? parseQuantity() {
      final v = double.tryParse(
        controller.text.replaceFirst(',', '.').trim(),
      );
      if (v == null || v < 0) return null;
      if (isPcs) return v.roundToDouble();
      return v;
    }
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Количество: ${item.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: isPcs ? 'Штук' : 'Кг (0.1 = 100 г)',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final v = parseQuantity();
            if (v != null) Navigator.of(ctx).pop(v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final v = parseQuantity();
              if (v != null) Navigator.of(ctx).pop(v);
            },
            child: const Text('Ок'),
          ),
        ],
      ),
    );
    if (result != null && result > 0 && mounted) {
      setState(() => _items[index].quantity = result);
    }
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _startEditName(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      _editingNameIndex = index;
      _nameEditController?.dispose();
      _nameEditController = TextEditingController(text: _items[index].name);
    });
  }

  void _finishEditName({bool save = true}) {
    final index = _editingNameIndex;
    if (index == null || index < 0 || index >= _items.length) return;
    final controller = _nameEditController;
    if (controller != null && save) {
      final text = controller.text.trim();
      if (text.isNotEmpty) {
        setState(() => _items[index].name = text);
      }
    }
    _nameEditController?.dispose();
    _nameEditController = null;
    setState(() => _editingNameIndex = null);
  }

  void _startEditPrice(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      _editingPriceIndex = index;
      _priceEditController?.dispose();
      _priceEditController = TextEditingController(
        text: _items[index].price.toStringAsFixed(2),
      );
    });
  }

  void _finishEditPrice({bool save = true}) {
    final index = _editingPriceIndex;
    if (index == null || index < 0 || index >= _items.length) return;
    final controller = _priceEditController;
    if (controller != null && save) {
      final text = controller.text.replaceFirst(',', '.').trim();
      final value = double.tryParse(text);
      if (value != null && value >= 0) {
        setState(() => _items[index].price = value);
      }
    }
    _priceEditController?.dispose();
    _priceEditController = null;
    setState(() => _editingPriceIndex = null);
  }

  void _addProductToSale(Product product) {
    setState(() {
      final step = product.unit == 'pcs' ? 1.0 : 0.1;
      final existingIndex =
          _items.indexWhere((e) => e.productId == product.id && e.setId == null);
      if (existingIndex >= 0) {
        _items[existingIndex].quantity += step;
      } else {
        _items.add(
          CartItem(
            productId: product.id,
            name: product.name,
            price: product.effectivePrice,
            quantity: step,
            unit: product.unit,
          ),
        );
      }
    });
  }

  void _addSetToSale(ProductSet productSet) {
    setState(() {
      const step = 1.0;
      final existingIndex =
          _items.indexWhere((e) => e.setId == productSet.id);
      if (existingIndex >= 0) {
        _items[existingIndex].quantity += step;
      } else {
        _items.add(
          CartItem(
            productId: 0,
            setId: productSet.id,
            name: productSet.name,
            price: productSet.effectivePrice,
            quantity: step,
            unit: 'pcs',
          ),
        );
      }
    });
  }

  /// Добавить позицию из каталога товаров (модалка со списком, можно добавлять несколько).
  Future<void> _addItemFromCatalog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AddProductDialog(
        apiService: widget.apiService,
        onAddProduct: (p) => _addProductToSale(p),
        onAddSet: (s) => _addSetToSale(s),
      ),
    );
  }

  /// Добавить произвольный товар (снимок, которого нет в базе).
  Future<void> _addArbitraryItem() async {
    final nameController = TextEditingController(text: '');
    final priceController = TextEditingController(text: '0');
    String unit = 'pcs';
    final quantityController = TextEditingController(text: '1');
    final result = await showDialog<
        ({String name, double price, String unit, double quantity})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Добавить произвольный товар'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Название',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Цена, ₸',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(
                        labelText: 'Единица',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('шт')),
                        DropdownMenuItem(value: 'g', child: Text('г')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => unit = v ?? 'pcs'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Количество',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final price = double.tryParse(
                      priceController.text.replaceFirst(',', '.').trim(),
                    );
                    final qty = double.tryParse(
                      quantityController.text.replaceFirst(',', '.').trim(),
                    );
                    if (name.isNotEmpty &&
                        price != null &&
                        price >= 0 &&
                        qty != null &&
                        qty > 0) {
                      Navigator.of(ctx).pop((
                        name: name,
                        price: price,
                        unit: unit,
                        quantity: qty,
                      ));
                    }
                  },
                  child: const Text('Добавить'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        _items.add(
          CartItem(
            productId: 0,
            name: result.name,
            price: result.price,
            quantity: result.quantity,
            unit: result.unit,
          ),
        );
      });
    }
  }

  Future<void> _delete() async {
    if (_sale == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить продажу?'),
        content: Text(
          'Продажа #${_sale!.id} на сумму ${_itemsTotal.toStringAsFixed(2)} ₸ будет удалена.',
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
    try {
      await widget.apiService.deleteSale(widget.saleId);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить');
    }
  }

  Future<void> _payDebt() async {
    if (_sale == null || !_sale!.isOnCredit) return;

    final result = await showDialog<PayDebtResult>(
      context: context,
      builder: (ctx) => PayDebtDialog(
        remainingDebt: _sale!.remainingDebt,
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await widget.apiService.payDebt(
        widget.saleId,
        amount: result.amount,
        paymentDate: result.paymentDate,
        notes: result.notes,
      );

      if (!mounted) return;

      // Reload to get updated sale and debt payments
      await _load();

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        showToast(context, 'Оплата на сумму ${result.amount.toStringAsFixed(2)} ₸ зарегистрирована');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Не удалось зарегистрировать оплату';
      });
    }
  }

  PosPaymentRecord? _resolvePosRecord() {
    final fromApi = _sale?.posTransaction;
    if (fromApi != null &&
        fromApi.transactionId.isNotEmpty &&
        fromApi.method.isNotEmpty) {
      return PosPaymentRecord(
        method: fromApi.method,
        transactionId: fromApi.transactionId,
        amount: fromApi.amount.round(),
        processId: fromApi.processId ?? '',
        paidAt: DateTime.now(),
      );
    }
    return _posPaymentStore.get(widget.saleId);
  }

  List<Map<String, dynamic>>? _buildReturnItemsPayload({required bool fullReturn}) {
    if (_sale == null) return null;

    if (fullReturn) {
      return null;
    }

    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < _sourceItems.length; i++) {
      final qty = _returnDraftQty[i] ?? 0;
      if (qty <= 0) continue;
      final line = _sourceItems[i];
      payload.add({
        ...line.toJson(),
        'quantity': qty,
      });
    }

    return payload.isEmpty ? [] : payload;
  }

  Future<void> _returnSale({required bool fullReturn}) async {
    if (_sale == null) return;

    final itemsPayload = _buildReturnItemsPayload(fullReturn: fullReturn);
    if (!fullReturn && (itemsPayload == null || itemsPayload.isEmpty)) {
      showToast(context, 'Выберите позиции для возврата');
      return;
    }

    var returnSum = 0.0;
    for (var i = 0; i < _sourceItems.length; i++) {
      final line = _sourceItems[i];
      final qty = fullReturn
          ? line.remainingQuantity
          : (_returnDraftQty[i] ?? 0);
      returnSum += line.price * qty;
    }

    final posRecord = _resolvePosRecord();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fullReturn ? 'Полный возврат?' : 'Частичный возврат?'),
        content: Text(
          posRecord != null && fullReturn
              ? 'Сначала возврат на терминале Kaspi (${posRecord.amount} ₸), '
                  'затем оформление возврата (${returnSum.toStringAsFixed(2)} ₸).'
              : fullReturn
                  ? 'Вернуть все оставшиеся позиции (${returnSum.toStringAsFixed(2)} ₸)?'
                  : 'Вернуть выбранные позиции на сумму ${returnSum.toStringAsFixed(2)} ₸?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('Оформить возврат'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _isReturning = true;
      _error = null;
    });

    if (posRecord != null && fullReturn) {
      if (!widget.storage.isPosConfigured) {
        if (mounted) {
          setState(() => _isReturning = false);
          showToast(
            context,
            'Настройте Kaspi POS в настройках для возврата на терминале',
          );
        }
        return;
      }
      try {
        final start = await _kaspiPosService.startRefund(
          amount: posRecord.amount,
          method: posRecord.method,
          transactionId: posRecord.transactionId,
        );
        if (!mounted) return;

        final result = await KaspiPosPaymentDialog.show(
          context: context,
          amount: posRecord.amount,
          processId: start.processId,
          title: 'Возврат на терминале',
          poll: (processId, onUpdate) => _kaspiPosService.pollUntilFinished(
            processId,
            onUpdate: onUpdate,
          ),
          actualize: _kaspiPosService.actualize,
        );

        if (!mounted) return;
        if (result == null || result.status != 'success') {
          final msg = result?.message ?? 'Возврат на терминале не выполнен';
          if (mounted) {
            setState(() => _isReturning = false);
            showToast(context, msg);
          }
          return;
        }
      } on KaspiPosException catch (e) {
        if (mounted) {
          setState(() => _isReturning = false);
          showToast(context, e.message);
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() => _isReturning = false);
          showToast(context, 'Ошибка POS: $e');
        }
        return;
      }
    }

    try {
      final result = await widget.apiService.returnSale(
        widget.saleId,
        items: itemsPayload,
      );
      if (fullReturn) {
        await _posPaymentStore.remove(widget.saleId);
      }
      if (!mounted) return;

      if (result.fiscal != null) {
        try {
          final printed = await _webkassaReceiptPrintService.printFiscalReceipt(
            result.fiscal,
          );
          if (mounted && printed) {
            showToast(context, 'Чек возврата напечатан');
          }
        } catch (_) {
          if (mounted) {
            showToast(context, 'Возврат оформлен, печать чека не удалась');
          }
        }
      } else if (mounted) {
        showToast(context, 'Возврат оформлен');
      }

      if (mounted) context.pop(true);
    } on ApiWebkassaException catch (e) {
      if (!mounted) return;
      setState(() => _error = formatWebkassaError(e));
      final hint = webkassaErrorHint(e.webkassaCode);
      if (hint != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hint)));
      }
      if (e.fiscal != null) {
        await FiscalReceiptDialog.show(context, fiscal: e.fiscal!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось оформить возврат');
    } finally {
      if (mounted) setState(() => _isReturning = false);
    }
  }

  Widget _buildReturningOverlay() {
    final ofd = _isOfdSale;
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      ofd ? 'Оформление возврата ОФД...' : 'Оформление возврата...',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ofd
                          ? 'Фискализация в WebKassa. Дождитесь завершения.'
                          : 'Дождитесь завершения операции',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printReceipt() async {
    if (_isOfdSale) {
      await _openWebkassaTicket(printVersion: true);
      return;
    }
    final printMode = widget.storage.receiptPrintMode;
    if (printMode != 'pdf' && !Platform.isWindows) {
      showToast(context, 'Печать чека доступна только на Windows');
      return;
    }
    if (_items.isEmpty) {
      showToast(context, 'Нет позиций для печати');
      return;
    }
    final cashiersMatch = _cashiers.where((c) => c.id == _selectedCashierId).toList();
    final cashierName = cashiersMatch.isNotEmpty ? cashiersMatch.first.name : '—';
    try {
      final dateTime =
          TimeUtil.toUtcPlus5Wall(_sale?.createdAt ?? DateTime.now());
      final totalQty = _itemsTotalQty;
      final bytes = printMode == 'raw'
          ? ReceiptPrinterService.buildReceipt(
              saleId: widget.saleId,
              cashierName: cashierName,
              items: _items,
              total: _itemsTotal,
              totalQty: totalQty,
              dateTime: dateTime,
              rawEncoding: widget.storage.receiptRawEncoding,
              xprinterCyrillicPreamble:
                  widget.storage.receiptRawXprinterPreamble,
            )
          : <int>[];
      await ReceiptPrinterService.printReceipt(
        printerName: widget.storage.receiptPrinterName,
        bytes: bytes,
        printMode: printMode,
        saleId: widget.saleId,
        cashierName: cashierName,
        items: _items,
        total: _itemsTotal,
        totalQty: totalQty,
        dateTime: dateTime,
      );
      if (!mounted) return;
      showToast(
        context,
        printMode == 'pdf'
            ? 'Открыт диалог печати'
            : printMode == 'pdf_direct'
                ? 'PDF отправлен на печать'
                : printMode == 'native'
                    ? 'Чек отправлен на печать (Windows)'
                    : 'Чек отправлен на печать',
      );
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Ошибка печати: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _saveReceiptPdf() async {
    if (_isOfdSale) {
      await _openWebkassaTicket(printVersion: true);
      if (mounted) {
        showToast(context, 'Открылся чек WebKassa: сохраните как PDF из браузера');
      }
      return;
    }
    if (_items.isEmpty) {
      showToast(context, 'Нет позиций для сохранения');
      return;
    }
    final cashiersMatch = _cashiers.where((c) => c.id == _selectedCashierId).toList();
    final cashierName = cashiersMatch.isNotEmpty ? cashiersMatch.first.name : '—';
    try {
      final totalQty = _itemsTotalQty;
      final dateTime =
          TimeUtil.toUtcPlus5Wall(_sale?.createdAt ?? DateTime.now());
      final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
        saleId: widget.saleId,
        cashierName: cashierName,
        items: _items,
        total: _itemsTotal,
        totalQty: totalQty,
        dateTime: dateTime,
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить чек в PDF',
        fileName: 'chek-${widget.saleId}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        final savePath = path.endsWith('.pdf') ? path : '$path.pdf';
        await File(savePath).writeAsBytes(pdfBytes);
        if (!mounted) return;
        showToast(context, 'Чек сохранён: $savePath');
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Ошибка: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Продажа'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _sale == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Продажа'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
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

    final sale = _sale!;
    final isReturned = sale.isReturned;
    final isReturnRecord = sale.isReturnRecord;
    final isOfdSale = _isOfdSale;
    final canEditOrder = !isReturned && !isReturnRecord && !isOfdSale;
    final canReturn = sale.canAcceptReturns && !_isReturning;
    final isScreenBusy = _isReturning || _isSaving;
    final hasMenuActions =
        (!isReturned && _items.isNotEmpty) || canReturn || canEditOrder;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('Продажа #${sale.id}'),
            if (isReturned) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Возврат', style: TextStyle(fontSize: 12)),
              ),
            ],
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isScreenBusy ? null : () => context.pop(),
        ),
        actions: [
          if (canEditOrder)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Добавить позицию',
              onPressed: isScreenBusy ? null : _addItemFromCatalog,
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: isOfdSale ? 'Чек WebKassa (PDF)' : 'Сохранить в PDF',
            onPressed: _items.isEmpty || isScreenBusy ? null : _saveReceiptPdf,
          ),
          if (canEditOrder)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Сохранить',
              onPressed: isScreenBusy ? null : _save,
            ),
          if (Platform.isWindows || isOfdSale)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: isOfdSale ? 'Печать чека WebKassa' : 'Печать чека',
              onPressed: _items.isEmpty || isScreenBusy ? null : _printReceipt,
            ),
          if (hasMenuActions)
            PopupMenuButton<String>(
              tooltip: 'Действия',
              enabled: !isScreenBusy,
              onSelected: (value) async {
                if (isScreenBusy) return;
                switch (value) {
                  case 'invoice':
                    showInvoiceDialog(
                      context: context,
                      apiService: widget.apiService,
                      items: List.from(_items),
                      initialDocumentNumber: '${sale.id}',
                      storage: widget.storage,
                    );
                    break;
                  case 'return_full':
                    await _returnSale(fullReturn: true);
                    break;
                  case 'delete':
                    await _delete();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (!isReturned && _items.isNotEmpty)
                  const PopupMenuItem(
                    value: 'invoice',
                    child: Text('Накладная'),
                  ),
                if (canReturn)
                  const PopupMenuItem(
                    value: 'return_full',
                    child: Text('Полный возврат'),
                  ),
                if (canEditOrder)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить'),
                  ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
          Material(
            color: Colors.white,
            child: IgnorePointer(
              ignoring: _isReturning,
              child: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.primary,
                onTap: (index) => setState(() => _tabIndex = index),
                tabs: const [
                  Tab(text: 'Детали продажи'),
                  Tab(text: 'Возврат'),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              sizing: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: _buildDetailsTab(
                    context,
                    sale,
                    isReturned,
                    isReturnRecord,
                  ),
                ),
                RepaintBoundary(
                  child: _buildReturnTab(context, sale, canReturn),
                ),
              ],
            ),
          ),
        ],
      ),
          if (_isReturning) _buildReturningOverlay(),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(
    BuildContext context,
    Sale sale,
    bool isReturned,
    bool isReturnRecord,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SaleDetailInfoSection(sale: sale),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${TimeUtil.toUtcPlus5Wall(sale.createdAt).day.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(sale.createdAt).month.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(sale.createdAt).year} '
                      '${TimeUtil.toUtcPlus5Wall(sale.createdAt).hour.toString().padLeft(2, '0')}:${TimeUtil.toUtcPlus5Wall(sale.createdAt).minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const Divider(),
                    ...List.generate(_items.length, (index) {
                      final item = _items[index];
                      final sourceLine = index < _sourceItems.length
                          ? _sourceItems[index]
                          : null;
                      final fullyReturned = _isLineFullyReturned(index);
                      if (isReturned || isReturnRecord || fullyReturned || _isOfdSale) {
                        final inactiveOnOriginalSale =
                            fullyReturned && !isReturned && !isReturnRecord;
                        final subtitle = inactiveOnOriginalSale && sourceLine != null
                            ? 'Полностью возвращено (${sourceLine.returnedQuantity} ${sourceLine.unit})'
                            : '${item.price.toStringAsFixed(2)} ₸ × ${item.quantity} ${item.unit}'
                                '${sourceLine != null && sourceLine.returnedQuantity > 0 ? ' (возвр. ${sourceLine.returnedQuantity})' : ''}';
                        return Opacity(
                          opacity: inactiveOnOriginalSale ? 0.55 : 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: inactiveOnOriginalSale
                                              ? AppColors.muted
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${item.total.toStringAsFixed(2)} ₸',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: inactiveOnOriginalSale
                                        ? AppColors.muted
                                        : null,
                                    decoration: inactiveOnOriginalSale
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _editingNameIndex == index &&
                                          _nameEditController != null
                                      ? TextField(
                                          controller: _nameEditController,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                          ),
                                          onSubmitted: (_) => _finishEditName(),
                                        )
                                      : GestureDetector(
                                          onDoubleTap: () =>
                                              _startEditName(index),
                                          child: Text(
                                            item.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onDoubleTap: () =>
                                            _startEditPrice(index),
                                        child: _editingPriceIndex == index &&
                                                _priceEditController != null
                                            ? SizedBox(
                                                width: 100,
                                                child: TextField(
                                                  controller: _priceEditController,
                                                  autofocus: true,
                                                  keyboardType: const TextInputType
                                                      .numberWithOptions(
                                                    decimal: true,
                                                  ),
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    border: OutlineInputBorder(),
                                                    contentPadding:
                                                        EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 6,
                                                    ),
                                                  ),
                                                  onSubmitted: (_) =>
                                                      _finishEditPrice(),
                                                ),
                                              )
                                            : Text(
                                                '${item.price.toStringAsFixed(2)} ₸ × ',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted,
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                      ),
                                      GestureDetector(
                                        onTap: () => _editQuantity(index),
                                        child: Text(
                                          '${item.quantity.toStringAsFixed(item.unit == 'pcs' ? 0 : 2)} ${item.unit}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                      if (sourceLine != null &&
                                          sourceLine.returnedQuantity > 0) ...[
                                        Text(
                                          ' (возвр. ${sourceLine.returnedQuantity} из ${sourceLine.quantity})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => _updateQuantity(index, -1),
                                  iconSize: 22,
                                ),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _editQuantity(index),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        item.quantity.toStringAsFixed(
                                          item.unit == 'pcs' ? 0 : 2,
                                        ),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          decoration: TextDecoration.underline,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () =>
                                      _updateQuantity(index, 1),
                                  iconSize: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${item.total.toStringAsFixed(2)} ₸',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: AppColors.danger,
                                    size: 22,
                                  ),
                                  onPressed: () => _removeItem(index),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Общее количество',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _formatTotalQty(_itemsTotalQty),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Итого',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SaleListAmountTitle(
                          sale: sale,
                          prominent: true,
                          amount: _itemsTotal,
                        ),
                      ],
                    ),
                    if (!isReturned && !_isOfdSale) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _addArbitraryItem,
                        icon: const Icon(Icons.edit_note, size: 20),
                        label: const Text('Произвольный товар'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (sale.isOnCredit && _counterparty != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Продажа в долг',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Покупатель: ${_counterparty!.name}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Сумма продажи:',
                            style: TextStyle(color: AppColors.muted),
                          ),
                          Text(
                            '${sale.totalPrice.toStringAsFixed(2)} ₸',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Оплачено:',
                            style: TextStyle(color: AppColors.muted),
                          ),
                          Text(
                            '${sale.paidAmount.toStringAsFixed(2)} ₸',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Остаток долга:',
                            style: TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${sale.remainingDebt.toStringAsFixed(2)} ₸',
                            style: TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      if (_debtPayments.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'История платежей:',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        ..._debtPayments.map((payment) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${TimeUtil.toUtcPlus5Wall(payment.paymentDate).day.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(payment.paymentDate).month.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(payment.paymentDate).year}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                        if (payment.notes != null &&
                                            payment.notes!.isNotEmpty)
                                          Text(
                                            payment.notes!,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${payment.amount.toStringAsFixed(2)} ₸',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                      if (sale.remainingDebt > 0) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isSaving ? null : _payDebt,
                          icon: const Icon(Icons.payment, size: 20),
                          label: const Text('Оплатить долг'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.danger,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (!isReturned && !isReturnRecord && !_isOfdSale) ...[
              const SizedBox(height: 24),
              Text(
                'Редактирование',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _selectedCashierId,
                decoration: const InputDecoration(labelText: 'Кассир'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Не выбран')),
                  ..._cashiers.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedCashierId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                value: _selectedShiftId,
                decoration: const InputDecoration(labelText: 'Смена'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Не выбрана')),
                  ..._shifts.map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${TimeUtil.toUtcPlus5Wall(s.openedAt).day.toString().padLeft(2, '0')}.${TimeUtil.toUtcPlus5Wall(s.openedAt).month.toString().padLeft(2, '0')} '
                        '${TimeUtil.toUtcPlus5Wall(s.openedAt).hour.toString().padLeft(2, '0')}:${TimeUtil.toUtcPlus5Wall(s.openedAt).minute.toString().padLeft(2, '0')}'
                        '${s.closedAt != null ? ' (закрыта)' : ' (открыта)'}',
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedShiftId = v),
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildReturnTab(BuildContext context, Sale sale, bool canReturn) {
    if (!canReturn) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  sale.isReturned
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 40,
                  color: AppColors.muted,
                ),
                const SizedBox(height: 12),
                Text(
                  sale.isReturnRecord
                      ? 'Это документ возврата'
                      : sale.isReturned
                          ? 'По этой продаже оформлен полный возврат'
                          : 'Возврат по этой продаже недоступен',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (sale.returnSales.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Оформленные возвраты',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ...sale.returnSales.map(
                    (r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Возврат №${r.id}'),
                      subtitle: Text(
                        '${r.totalPrice.toStringAsFixed(2)} ₸ • ${_formatSaleDateTime(r.createdAt)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push<bool>('/sales/sale/${r.id}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Выберите позиции для возврата',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...List.generate(_sourceItems.length, (index) {
                final line = _sourceItems[index];
                final remaining = line.remainingQuantity;
                if (remaining <= 0) {
                  return ListTile(
                    dense: true,
                    title: Text(
                      line.name,
                      style: TextStyle(color: AppColors.muted),
                    ),
                    subtitle: Text(
                      'Полностью возвращено (${line.returnedQuantity} ${line.unit})',
                    ),
                  );
                }
                final step = line.unit == 'pcs' ? 1.0 : 0.1;
                final draft = _returnDraftQty[index] ?? 0;
                return ListTile(
                  title: Text(line.name),
                  subtitle: Text(
                    'Доступно: $remaining ${line.unit} '
                    '(продано ${line.quantity}, возвр. ${line.returnedQuantity})',
                  ),
                  trailing: SizedBox(
                    width: 140,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: !_isReturning && draft > 0
                              ? () => setState(() {
                                    _returnDraftQty[index] =
                                        (draft - step).clamp(0, remaining);
                                  })
                              : null,
                        ),
                        Text(draft.toStringAsFixed(
                          line.unit == 'pcs' ? 0 : 2,
                        )),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: !_isReturning && draft < remaining
                              ? () => setState(() {
                                    _returnDraftQty[index] =
                                        (draft + step).clamp(0, remaining);
                                  })
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isReturning
                          ? null
                          : () => _returnSale(fullReturn: false),
                      icon: const Icon(Icons.undo),
                      label: Text(
                        _isReturning ? 'Оформление...' : 'Частичный возврат',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isReturning
                          ? null
                          : () => _returnSale(fullReturn: true),
                      icon: const Icon(Icons.keyboard_return),
                      label: Text(
                        _isReturning ? 'Оформление...' : 'Полный возврат',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSaleDateTime(DateTime dt) {
    final t = TimeUtil.toUtcPlus5Wall(dt);
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
