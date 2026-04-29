import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../services/api_service.dart';
import '../services/receipt_pdf_service.dart';
import '../services/receipt_printer_service.dart';
import '../utils/time_util.dart';
import '../widgets/invoice_dialog.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.apiService,
    required this.storage,
    required this.orderId,
  });

  final ApiService apiService;
  final Storage storage;
  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Order? _order;
  String _selectedStatus = Order.statusNew;
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _error;

  String get _cashierName {
    final name = widget.storage.user?['name']?.toString();
    return name != null && name.isNotEmpty ? name : '—';
  }

  List<CartItem> _orderAsCartItems(Order o) {
    return o.items
        .map(
          (i) => CartItem(
            productId: i.productId,
            name: i.productName ?? '—',
            price: i.price,
            quantity: i.quantity.toDouble(),
            unit: 'pcs',
          ),
        )
        .toList();
  }

  double _totalQty(List<CartItem> items) =>
      items.fold<double>(0, (s, e) => s + e.quantity);

  Future<void> _printReceipt() async {
    final order = _order;
    if (order == null) return;
    if (order.items.isEmpty) return;

    final printMode = widget.storage.receiptPrintMode;
    if ((printMode == 'raw' || printMode == 'pdf_direct') && !Platform.isWindows) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RAW и PDF Direct печать доступны только на Windows')),
        );
      }
      return;
    }

    final items = _orderAsCartItems(order);
    final dateTime = TimeUtil.toUtcPlus5Wall(order.createdAt);
    final totalQty = _totalQty(items);
    final bytes = ReceiptPrinterService.buildReceipt(
      saleId: order.id,
      cashierName: _cashierName,
      items: items,
      total: order.total,
      totalQty: totalQty,
      dateTime: dateTime,
      rawEncoding: widget.storage.receiptRawEncoding,
      xprinterCyrillicPreamble: widget.storage.receiptRawXprinterPreamble,
    );
    await ReceiptPrinterService.printReceipt(
      printerName: widget.storage.receiptPrinterName,
      bytes: bytes,
      printMode: printMode,
      saleId: order.id,
      cashierName: _cashierName,
      items: items,
      total: order.total,
      totalQty: totalQty,
      dateTime: dateTime,
    );
  }

  Future<void> _saveReceiptPdf() async {
    final order = _order;
    if (order == null) return;
    if (order.items.isEmpty) return;

    final items = _orderAsCartItems(order);
    final dateTime = TimeUtil.toUtcPlus5Wall(order.createdAt);
    final totalQty = _totalQty(items);
    final pdfBytes = await ReceiptPdfService.buildReceiptPdf(
      saleId: order.id,
      cashierName: _cashierName,
      items: items,
      total: order.total,
      totalQty: totalQty,
      dateTime: dateTime,
    );
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить чек в PDF',
      fileName: 'order-${order.id}.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (!mounted) return;
    if (path != null && path.isNotEmpty) {
      final savePath = path.endsWith('.pdf') ? path : '$path.pdf';
      await File(savePath).writeAsBytes(pdfBytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Чек сохранён: $savePath')),
      );
    }
  }

  void _showInvoice() {
    final order = _order;
    if (order == null) return;
    if (order.items.isEmpty) return;
    final items = _orderAsCartItems(order);
    showInvoiceDialog(
      context: context,
      apiService: widget.apiService,
      items: List.from(items),
      initialDocumentNumber: '${order.id}',
      storage: widget.storage,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final order = await widget.apiService.getOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _selectedStatus = order.status;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить заказ';
        _isLoading = false;
      });
    }
  }

  Future<void> _setStatus(String status) async {
    if (_order == null || _isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      final updated = await widget.apiService.updateOrderStatus(
        widget.orderId,
        status,
      );
      if (!mounted) return;
      setState(() {
        _order = updated;
        _isUpdating = false;
      });
      if (mounted) {
        final label = updated.statusLabel;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Статус изменён на «$label»')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось обновить статус'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _markIssued() async {
    await _setStatus(Order.statusIssued);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Заказ')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error != null) Text(_error!),
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

    final order = _order!;
    final canMarkIssued =
        order.status != Order.statusIssued &&
        (order.status == Order.statusNew ||
            order.status == Order.statusInProgress);

    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ #${order.id}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(true),
        ),
        actions: [
          if (canMarkIssued)
            IconButton(
              icon: _isUpdating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              tooltip: 'Выдан',
              onPressed: _isUpdating ? null : _markIssued,
            ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Сохранить чек в PDF',
            onPressed: order.items.isEmpty ? null : _saveReceiptPdf,
          ),
          if (Platform.isWindows)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Печать чека',
              onPressed: order.items.isEmpty ? null : _printReceipt,
            ),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            onSelected: (v) {
              switch (v) {
                case 'invoice':
                  _showInvoice();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'invoice', child: Text('Накладная')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(
                      'Дата',
                      TimeUtil.toUtcPlus5Wall(order.createdAt)
                          .toString()
                          .substring(0, 16),
                    ),
                    _row('Статус', order.statusLabel),
                    _row('Покупатель', order.user?.name ?? '—'),
                    if (order.user?.email != null)
                      _row('Email', order.user!.email!),
                    if (order.requestedDeliveryDate != null)
                      _row(
                        'Желаемая дата доставки',
                        order.requestedDeliveryDate!.toString().substring(
                          0,
                          10,
                        ),
                      ),
                    if (order.deliveryAddress?.address != null) ...[
                      _row(
                        'Адрес доставки',
                        order.deliveryAddress!.address ?? '—',
                      ),
                      if (order.deliveryAddress!.city != null ||
                          order.deliveryAddress!.phone != null)
                        _row(
                          '',
                          [
                                order.deliveryAddress!.city,
                                order.deliveryAddress!.phone,
                              ]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join(', '),
                        ),
                    ],
                    if (order.comment != null && order.comment!.isNotEmpty)
                      _row('Комментарий', order.comment!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Позиции',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(1),
                        2: FlexColumnWidth(1),
                        3: FlexColumnWidth(1),
                      },
                      children: [
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Товар',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Цена',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Кол-во',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Сумма',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        ...order.items.map((item) {
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(item.productName ?? '—'),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(item.price.toStringAsFixed(2)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text('${item.quantity}'),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(item.subtotal.toStringAsFixed(2)),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Итого: ${order.total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Сменить статус',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Статус',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: Order.statusNew, child: Text('Новый')),
                        DropdownMenuItem(value: Order.statusInProgress, child: Text('Заказ собирается')),
                        DropdownMenuItem(value: Order.statusIssued, child: Text('Выдан')),
                        DropdownMenuItem(value: Order.statusCancelled, child: Text('Отменён')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedStatus = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _isUpdating ? null : () => _setStatus(_selectedStatus),
                      child: Text(_isUpdating ? 'Сохранение…' : 'Установить статус'),
                    ),
                  ],
                ),
              ),
            ),
            if (canMarkIssued) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isUpdating ? null : _markIssued,
                icon: _isUpdating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: const Text('Выдан'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            SizedBox(
              width: 160,
              child: Text(
                label,
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ),
          if (label.isNotEmpty) const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
