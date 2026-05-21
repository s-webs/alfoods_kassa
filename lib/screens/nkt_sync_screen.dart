import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/product_search.dart';
import '../utils/toast.dart';

enum _NktFilter { all, unlinked, linked, notFound, noBarcode }

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

  List<Product> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    return _products.where((p) {
      switch (_filter) {
        case _NktFilter.linked:
          if (!p.isLinkedToNkt) return false;
          break;
        case _NktFilter.unlinked:
          // «Без привязки» — то, с чем реально можно работать:
          // не привязано, есть штрихкод, и не помечено как «не найдено в НКТ».
          if (p.isLinkedToNkt) return false;
          if (!productHasScannableBarcode(p)) return false;
          if (p.isNktNotFound) return false;
          break;
        case _NktFilter.notFound:
          if (!p.isNktNotFound) return false;
          break;
        case _NktFilter.noBarcode:
          if (productHasScannableBarcode(p)) return false;
          break;
        case _NktFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      final ntin = (p.nktNtin ?? '').toLowerCase();
      return productMatchesQuery(p, q) || ntin.contains(q);
    }).toList();
  }

  void _toggleAllVisible(bool? value) {
    final visible = _filtered;
    setState(() {
      if (value == true) {
        for (final p in visible) {
          if (productHasScannableBarcode(p)) {
            _selectedIds.add(p.id);
          }
        }
      } else {
        for (final p in visible) {
          _selectedIds.remove(p.id);
        }
      }
    });
  }

  bool get _allVisibleSelected {
    final visible = _filtered.where(
      productHasScannableBarcode,
    );
    if (visible.isEmpty) return false;
    return visible.every((p) => _selectedIds.contains(p.id));
  }

  Future<void> _onSingleSync(Product product) async {
    if (!productHasScannableBarcode(product)) {
      showToast(context, 'У товара нет штрихкода');
      return;
    }

    NktSearchResult? result;
    String? errorMsg;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingDialog(text: 'Запрашиваем НКТ...'),
    );
    try {
      result = await widget.apiService.nktSearch(
        product.id,
        forceFresh: true,
      );
    } on DioException catch (e) {
      errorMsg = _extractError(e, fallback: 'Ошибка запроса в НКТ');
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
      // Бэкенд пометил товар как nkt_not_found=true — подтянем свежее состояние.
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
        final tried = res.barcodesTried;
        final triedText = tried.isNotEmpty
            ? tried.join(', ')
            : (product.barcode ?? product.extraBarcodes.join(', '));
        showToast(context, 'В НКТ ничего не найдено по штрихкодам: $triedText');
      }
      return;
    }

    if (!mounted) return;
    final pick = await showDialog<_VariantPickResult>(
      context: context,
      builder: (_) => _VariantPickerDialog(
        product: product,
        result: res,
        bulkMode: false,
      ),
    );
    if (pick == null || pick.ntin == null) return;

    await _linkProduct(product, pick.ntin!);
  }

  Future<void> _linkProduct(Product product, String ntin) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingDialog(text: 'Привязываем к НКТ...'),
    );
    try {
      final updated = await widget.apiService.nktLink(product.id, ntin);
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
      builder: (_) => const _LoadingDialog(text: 'Обновляем данные...'),
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
    final selected = _products
        .where((p) => _selectedIds.contains(p.id))
        .where(productHasScannableBarcode)
        .toList();

    if (selected.isEmpty) {
      showToast(context, 'Нет выбранных товаров со штрихкодом');
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
                '${notFoundCount > 0 ? ' · не найдено: $notFoundCount' : ''}'
                '${deactivatedCount > 0 ? ' · деактивировано в НКТ: $deactivatedCount' : ''}',
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
        SegmentedButton<_NktFilter>(
          showSelectedIcon: false,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.primary;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryLight;
              }
              return Colors.white;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return AppColors.surface;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const BorderSide(color: AppColors.primary, width: 1.5);
              }
              return BorderSide(
                color: AppColors.muted.withValues(alpha: 0.55),
              );
            }),
            textStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(fontWeight: FontWeight.w700);
              }
              return const TextStyle(fontWeight: FontWeight.w500);
            }),
            overlayColor: WidgetStateProperty.all(
              AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          segments: const [
            ButtonSegment(value: _NktFilter.all, label: Text('Все')),
            ButtonSegment(
              value: _NktFilter.unlinked,
              label: Text('Без привязки'),
            ),
            ButtonSegment(value: _NktFilter.linked, label: Text('Привязаны')),
            ButtonSegment(
              value: _NktFilter.notFound,
              label: Text('Не найдены'),
            ),
            ButtonSegment(
              value: _NktFilter.noBarcode,
              label: Text('Без штрихкода'),
            ),
          ],
          selected: {_filter},
          onSelectionChanged: (s) => setState(() => _filter = s.first),
        ),
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
                const SizedBox(width: 260),
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
                  onRefresh: () => _onRefresh(p),
                  onUnlink: () => _onUnlink(p),
                  onDetails: () => _onDetails(p),
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
    required this.onRefresh,
    required this.onUnlink,
    required this.onDetails,
  });

  final Product product;
  final bool isSelected;
  final ValueChanged<bool?> onSelect;
  final VoidCallback onSync;
  final VoidCallback onRefresh;
  final VoidCallback onUnlink;
  final VoidCallback onDetails;

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
              onChanged: hasBarcode ? onSelect : null,
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
              width: 260,
              child: _RowActions(
                product: product,
                onSync: onSync,
                onRefresh: onRefresh,
                onUnlink: onUnlink,
                onDetails: onDetails,
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
    required this.onSync,
    required this.onRefresh,
    required this.onUnlink,
    required this.onDetails,
  });

  final Product product;
  final VoidCallback onSync;
  final VoidCallback onRefresh;
  final VoidCallback onUnlink;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final hasBarcode = productHasScannableBarcode(product);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!product.isLinkedToNkt)
          FilledButton.icon(
            onPressed: hasBarcode ? onSync : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Найти'),
          )
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

