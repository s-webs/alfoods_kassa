import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/nkt_search_flow.dart';
import '../utils/product_search.dart';
import '../utils/nkt_request_ui.dart';
import '../utils/toast.dart';
import '../widgets/nkt_request_actions_panel.dart';
import '../widgets/nkt_variants_ui.dart';

enum _NktFilter {
  all,
  unlinked,
  linked,
  notFound,
  noBarcode,
  withRequest,
  deactivated,
}

class NktSyncScreen extends StatefulWidget {
  const NktSyncScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<NktSyncScreen> createState() => _NktSyncScreenState();
}

class _NktSyncScreenState extends State<NktSyncScreen> {
  // Сохраняем состояние экрана между навигациями (вход в детали → возврат).
  // GoRouter пересоздаёт виджет, поэтому используем статику.
  static double _savedScrollOffset = 0;
  static String _savedSearchQuery = '';
  static _NktFilter _savedFilter = _NktFilter.all;
  static final Set<int> _savedSelectedIds = {};

  List<Product> _products = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  _NktFilter _filter = _NktFilter.all;
  final Set<int> _selectedIds = {};
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchQuery = _savedSearchQuery;
    _filter = _savedFilter;
    _selectedIds.addAll(_savedSelectedIds);
    _searchController = TextEditingController(text: _savedSearchQuery);
    _scrollController = ScrollController(
      initialScrollOffset: _savedScrollOffset,
    );
    _load();
  }

  @override
  void dispose() {
    _savedScrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0;
    _savedSearchQuery = _searchQuery;
    _savedFilter = _filter;
    _savedSelectedIds
      ..clear()
      ..addAll(_selectedIds);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final products = await widget.apiService.getProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _selectedIds.removeWhere((id) => !products.any((p) => p.id == id));
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить товары';
        _isLoading = false;
      });
    }
  }

  bool _matchesFilter(Product p, _NktFilter filter) {
    switch (filter) {
      case _NktFilter.all:
        return true;
      case _NktFilter.linked:
        return p.isLinkedToNkt;
      case _NktFilter.unlinked:
        return !p.isLinkedToNkt &&
            productHasScannableBarcode(p) &&
            !p.isNktNotFound;
      case _NktFilter.notFound:
        return p.isNktNotFound;
      case _NktFilter.noBarcode:
        return !productHasScannableBarcode(p);
      case _NktFilter.withRequest:
        return p.hasNktRequest;
      case _NktFilter.deactivated:
        return p.nktIsDeactivated == true;
    }
  }

  int _countForFilter(_NktFilter filter) {
    if (filter == _NktFilter.all) return _products.length;
    return _products.where((p) => _matchesFilter(p, filter)).length;
  }

  List<Product> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    return _products.where((p) {
      if (!_matchesFilter(p, _filter)) return false;
      if (q.isEmpty) return true;
      final ntin = (p.nktNtin ?? '').toLowerCase();
      return productMatchesQuery(p, q) || ntin.contains(q);
    }).toList();
  }

  void _selectFilter(_NktFilter filter) {
    setState(() => _filter = filter);
  }

  List<Widget> _buildFilterChips() {
    const chips = <(_NktFilter, String)>[
      (_NktFilter.all, 'Все'),
      (_NktFilter.unlinked, 'Без привязки'),
      (_NktFilter.linked, 'Привязаны'),
      (_NktFilter.notFound, 'Не найдены'),
      (_NktFilter.noBarcode, 'Без штрихкода'),
      (_NktFilter.withRequest, 'С заявкой'),
      (_NktFilter.deactivated, 'Деактивированы'),
    ];

    return chips.map((entry) {
      final filter = entry.$1;
      final label = entry.$2;
      final count = _countForFilter(filter);
      final selected = _filter == filter;

      return Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 4),
        child: FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 6),
              _NktFilterCountBadge(count: count, selected: selected),
            ],
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          selected: selected,
          showCheckmark: false,
          selectedColor: AppColors.primary,
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.surface,
          ),
          side: BorderSide(
            color: selected
                ? AppColors.primary
                : AppColors.muted.withValues(alpha: 0.45),
          ),
          onSelected: (_) => _selectFilter(filter),
        ),
      );
    }).toList();
  }

  void _toggleAllVisible(bool? value) {
    final visible = _filtered;
    setState(() {
      if (value == true) {
        for (final p in visible) {
          _selectedIds.add(p.id);
        }
      } else {
        for (final p in visible) {
          _selectedIds.remove(p.id);
        }
      }
    });
  }

  bool get _allVisibleSelected {
    final visible = _filtered;
    if (visible.isEmpty) return false;
    return visible.every((p) => _selectedIds.contains(p.id));
  }

  Future<void> _onSingleSync(Product product) async {
    NktSearchResult? result;
    String? errorMsg;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NktLoadingDialog(text: 'Запрашиваем НКТ...'),
    );
    try {
      if (productHasScannableBarcode(product)) {
        result = await NktSearchFlow.searchWithBarcodeFallback(
          api: widget.apiService,
          productId: product.id,
          product: product,
          forceFresh: true,
        );
      } else {
        final name = product.name.trim();
        if (name.isEmpty) {
          if (mounted) {
            showToast(context, 'Укажите наименование товара');
          }
          return;
        }
        result = await NktSearchFlow.searchByName(
          api: widget.apiService,
          productId: product.id,
          query: name,
          forceFresh: true,
        );
      }
    } on NktSearchException catch (e) {
      errorMsg = e.message;
    } catch (_) {
      errorMsg = 'Ошибка запроса в НКТ';
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (errorMsg != null) {
      if (mounted) showToast(context, errorMsg);
      return;
    }
    final res = result!;
    if (res.variants.isEmpty) {
      try {
        final refreshed = await widget.apiService.getProduct(product.id);
        if (mounted) {
          setState(() {
            final idx = _products.indexWhere((p) => p.id == product.id);
            if (idx >= 0) _products[idx] = refreshed;
          });
        }
      } catch (_) {}
      if (mounted) {
        showToast(
          context,
          'В НКТ ничего не найдено по штрихкоду и наименованию',
        );
      }
      return;
    }

    if (!mounted) return;
    final pick = await showNktVariantPickerDialog(
      context: context,
      product: product,
      result: res,
      apiService: widget.apiService,
      productId: product.id,
    );
    if (pick == null || pick.ntin == null) return;

    await _linkProduct(
      product,
      pick.ntin!,
      searchResult: pick.searchResult ?? res,
    );
  }

  Future<void> _onSearchByName(Product product) async {
    final query = await NktSearchFlow.promptName(
      context,
      initialQuery: product.name,
    );
    if (query == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NktLoadingDialog(text: 'Поиск по наименованию...'),
    );
    NktSearchResult? result;
    String? errorMsg;
    try {
      result = await NktSearchFlow.searchByName(
        api: widget.apiService,
        productId: product.id,
        query: query,
      );
    } on NktSearchException catch (e) {
      errorMsg = e.message;
    } catch (_) {
      errorMsg = 'Ошибка запроса в НКТ';
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (errorMsg != null) {
      if (mounted) showToast(context, errorMsg);
      return;
    }
    final res = result!;
    if (res.variants.isEmpty) {
      if (mounted) {
        showToast(context, 'По наименованию «$query» ничего не найдено');
      }
      return;
    }

    if (!mounted) return;
    final pick = await showNktVariantPickerDialog(
      context: context,
      product: product,
      result: res,
      apiService: widget.apiService,
      productId: product.id,
    );
    if (pick == null || pick.ntin == null) return;
    await _linkProduct(
      product,
      pick.ntin!,
      searchResult: pick.searchResult ?? res,
    );
  }

  Future<void> _onSearchByNtin(Product product) async {
    final ntin = await NktSearchFlow.promptNtin(context);
    if (ntin == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NktLoadingDialog(text: 'Поиск по NTIN...'),
    );
    NktSearchResult? result;
    String? errorMsg;
    try {
      result = await NktSearchFlow.searchByNtin(
        api: widget.apiService,
        productId: product.id,
        ntin: ntin,
      );
    } on NktSearchException catch (e) {
      errorMsg = e.message;
    } catch (_) {
      errorMsg = 'Ошибка запроса в НКТ';
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (errorMsg != null) {
      if (mounted) showToast(context, errorMsg);
      return;
    }
    final res = result!;
    if (res.variants.isEmpty) {
      if (mounted) showToast(context, 'По NTIN $ntin ничего не найдено');
      return;
    }

    if (!mounted) return;
    final pick = await showNktVariantPickerDialog(
      context: context,
      product: product,
      result: res,
      apiService: widget.apiService,
      productId: product.id,
    );
    if (pick == null || pick.ntin == null) return;
    await _linkProduct(
      product,
      pick.ntin!,
      searchResult: pick.searchResult ?? res,
    );
  }

  Future<void> _linkProduct(
    Product product,
    String ntin, {
    NktSearchResult? searchResult,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NktLoadingDialog(text: 'Привязываем к НКТ...'),
    );
    try {
      final updated = await widget.apiService.nktLink(
        product.id,
        ntin,
        mode: searchResult?.searchMode,
        query: searchResult?.searchQuery,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        final idx = _products.indexWhere((p) => p.id == product.id);
        if (idx >= 0) _products[idx] = updated;
      });
      showToast(context, 'Товар привязан к НКТ');
    } on DioException catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, _extractError(e, fallback: 'Не удалось привязать'));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, 'Не удалось привязать');
    }
  }

  Future<void> _onRefresh(Product product) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NktLoadingDialog(text: 'Обновляем данные...'),
    );
    try {
      final updated = await widget.apiService.nktRefresh(product.id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        final idx = _products.indexWhere((p) => p.id == product.id);
        if (idx >= 0) _products[idx] = updated;
      });
      showToast(context, 'Данные обновлены');
    } on DioException catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, _extractError(e, fallback: 'Не удалось обновить'));
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(context, 'Не удалось обновить');
    }
  }

  Future<void> _onDetails(Product product) async {
    final updated = await context.push<Product>('/nkt/${product.id}');
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        final idx = _products.indexWhere((p) => p.id == updated.id);
        if (idx >= 0) _products[idx] = updated;
      });
    }
  }

  void _replaceProduct(Product updated) {
    setState(() {
      final idx = _products.indexWhere((p) => p.id == updated.id);
      if (idx >= 0) _products[idx] = updated;
    });
  }

  void _onCreateRequest(Product product) {
    context.push('/nkt/${product.id}?tab=request');
  }

  Future<void> _onUnlink(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Отвязать товар от НКТ?'),
        content: Text('Все НКТ-поля у товара «${product.name}» будут очищены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Отвязать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final updated = await widget.apiService.nktUnlink(product.id);
      if (!mounted) return;
      setState(() {
        final idx = _products.indexWhere((p) => p.id == product.id);
        if (idx >= 0) _products[idx] = updated;
      });
      showToast(context, 'Связь с НКТ удалена');
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Не удалось отвязать');
    }
  }

  Future<void> _onBulkSync() async {
    final selected =
        _products.where((p) => _selectedIds.contains(p.id)).toList();

    if (selected.isEmpty) {
      showToast(context, 'Выберите товары в списке');
      return;
    }

    final mode = await showDialog<_BulkMode>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Массовая синхронизация'),
        content: Text(
          'Выбрано товаров: ${selected.length}.\n\n'
          'Если для штрихкода НКТ возвращает ровно один товар — будет автоматическая привязка.\n'
          'Если несколько вариантов — откроется окно выбора, обработка приостановится до вашего ответа.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Отмена'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogCtx, _BulkMode.refreshOnly),
            child: const Text('Только обновить связанные'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, _BulkMode.autoLink),
            child: const Text('Синхронизировать все'),
          ),
        ],
      ),
    );
    if (mode == null) return;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BulkProgressDialog(
        products: selected,
        mode: mode,
        apiService: widget.apiService,
        onProductUpdated: (updated) {
          if (!mounted) return;
          setState(() {
            final idx = _products.indexWhere((p) => p.id == updated.id);
            if (idx >= 0) _products[idx] = updated;
          });
        },
      ),
    );

    if (mounted) setState(_selectedIds.clear);
    // Подтягиваем свежие данные: для товаров, по которым в bulk'е ничего не нашлось,
    // бэкенд проставил nkt_not_found=true — нужно отразить это в списке.
    if (mounted) await _load(silent: true);
  }

  String _extractError(DioException e, {required String fallback}) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryLight,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildToolbar(),
            const SizedBox(height: 12),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final linkedCount = _products.where((p) => p.isLinkedToNkt).length;
    final deactivatedCount = _products
        .where((p) => p.nktIsDeactivated == true)
        .length;
    final notFoundCount = _products.where((p) => p.isNktNotFound).length;
    final requestCount = _products.where((p) => p.hasNktRequest).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          PhosphorIconsRegular.barcode,
          color: AppColors.primary,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Синхронизация с НКТ',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.surface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Привязано: $linkedCount из ${_products.length}'
                ' · деактивировано в НКТ: $deactivatedCount'
                '${notFoundCount > 0 ? ' · не найдено: $notFoundCount' : ''}'
                '${requestCount > 0 ? ' · заявок: $requestCount' : ''}',
                style: const TextStyle(color: AppColors.surface, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Обновить список',
          onPressed: _isLoading ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Поиск: имя, штрихкод, NTIN',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        ..._buildFilterChips(),
        if (_selectedIds.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Выбрано: ${_selectedIds.length}',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _onBulkSync,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Синхронизировать выбранные'),
          ),
          TextButton(
            onPressed: () => setState(_selectedIds.clear),
            child: const Text('Снять выделение'),
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _load(),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final list = _filtered;
    if (list.isEmpty) {
      return const Center(child: Text('Нет товаров под этот фильтр'));
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.5),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.muted.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _allVisibleSelected,
                  tristate: false,
                  onChanged: _toggleAllVisible,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Товар',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 160,
                  child: Text(
                    'Штрихкод',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.surface,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 220,
                  child: Text(
                    'НКТ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 300),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: AppColors.muted.withValues(alpha: 0.3)),
              itemBuilder: (context, i) {
                final p = list[i];
                return _ProductRow(
                  product: p,
                  isSelected: _selectedIds.contains(p.id),
                  onSelect: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.add(p.id);
                      } else {
                        _selectedIds.remove(p.id);
                      }
                    });
                  },
                  onSync: () => _onSingleSync(p),
                  onSearchByName: () => _onSearchByName(p),
                  onSearchByNtin: () => _onSearchByNtin(p),
                  onRefresh: () => _onRefresh(p),
                  onUnlink: () => _onUnlink(p),
                  onDetails: () => _onDetails(p),
                  onCreateRequest: () => _onCreateRequest(p),
                  onOpenRequestTab: () => context.push('/nkt/${p.id}?tab=request'),
                  onProductUpdated: _replaceProduct,
                  apiService: widget.apiService,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.isSelected,
    required this.onSelect,
    required this.onSync,
    required this.onSearchByName,
    required this.onSearchByNtin,
    required this.onRefresh,
    required this.onUnlink,
    required this.onDetails,
    required this.onCreateRequest,
    required this.onOpenRequestTab,
    required this.onProductUpdated,
    required this.apiService,
  });

  final Product product;
  final bool isSelected;
  final ValueChanged<bool?> onSelect;
  final VoidCallback onSync;
  final VoidCallback onSearchByName;
  final VoidCallback onSearchByNtin;
  final VoidCallback onRefresh;
  final VoidCallback onUnlink;
  final VoidCallback onDetails;
  final VoidCallback onCreateRequest;
  final VoidCallback onOpenRequestTab;
  final ValueChanged<Product> onProductUpdated;
  final ApiService apiService;

  @override
  Widget build(BuildContext context) {
    final hasBarcode = productHasScannableBarcode(product);

    return InkWell(
      onTap: onDetails,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: isSelected,
              onChanged: onSelect,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.nktNameRu != null &&
                      product.nktNameRu!.isNotEmpty &&
                      product.nktNameRu != product.name)
                    Text(
                      'НКТ: ${product.nktNameRu}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 160,
              child: Text(
                hasBarcode ? productDisplayBarcode(product) : '—',
                style: TextStyle(
                  color: hasBarcode ? AppColors.surface : AppColors.muted,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: _NktStatus(product: product),
            ),
            SizedBox(
              width: 300,
              child: _RowActions(
                product: product,
                apiService: apiService,
                onSync: onSync,
                onSearchByName: onSearchByName,
                onSearchByNtin: onSearchByNtin,
                onRefresh: onRefresh,
                onUnlink: onUnlink,
                onDetails: onDetails,
                onCreateRequest: onCreateRequest,
                onOpenRequestTab: onOpenRequestTab,
                onProductUpdated: onProductUpdated,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NktStatus extends StatelessWidget {
  const _NktStatus({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    if (!product.isLinkedToNkt) {
      if (product.hasNktRequest) {
        return _ChipBadge(
          label: product.nktRequestStatusDisplay,
          color: nktRequestStatusColor(product.nktRequestStatus),
          icon: Icons.assignment_outlined,
        );
      }
      if (product.isNktNotFound) {
        return Row(
          children: [
            _ChipBadge(
              label: 'Нет в НКТ',
              color: AppColors.danger,
              icon: Icons.search_off,
            ),
          ],
        );
      }
      return const Text(
        'Не привязан',
        style: TextStyle(color: AppColors.muted, fontSize: 13),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'NTIN: ${product.nktNtin}',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: AppColors.surface,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (product.nktIsMarkedeac == true)
              _ChipBadge(
                label: 'Маркировка',
                color: AppColors.accent,
                icon: Icons.qr_code_2,
              ),
            if (product.nktIsSocial == true)
              _ChipBadge(label: 'СЗПТ', color: AppColors.primary),
            if (product.nktIsDeactivated == true)
              _ChipBadge(label: 'Деактивирован', color: AppColors.danger),
          ],
        ),
      ],
    );
  }
}

class _NktFilterCountBadge extends StatelessWidget {
  const _NktFilterCountBadge({
    required this.count,
    required this.selected,
  });

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.22)
            : AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: selected ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.product,
    required this.apiService,
    required this.onSync,
    required this.onSearchByName,
    required this.onSearchByNtin,
    required this.onRefresh,
    required this.onUnlink,
    required this.onDetails,
    required this.onCreateRequest,
    required this.onOpenRequestTab,
    required this.onProductUpdated,
  });

  final Product product;
  final ApiService apiService;
  final VoidCallback onSync;
  final VoidCallback onSearchByName;
  final VoidCallback onSearchByNtin;
  final VoidCallback onRefresh;
  final VoidCallback onUnlink;
  final VoidCallback onDetails;
  final VoidCallback onCreateRequest;
  final VoidCallback onOpenRequestTab;
  final ValueChanged<Product> onProductUpdated;

  @override
  Widget build(BuildContext context) {
    final hasBarcode = productHasScannableBarcode(product);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (nktCanCreateRequest(product))
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: OutlinedButton(
              onPressed: onCreateRequest,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              child: const Text('Заявка', style: TextStyle(fontSize: 12)),
            ),
          ),
        if (product.hasNktRequest)
          NktRequestActionsPanel(
            api: apiService,
            product: product,
            compact: true,
            onProductUpdated: onProductUpdated,
            onOpenRequestTab: onOpenRequestTab,
          ),
        if (!product.isLinkedToNkt) ...[
          FilledButton.icon(
            onPressed: onSync,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Найти'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Поиск по наименованию',
            onPressed: onSearchByName,
            icon: const Icon(Icons.text_fields, size: 18),
          ),
          IconButton(
            tooltip: 'Поиск по NTIN',
            onPressed: onSearchByNtin,
            icon: const Icon(Icons.pin, size: 18),
          ),
        ]
        else ...[
          OutlinedButton.icon(
            onPressed: onRefresh,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Обновить'),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Отвязать',
            color: AppColors.danger,
            onPressed: onUnlink,
            icon: const Icon(Icons.link_off, size: 18),
          ),
        ],
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Подробнее',
          onPressed: onDetails,
          icon: const Icon(Icons.info_outline, size: 18),
        ),
      ],
    );
  }
}

