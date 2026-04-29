import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/supplier.dart';
import '../services/api_service.dart';

class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({
    super.key,
    required this.apiService,
    this.supplierId,
    this.mode = SupplierFormMode.create,
  });

  final ApiService apiService;
  final int? supplierId;
  final SupplierFormMode mode;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

enum SupplierFormMode { create, edit }

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _iinController = TextEditingController();
  final _kbeController = TextEditingController();
  final _iikController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bikController = TextEditingController();
  final _addressController = TextEditingController();
  final _managerController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  Supplier? _supplier;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.mode == SupplierFormMode.edit && widget.supplierId != null) {
      _load();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iinController.dispose();
    _kbeController.dispose();
    _iikController.dispose();
    _bankNameController.dispose();
    _bikController.dispose();
    _addressController.dispose();
    _managerController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final supplier = await widget.apiService.getSupplier(widget.supplierId!);
      if (!mounted) return;
      setState(() {
        _supplier = supplier;
        _nameController.text = supplier.name;
        _iinController.text = supplier.iin ?? '';
        _kbeController.text = supplier.kbe ?? '';
        _iikController.text = supplier.iik ?? '';
        _bankNameController.text = supplier.bankName ?? '';
        _bikController.text = supplier.bik ?? '';
        _addressController.text = supplier.address ?? '';
        _managerController.text = supplier.manager ?? '';
        _phoneController.text = supplier.phone ?? '';
        _emailController.text = supplier.email ?? '';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить поставщика';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final data = {
        'name': name,
        'iin': _iinController.text.trim().isEmpty ? null : _iinController.text.trim(),
        'kbe': _kbeController.text.trim().isEmpty ? null : _kbeController.text.trim(),
        'iik': _iikController.text.trim().isEmpty ? null : _iikController.text.trim(),
        'bank_name': _bankNameController.text.trim().isEmpty ? null : _bankNameController.text.trim(),
        'bik': _bikController.text.trim().isEmpty ? null : _bikController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'manager': _managerController.text.trim().isEmpty ? null : _managerController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      };
      if (widget.mode == SupplierFormMode.edit && widget.supplierId != null) {
        await widget.apiService.updateSupplier(widget.supplierId!, data);
      } else {
        await widget.apiService.createSupplier(data);
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
    if (widget.supplierId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить поставщика?'),
        content: Text(
          'Поставщик «${_supplier?.name ?? ''}» будет удален безвозвратно.',
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
      await widget.apiService.deleteSupplier(widget.supplierId!);
      if (!mounted) return;
      context.pop(true);
    } catch (_) {
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
        appBar: AppBar(title: const Text('Поставщик')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _supplier == null && widget.mode == SupplierFormMode.edit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Поставщик')),
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
          widget.mode == SupplierFormMode.edit ? 'Редактирование' : 'Новый поставщик',
        ),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            tooltip: 'Сохранить',
          ),
        ],
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
                      Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название *',
                  hintText: 'Введите название',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _iinController,
                decoration: const InputDecoration(
                  labelText: 'ИИН',
                  hintText: 'ИИН',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _kbeController,
                decoration: const InputDecoration(
                  labelText: 'КБЕ',
                  hintText: 'КБЕ',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _iikController,
                decoration: const InputDecoration(
                  labelText: 'ИИК',
                  hintText: 'ИИК',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bankNameController,
                decoration: const InputDecoration(
                  labelText: 'Название банка',
                  hintText: 'Название банка',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bikController,
                decoration: const InputDecoration(
                  labelText: 'БИК',
                  hintText: 'БИК',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Адрес',
                  hintText: 'Адрес',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _managerController,
                decoration: const InputDecoration(
                  labelText: 'Руководитель',
                  hintText: 'Руководитель',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Телефон',
                  hintText: 'Телефон',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Email',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),
              if (widget.mode == SupplierFormMode.edit) ...[
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