class _VariantPickResult {
  const _VariantPickResult._({this.ntin, this.skip = false, this.cancelBulk = false});

  final String? ntin;
  final bool skip;
  final bool cancelBulk;

  factory _VariantPickResult.pick(String ntin) =>
      _VariantPickResult._(ntin: ntin);
  factory _VariantPickResult.skip() => const _VariantPickResult._(skip: true);
  factory _VariantPickResult.cancelBulk() =>
      const _VariantPickResult._(cancelBulk: true);
}

class _VariantPickerDialog extends StatefulWidget {
  const _VariantPickerDialog({
    required this.product,
    required this.result,
    this.bulkMode = false,
    this.bulkIndex,
    this.bulkTotal,
  });

  final Product product;
  final NktSearchResult result;
  final bool bulkMode;
  final int? bulkIndex;
  final int? bulkTotal;

  @override
  State<_VariantPickerDialog> createState() => _VariantPickerDialogState();
}

class _VariantPickerDialogState extends State<_VariantPickerDialog> {
  String? _picked;

  @override
  void initState() {
    super.initState();
    if (widget.result.variants.length == 1) {
      _picked = widget.result.variants.first.ntinCode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final variants = widget.result.variants;
    final single = variants.length == 1;

    final bulkHint = widget.bulkMode && widget.bulkTotal != null
        ? ' (товар ${widget.bulkIndex! + 1} из ${widget.bulkTotal})'
        : '';

    return AlertDialog(
      title: Text(
        (single ? 'Найден товар в НКТ' : 'Выберите вариант') + bulkHint,
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Локальный товар: ${widget.product.name}\n'
              'Штрихкод: ${widget.product.barcode ?? widget.result.barcode ?? '—'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (widget.result.cached)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Данные из кэша',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: variants.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (_, i) {
                  final v = variants[i];
                  final selected = _picked == v.ntinCode;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _picked = v.ntinCode),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.muted.withValues(alpha: 0.4),
                          width: selected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: selected
                            ? AppColors.primaryLight.withValues(alpha: 0.4)
                            : null,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Radio<String>(
                            value: v.ntinCode ?? '',
                            groupValue: _picked ?? '',
                            onChanged: (val) => setState(() => _picked = val),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.nameRu ?? v.nameKk ?? '(без названия)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (v.nameKk != null &&
                                    v.nameKk != v.nameRu &&
                                    v.nameKk!.isNotEmpty)
                                  Text(
                                    v.nameKk!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'NTIN: ${v.ntinCode ?? '—'}'
                                  '${v.gtin != null ? '   GTIN: ${v.gtin}' : ''}'
                                  '${v.measureName != null ? '   Ед: ${v.measureName}' : ''}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    if (v.isMarkedeac == true)
                                      _ChipBadge(
                                        label: 'Маркировка',
                                        color: AppColors.accent,
                                        icon: Icons.qr_code_2,
                                      ),
                                    if (v.isSocial == true)
                                      _ChipBadge(
                                        label: 'СЗПТ',
                                        color: AppColors.primary,
                                      ),
                                    if (v.isDeactivated == true)
                                      _ChipBadge(
                                        label: 'Деактивирован',
                                        color: AppColors.danger,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: widget.bulkMode
          ? [
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _VariantPickResult.cancelBulk(),
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Остановить'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _VariantPickResult.skip()),
                child: const Text('Пропустить'),
              ),
              FilledButton(
                onPressed: (_picked != null && _picked!.isNotEmpty)
                    ? () => Navigator.pop(
                        context,
                        _VariantPickResult.pick(_picked!),
                      )
                    : null,
                child: const Text('Привязать и далее'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: (_picked != null && _picked!.isNotEmpty)
                    ? () => Navigator.pop(
                        context,
                        _VariantPickResult.pick(_picked!),
                      )
                    : null,
                child: const Text('Привязать'),
              ),
            ],
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Text(text),
          ],
        ),
      ),
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
            final res = await widget.apiService.nktSearch(
              item.product.id,
              forceFresh: true,
            );
            if (res.variants.isEmpty) {
              item.status = _BulkStatus.skipped;
              item.note = 'Нет в НКТ';
            } else if (res.variants.length > 1) {
              // Несколько вариантов — приостанавливаем цикл, спрашиваем пользователя.
              if (!mounted) break;
              final pick = await showDialog<_VariantPickResult>(
                context: context,
                barrierDismissible: false,
                builder: (_) => _VariantPickerDialog(
                  product: item.product,
                  result: res,
                  bulkMode: true,
                  bulkIndex: i,
                  bulkTotal: _items.length,
                ),
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
                final updated = await widget.apiService.nktLink(
                  item.product.id,
                  pick.ntin!,
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