enum _BulkMode { autoLink, refreshOnly }

enum _BulkStatus { pending, processing, linked, refreshed, skipped, failed }

class _BulkItem {
  _BulkItem(this.product);
  final Product product;
  _BulkStatus status = _BulkStatus.pending;
  String? note;
}


class _BulkProgressDialog extends StatefulWidget {
  const _BulkProgressDialog({
    required this.products,
    required this.mode,
    required this.apiService,
    required this.onProductUpdated,
  });

  final List<Product> products;
  final _BulkMode mode;
  final ApiService apiService;
  final ValueChanged<Product> onProductUpdated;

  @override
  State<_BulkProgressDialog> createState() => _BulkProgressDialogState();
}

class _BulkProgressDialogState extends State<_BulkProgressDialog> {
  late final List<_BulkItem> _items;
  bool _done = false;
  bool _cancelled = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _items = widget.products.map((p) => _BulkItem(p)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (var i = 0; i < _items.length; i++) {
      if (_cancelled || !mounted) break;
      setState(() {
        _currentIndex = i;
        _items[i].status = _BulkStatus.processing;
      });

      final item = _items[i];
      try {
        if (widget.mode == _BulkMode.refreshOnly) {
          if (!item.product.isLinkedToNkt) {
            item.status = _BulkStatus.skipped;
            item.note = 'Не привязан';
          } else {
            final updated = await widget.apiService.nktRefresh(item.product.id);
            widget.onProductUpdated(updated);
            item.status = _BulkStatus.refreshed;
          }
        } else {
          // autoLink mode: refresh if linked, otherwise search + auto-link if single variant
          if (item.product.isLinkedToNkt) {
            final updated = await widget.apiService.nktRefresh(item.product.id);
            widget.onProductUpdated(updated);
            item.status = _BulkStatus.refreshed;
          } else {
            NktSearchResult? res;
            try {
              if (productHasScannableBarcode(item.product)) {
                res = await NktSearchFlow.searchWithBarcodeFallback(
                  api: widget.apiService,
                  productId: item.product.id,
                  product: item.product,
                  forceFresh: true,
                );
              } else {
                final name = item.product.name.trim();
                if (name.isEmpty) {
                  item.status = _BulkStatus.skipped;
                  item.note = 'Нет наименования';
                  continue;
                }
                res = await NktSearchFlow.searchByName(
                  api: widget.apiService,
                  productId: item.product.id,
                  query: name,
                  forceFresh: true,
                );
              }
            } on NktSearchException catch (e) {
              item.status = _BulkStatus.failed;
              item.note = e.message;
              continue;
            }
            if (res == null || res.variants.isEmpty) {
              item.status = _BulkStatus.skipped;
              item.note = 'Нет в НКТ';
            } else if (res.variants.length > 1) {
              if (!mounted) break;
              final pick = await showNktVariantPickerDialog(
                context: context,
                product: item.product,
                result: res,
                apiService: widget.apiService,
                productId: item.product.id,
                bulkMode: true,
                bulkIndex: i,
                bulkTotal: _items.length,
              );
              if (!mounted) break;
              if (pick == null || pick.cancelBulk) {
                item.status = _BulkStatus.skipped;
                item.note = 'Остановлено пользователем';
                _cancelled = true;
              } else if (pick.skip) {
                item.status = _BulkStatus.skipped;
                item.note = 'Пропущено вручную';
              } else if (pick.ntin != null && pick.ntin!.isNotEmpty) {
                final sr = pick.searchResult ?? res;
                final updated = await widget.apiService.nktLink(
                  item.product.id,
                  pick.ntin!,
                  mode: sr.searchMode,
                  query: sr.searchQuery,
                );
                widget.onProductUpdated(updated);
                item.status = _BulkStatus.linked;
              } else {
                item.status = _BulkStatus.skipped;
                item.note = 'Не выбран вариант';
              }
            } else {
              final ntin = res.variants.first.ntinCode;
              if (ntin == null || ntin.isEmpty) {
                item.status = _BulkStatus.skipped;
                item.note = 'Нет NTIN';
              } else {
                final updated = await widget.apiService.nktLink(
                  item.product.id,
                  ntin,
                  mode: res.searchMode,
                  query: res.searchQuery,
                );
                widget.onProductUpdated(updated);
                item.status = _BulkStatus.linked;
              }
            }
          }
        }
      } on DioException catch (e) {
        item.status = _BulkStatus.failed;
        final data = e.response?.data;
        if (data is Map) {
          final msg = data['message']?.toString() ?? '';
          final err = data['error']?.toString();
          item.note = err != null && err.isNotEmpty
              ? '$msg ($err)'
              : (msg.isNotEmpty ? msg : 'HTTP ${e.response?.statusCode ?? '?'}');
        } else {
          item.note = 'HTTP ${e.response?.statusCode ?? '?'}';
        }
      } catch (e) {
        item.status = _BulkStatus.failed;
        item.note = e.toString();
      }

      if (!mounted) break;
      setState(() {});
    }
    if (mounted) setState(() => _done = true);
  }

