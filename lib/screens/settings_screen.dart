import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/storage.dart';
import '../services/receipt_printer_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.storage,
  });

  final Storage storage;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _printers = [];
  String? _selectedPrinterName;
  bool _isLoading = true;
  String? _error;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _selectedPrinterName = widget.storage.receiptPrinterName;
    _loadPrinters();
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
        _error = 'Не удалось получить список принтеров. '
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Принтер для чеков сохранён')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Настройки',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
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
                    'Печать чеков',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
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
                  if (!Platform.isWindows)
                    Text(
                      'Печать чеков на принтер 80мм поддерживается только на Windows.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    )
                  else if (_isLoading)
                    const SizedBox(
                      height: 48,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _printers.contains(_selectedPrinterName)
                          ? _selectedPrinterName
                          : (_printers.isNotEmpty ? _printers.first : null),
                      decoration: const InputDecoration(
                        labelText: 'Принтер для чеков (80мм)',
                        border: OutlineInputBorder(),
                      ),
                      items: _printers
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                p,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => _savePrinter(v),
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
