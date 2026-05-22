import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/product_search.dart';
import '../utils/toast.dart';
import '../widgets/nkt_product_request_form.dart';
import '../widgets/nkt_variants_ui.dart';

enum NktDetailsTab { product, nkt, request }

class NktProductDetailsScreen extends StatefulWidget {
  const NktProductDetailsScreen({
    super.key,
    required this.apiService,
    required this.productId,
    this.initialTab = NktDetailsTab.product,
  });

  final ApiService apiService;
  final int productId;
  final NktDetailsTab initialTab;

  @override
  State<NktProductDetailsScreen> createState() =>
      _NktProductDetailsScreenState();
}

class _NktProductDetailsScreenState extends State<NktProductDetailsScreen>
    with SingleTickerProviderStateMixin {
  Product? _product;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _newNameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _unitController = TextEditingController();
  final _priceController = TextEditingController();
  final _discountPriceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _stockThresholdController = TextEditingController();
  bool _isActive = true;
  bool _dirty = false;
  NktSearchResult? _nktSearchResult;
  bool _nktSearching = false;
  bool _nktLinking = false;
  String? _pickedNktNtin;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialIndex = switch (widget.initialTab) {
      NktDetailsTab.nkt => 1,
      NktDetailsTab.request => 2,
      NktDetailsTab.product => 0,
    };
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _slugController.dispose();
    _newNameController.dispose();
    _barcodeController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _discountPriceController.dispose();
    _purchasePriceController.dispose();
    _stockController.dispose();
    _stockThresholdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final p = await widget.apiService.getProduct(widget.productId);
      _populateControllers(p);
      if (!mounted) return;
      setState(() {
        _product = p;
        _isLoading = false;
      });
      await _loadCachedNktVariants(p);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить товар';
        _isLoading = false;
      });
    }
  }

  void _populateControllers(Product p) {
    _nameController.text = p.name;
    _slugController.text = p.slug;
    _newNameController.text = p.newName ?? '';
    _barcodeController.text = p.barcode ?? '';
    _unitController.text = p.unit;
    _priceController.text = _fmtNum(p.price);
    _discountPriceController.text =
        p.discountPrice != null ? _fmtNum(p.discountPrice!) : '';
    _purchasePriceController.text = _fmtNum(p.purchasePrice);
    _stockController.text = _fmtNum(p.stock);
    _stockThresholdController.text = _fmtNum(p.stockThreshold);
    _isActive = p.isActive;
    _dirty = false;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _isSaving = true);
    try {
      final discountRaw = _discountPriceController.text.trim();
      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'slug': _slugController.text.trim(),
        'new_name': _newNameController.text.trim().isEmpty
            ? null
            : _newNameController.text.trim(),
        'barcode': _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        'unit': _unitController.text.trim(),
        'price': double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0,
        'discount_price': discountRaw.isEmpty
            ? null
            : double.tryParse(discountRaw.replaceAll(',', '.')),
        'purchase_price': double.tryParse(
              _purchasePriceController.text.replaceAll(',', '.'),
            ) ??
            0,
        'stock':
            double.tryParse(_stockController.text.replaceAll(',', '.')) ?? 0,
        'stock_threshold': double.tryParse(
              _stockThresholdController.text.replaceAll(',', '.'),
            ) ??
            0,
        'is_active': _isActive,
      };

      final updated = await widget.apiService.updateProduct(
        widget.productId,
        payload,
      );
      _populateControllers(updated);
      if (!mounted) return;
      setState(() {
        _product = updated;
        _isSaving = false;
      });
      showToast(context, 'Сохранено');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final data = e.response?.data;
      String msg = 'Не удалось сохранить';
      if (data is Map) {
        if (data['message'] is String) {
          msg = data['message'] as String;
        } else if (data['errors'] is Map) {
          final errors = data['errors'] as Map;
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) {
            msg = first.first.toString();
          }
        }
      }
      showToast(context, msg);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showToast(context, 'Не удалось сохранить');
    }
  }

  void _onBack() {
    context.pop(_product);
  }

  void _openFullProductForm() {
    context.push('/products/${widget.productId}/edit');
  }

  String? get _effectiveBarcode {
    final fromField = _barcodeController.text.trim();
    if (fromField.isNotEmpty) return fromField;
    if (_product != null && productHasScannableBarcode(_product!)) {
      final display = productDisplayBarcode(_product!);
      if (display != '—') return display;
    }
    return null;
  }

  Future<void> _loadCachedNktVariants(Product p) async {
    if (!productHasScannableBarcode(p)) return;
    try {
      final result = await widget.apiService.nktSearch(widget.productId);
      if (!mounted) return;
      setState(() {
        _nktSearchResult = result;
        _pickedNktNtin = _defaultPickedNtin(result, p);
      });
    } catch (_) {}
  }

  String? _defaultPickedNtin(NktSearchResult result, Product p) {
    if (result.variants.isEmpty) return null;
    if (result.variants.length == 1) {
      return result.variants.first.ntinCode;
    }
    final linked = p.nktNtin;
    if (linked != null &&
        result.variants.any((v) => v.ntinCode == linked)) {
      return linked;
    }
    return null;
  }

  Future<NktSearchResult?> _searchNktVariants({bool forceFresh = false}) async {
    if (_effectiveBarcode == null) {
      showToast(context, 'У товара нет штрихкода');
      return null;
    }
    setState(() => _nktSearching = true);
    try {
      final result = await widget.apiService.nktSearch(
        widget.productId,
        forceFresh: forceFresh,
      );
      if (!mounted) return null;
      setState(() {
        _nktSearchResult = result;
        _nktSearching = false;
        _pickedNktNtin =
            _product != null ? _defaultPickedNtin(result, _product!) : null;
      });
      return result;
    } on DioException catch (e) {
      if (!mounted) return null;
      setState(() => _nktSearching = false);
      showToast(
        context,
        nktExtractDioError(e, fallback: 'Ошибка запроса в НКТ'),
      );
    } catch (_) {
      if (!mounted) return null;
      setState(() => _nktSearching = false);
      showToast(context, 'Ошибка запроса в НКТ');
    }
    return null;
  }

  Future<void> _runNktSearch() async {
    final result = await _searchNktVariants(forceFresh: true);
    if (result == null || !mounted) return;

    if (result.variants.isEmpty) {
      try {
        final refreshed = await widget.apiService.getProduct(widget.productId);
        if (mounted) {
          _populateControllers(refreshed);
          setState(() => _product = refreshed);
        }
      } catch (_) {}
    }
  }

  Future<void> _linkNkt(String ntin) async {
    if (_nktLinking) return;
    setState(() => _nktLinking = true);
    try {
      final updated = await widget.apiService.nktLink(widget.productId, ntin);
      if (!mounted) return;
      _populateControllers(updated);
      setState(() {
        _product = updated;
        _nktLinking = false;
        _pickedNktNtin = ntin;
      });
      showToast(context, 'Товар привязан к НКТ');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _nktLinking = false);
      showToast(
        context,
        nktExtractDioError(e, fallback: 'Не удалось привязать'),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _nktLinking = false);
      showToast(context, 'Не удалось привязать');
    }
  }

  String _imageUrl(String path) => widget.apiService.fileUrl(path);

  String _resolveImageUrl(String path) =>
      path.startsWith('http') ? path : _imageUrl(path);

  Future<void> _showImagePreview(String path) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Изображение'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          body: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.network(
                _resolveImageUrl(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text(
                    'Не удалось загрузить изображение',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final router = GoRouter.of(context);
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Несохранённые изменения'),
            content: const Text(
              'Вы изменили данные товара, но не сохранили их. Выйти без сохранения?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Остаться'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Выйти'),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          router.pop(_product);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.primaryLight,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBack,
          ),
          title: Text(_product?.name ?? 'Товар'),
          actions: [
            if (_product != null) ...[
              IconButton(
                tooltip: 'Открыть полную форму товара',
                icon: const Icon(PhosphorIconsRegular.pencilSimple),
                onPressed: _openFullProductForm,
              ),
              if (_tabController.index == 0)
                IconButton(
                  tooltip: _isSaving ? 'Сохраняем...' : 'Сохранить',
                  onPressed: _isSaving || !_dirty ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsRegular.floppyDisk),
                ),
              IconButton(
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading || _isSaving ? null : _load,
              ),
            ],
          ],
          bottom: _product == null
              ? null
              : TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  onTap: (_) => setState(() {}),
                  tabs: const [
                    Tab(text: 'Товар'),
                    Tab(text: 'НКТ'),
                    Tab(text: 'Заявка НКТ'),
                  ],
                ),
        ),
        body: _buildBody(),
        bottomNavigationBar: _product == null || _tabController.index != 0
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : _onBack,
                          child: const Text('Назад'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _isSaving || !_dirty ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _isSaving ? 'Сохраняем...' : 'Сохранить',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _onProductUpdatedFromRequest(Product updated) {
    setState(() => _product = updated);
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _product == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? 'Товар не найден',
              style: const TextStyle(color: AppColors.danger),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final p = _product!;

    return TabBarView(
      controller: _tabController,
      children: [
        _buildProductTab(p),
        _buildNktTab(p),
        _buildRequestTab(p),
      ],
    );
  }

  Widget _buildProductTab(Product p) {
    return Form(
      key: _formKey,
      onChanged: () {
        if (!_dirty && mounted) setState(() => _dirty = true);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Идентификация',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReadOnlyKV('ID', p.id.toString()),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Название *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Обязательное поле' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newNameController,
                  decoration: const InputDecoration(
                    labelText: 'Новое название',
                    helperText: 'Используется при переименовании на этикетках',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _slugController,
                  decoration: const InputDecoration(labelText: 'Slug'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcodeController,
                  decoration: const InputDecoration(
                    labelText: 'Штрихкод',
                    hintText: '13 цифр (EAN-13)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                _ReadOnlyKV(
                  'Категория ID',
                  p.categoryId?.toString() ?? '—',
                  hint: 'Изменить категорию можно через полную форму товара',
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Параметры',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _unitController,
                  decoration: const InputDecoration(
                    labelText: 'Единица измерения',
                    hintText: 'pcs / g',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Активен'),
                  subtitle: const Text(
                    'Если выключено — товар скрыт из кассы',
                  ),
                  value: _isActive,
                  onChanged: (v) {
                    setState(() {
                      _isActive = v;
                      _dirty = true;
                    });
                  },
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Цены',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NumberField(
                  controller: _priceController,
                  label: 'Цена *',
                  suffix: '₸',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Укажите цену';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _discountPriceController,
                  label: 'Цена со скидкой',
                  suffix: '₸',
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _purchasePriceController,
                  label: 'Закупочная',
                  suffix: '₸',
                ),
                const SizedBox(height: 12),
                _ReadOnlyKV(
                  'Эффективная цена',
                  '${_fmtNum(p.effectivePrice)} ₸',
                  hint: 'Если задана цена со скидкой > 0 — берётся она',
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Склад',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NumberField(
                  controller: _stockController,
                  label: 'Остаток',
                ),
                const SizedBox(height: 12),
                _NumberField(
                  controller: _stockThresholdController,
                  label: 'Порог запаса',
                ),
              ],
            ),
          ),
          if (p.images != null && p.images!.isNotEmpty)
            _SectionCard(
              title: 'Изображения (${p.images!.length})',
              child: _ProductImagesPreview(
                images: p.images!,
                resolveUrl: _resolveImageUrl,
                onTap: _showImagePreview,
              ),
            ),
          if (p.meta != null && p.meta!.isNotEmpty)
            _SectionCard(
              title: 'Meta',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in p.meta!.entries)
                    _ReadOnlyKV(e.key, _fmtMetaValue(e.value)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openFullProductForm,
            icon: const Icon(Icons.edit_note),
            label: const Text('Открыть полную форму товара'),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildNktTab(Product p) {
    final hasNktData =
        p.isLinkedToNkt || p.isNktNotFound || p.nktCheckedAt != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasNktData)
          _SectionCard(
            title: 'НКТ — статус',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NktStatusBadge(product: p),
                if (p.nktCheckedAt != null) ...[
                  const SizedBox(height: 8),
                  _ReadOnlyKV('Проверено', _fmtDateTime(p.nktCheckedAt!)),
                ],
                if (p.nktModifiedAt != null)
                  _ReadOnlyKV(
                    'Изменено в НКТ',
                    _fmtDateTime(p.nktModifiedAt!),
                  ),
              ],
            ),
          ),
        _SectionCard(
          title: _nktSearchResult != null
              ? 'НКТ — варианты по штрихкоду (${_nktSearchResult!.variants.length})'
              : 'НКТ — варианты по штрихкоду',
          child: _buildNktVariantsBlock(p),
        ),
        if (p.isLinkedToNkt) ...[
            _SectionCard(
              title: 'НКТ — идентификация',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReadOnlyKV(
                    'NTIN',
                    p.nktNtin ?? '—',
                    mono: true,
                    copyable: p.nktNtin != null,
                  ),
                  _ReadOnlyKV(
                    'GTIN',
                    p.nktGtin ?? '—',
                    mono: true,
                    copyable: p.nktGtin != null,
                  ),
                  _ReadOnlyKV(
                    'НКТ Product ID',
                    p.nktProductId?.toString() ?? '—',
                  ),
                ],
              ),
            ),
            _SectionCard(
              title: 'НКТ — названия',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReadOnlyKV('RU', p.nktNameRu ?? '—'),
                  _ReadOnlyKV('KK', p.nktNameKk ?? '—'),
                ],
              ),
            ),
            _SectionCard(
              title: 'НКТ — характеристики',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReadOnlyKV('Маркировка EAC', _fmtBool(p.nktIsMarkedeac)),
                  _ReadOnlyKV('СЗПТ (соц.)', _fmtBool(p.nktIsSocial)),
                  _ReadOnlyKV(
                    'Ед. изм. (код)',
                    p.nktMeasureCode ?? '—',
                  ),
                  _ReadOnlyKV(
                    'Ед. изм. (название)',
                    p.nktMeasureName ?? '—',
                  ),
                ],
              ),
            ),
            if (p.nktIsDeactivated == true ||
                p.nktDeactivationReason != null ||
                p.nktDuplicateOfNtin != null)
              _SectionCard(
                title: 'НКТ — деактивация',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReadOnlyKV(
                      'Деактивирован',
                      _fmtBool(p.nktIsDeactivated),
                    ),
                    if (p.nktDeactivationReason != null &&
                        p.nktDeactivationReason!.isNotEmpty)
                      _ReadOnlyKV('Причина', p.nktDeactivationReason!),
                    if (p.nktDuplicateOfNtin != null &&
                        p.nktDuplicateOfNtin!.isNotEmpty)
                      _ReadOnlyKV(
                        'Дубликат NTIN',
                        p.nktDuplicateOfNtin!,
                        mono: true,
                        copyable: true,
                      ),
                  ],
                ),
              ),
          ],
        if (p.nktRequestStatus == 'completed' && !p.isLinkedToNkt)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Заявка выполнена. Нажмите «Поиск» выше, чтобы привязать товар к NTIN в каталоге.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildRequestTab(Product p) {
    return NktProductRequestForm(
      api: widget.apiService,
      product: p,
      onProductUpdated: _onProductUpdatedFromRequest,
    );
  }

  Widget _buildNktVariantsBlock(Product p) {
    final barcode = _effectiveBarcode;
    final result = _nktSearchResult;
    final canLink = _pickedNktNtin != null &&
        _pickedNktNtin!.isNotEmpty &&
        p.nktNtin != _pickedNktNtin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ReadOnlyKV(
                'Штрихкод',
                barcode ?? '—',
                mono: barcode != null,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _nktSearching || _nktLinking || barcode == null
                  ? null
                  : _runNktSearch,
              icon: _nktSearching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      PhosphorIconsRegular.magnifyingGlass,
                      size: 18,
                    ),
              label: Text(_nktSearching ? 'Поиск...' : 'Поиск'),
            ),
          ],
        ),
        if (barcode == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Укажите штрихкод, чтобы искать в НКТ',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        if (_nktSearching) ...[
          const SizedBox(height: 16),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        ] else if (result == null) ...[
          const SizedBox(height: 12),
          const Text(
            'Нажмите «Поиск», чтобы запросить варианты в НКТ',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ] else ...[
          if (result.cached)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Данные из кэша последнего поиска',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.muted.withValues(alpha: 0.9),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (result.variants.isEmpty)
            const Text(
              'По штрихкоду варианты не найдены',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else ...[
            for (final v in result.variants)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NktVariantTile(
                  variant: v,
                  selected: _pickedNktNtin == v.ntinCode,
                  isLinked: p.nktNtin != null && p.nktNtin == v.ntinCode,
                  showRadio: result.variants.length > 1,
                  groupValue: _pickedNktNtin ?? '',
                  onRadioChanged: (val) =>
                      setState(() => _pickedNktNtin = val),
                  onTap: () => setState(() => _pickedNktNtin = v.ntinCode),
                ),
              ),
            if (canLink)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _nktLinking
                      ? null
                      : () => _linkNkt(_pickedNktNtin!),
                  icon: _nktLinking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.link, size: 18),
                  label: Text(_nktLinking ? 'Привязываем...' : 'Привязать'),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _ProductImagesPreview extends StatelessWidget {
  const _ProductImagesPreview({
    required this.images,
    required this.resolveUrl,
    required this.onTap,
  });

  static const double _previewSize = 56;

  final List<String> images;
  final String Function(String path) resolveUrl;
  final void Function(String path) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final path in images)
          GestureDetector(
            onTap: () => onTap(path),
            child: Container(
              width: _previewSize,
              height: _previewSize,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                border: Border.all(color: AppColors.muted),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: _PreviewImage(url: resolveUrl(path)),
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, color: AppColors.muted, size: 22),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  PhosphorIconsRegular.circlesFour,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyKV extends StatelessWidget {
  const _ReadOnlyKV(
    this.label,
    this.value, {
    this.mono = false,
    this.copyable = false,
    this.hint,
  });

  final String label;
  final String value;
  final bool mono;
  final bool copyable;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: mono ? 'monospace' : null,
                fontSize: mono ? 13 : 14,
                color: AppColors.surface,
              ),
            ),
          ),
          if (copyable && value.isNotEmpty && value != '—')
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                showToast(context, 'Скопировано');
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 14, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: validator,
    );
  }
}

class _NktStatusBadge extends StatelessWidget {
  const _NktStatusBadge({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    if (product.isLinkedToNkt) {
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _Chip(
            label: 'Привязан к НКТ',
            color: AppColors.accent,
            icon: Icons.link,
          ),
          if (product.nktIsDeactivated == true)
            _Chip(label: 'Деактивирован', color: AppColors.danger),
        ],
      );
    }
    if (product.isNktNotFound) {
      return _Chip(
        label: 'Нет в НКТ',
        color: AppColors.danger,
        icon: Icons.search_off,
      );
    }
    return const Text(
      'Не проверялся',
      style: TextStyle(color: AppColors.muted, fontSize: 13),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtNum(double v) {
  if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(3);
}

String _fmtBool(bool? v) => v == null ? '—' : (v ? 'Да' : 'Нет');

String _fmtDateTime(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  final l = dt.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)} '
      '${two(l.hour)}:${two(l.minute)}';
}

String _fmtMetaValue(dynamic v) {
  if (v == null) return '—';
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  try {
    return const JsonEncoder.withIndent('  ').convert(v);
  } catch (_) {
    return v.toString();
  }
}