  int get _doneCount =>
      _items.where((e) => e.status != _BulkStatus.pending && e.status != _BulkStatus.processing).length;

  @override
  Widget build(BuildContext context) {
    final total = _items.length;
    final progress = total == 0 ? 0.0 : _doneCount / total;
    final linked = _items.where((e) => e.status == _BulkStatus.linked).length;
    final refreshed =
        _items.where((e) => e.status == _BulkStatus.refreshed).length;
    final skipped = _items.where((e) => e.status == _BulkStatus.skipped).length;
    final failed = _items.where((e) => e.status == _BulkStatus.failed).length;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _done
                          ? 'Готово: $_doneCount из $total'
                          : 'Обрабатываем ${_currentIndex + 1} из $total',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!_done)
                    TextButton(
                      onPressed: () => setState(() => _cancelled = true),
                      child: const Text('Остановить'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _StatChip(label: 'Привязано', value: linked, color: AppColors.accent),
                  _StatChip(label: 'Обновлено', value: refreshed, color: AppColors.primary),
                  _StatChip(label: 'Пропущено', value: skipped, color: AppColors.muted),
                  _StatChip(label: 'Ошибки', value: failed, color: AppColors.danger),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          _StatusIcon(status: it.status),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              it.product.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (it.note != null)
                            Text(
                              it.note!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _done || _cancelled
                      ? () => Navigator.pop(context)
                      : null,
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final _BulkStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _BulkStatus.pending:
        return Icon(Icons.circle_outlined, size: 18, color: AppColors.muted);
      case _BulkStatus.processing:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _BulkStatus.linked:
        return const Icon(Icons.link, size: 18, color: AppColors.accent);
      case _BulkStatus.refreshed:
        return const Icon(Icons.refresh, size: 18, color: AppColors.primary);
      case _BulkStatus.skipped:
        return Icon(Icons.remove_circle_outline, size: 18, color: AppColors.muted);
      case _BulkStatus.failed:
        return const Icon(Icons.error_outline, size: 18, color: AppColors.danger);
    }
  }
}
