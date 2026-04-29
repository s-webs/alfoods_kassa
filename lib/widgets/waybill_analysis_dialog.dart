import 'package:flutter/material.dart';
import 'dart:math';

import '../core/theme.dart';
import '../models/product.dart';
import '../models/waybill_analysis.dart';
import '../services/api_service.dart';

// ---------------------------------------------------------------------------
// Resolution model
// ---------------------------------------------------------------------------

enum ItemMatchStatus { matched, pending }

class ResolvedWaybillItem {
  final WaybillAnalysisItem aiItem;

  // Editable import values (pre-filled from AI, user may override)
  double? importQuantity;
  double? importPrice;

  Product? product;
  bool selected;
  ItemMatchStatus status;

  ResolvedWaybillItem({
    required this.aiItem,
    this.product,
    bool? selected,
  })  : importQuantity = aiItem.quantity,
        importPrice = aiItem.price,
        selected = selected ?? product != null,
        status =
            product != null ? ItemMatchStatus.matched : ItemMatchStatus.pending;

  void assignProduct(Product p) {
    product = p;
    selected = true;
    status = ItemMatchStatus.matched;
  }

  void clearProduct() {
    product = null;
    selected = false;
    status = ItemMatchStatus.pending;
  }

  bool get isMatched => product != null;
}

// ---------------------------------------------------------------------------
// Fuzzy name search — improved algorithm
// ---------------------------------------------------------------------------

/// Normalise: lowercase, strip quotes/punctuation, collapse spaces.
/// Uses \p{L} / \p{N} (Unicode properties) to keep any letter/digit safely.
String _normaliseName(String s) => s
    .toLowerCase()
    // Remove quote characters and brackets
    .replaceAll(RegExp(r'[(){}\[\]]'), '')
    .replaceAll(RegExp(r'["«»]'), '')
    // Replace anything that's not a Unicode letter, digit or space with a space
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Words that should not affect matching score.
final _stopWords = <String>{
  'из', 'в', 'с', 'и', 'по', 'для', 'на', 'от', 'до', 'без',
  'рецепт', 'рецепту', 'вкус', 'вкуса', 'натур', 'натуральный',
  'натуральная', 'тм', 'тмо', 'тов', 'шт', 'упак', 'пакет',
};

/// Returns true for pure measurement tokens: "300г", "500мл", "1/4", plain numbers.
bool _isMeasurement(String w) =>
    RegExp(r'^\d+$').hasMatch(w) ||
    RegExp(r'^\d+[\/]\d+$').hasMatch(w) ||
    RegExp(r'^\d+[a-zа-яё]+$', unicode: true).hasMatch(w) ||
    RegExp(r'^[a-zа-яё]+$', unicode: true).hasMatch(w) && w.length <= 3;

/// Extract meaningful tokens from a product name.
List<String> _tokenise(String name) {
  return _normaliseName(name)
      .split(RegExp(r'[\s\-,;:]+'))
      .where((w) => w.length > 1 && !_stopWords.contains(w) && !_isMeasurement(w))
      .toList();
}

/// Fuzzy product search.
///
/// Scoring:
/// - Each AI token that appears in the product name adds to the hit count.
/// - Longer tokens (> 4 chars — brand names, distinctive words) are worth 2×.
/// - If all significant tokens match → near-perfect score.
/// - Minimum score threshold prevents noisy matches.
List<Product> findSuggestions(
  String? aiName,
  List<Product> allProducts, {
  int max = 6,
}) {
  if (aiName == null || aiName.isEmpty) return [];

  final aiTokens = _tokenise(aiName);
  if (aiTokens.isEmpty) return [];

  // Pre-weight tokens: long/unique words count more
  final weights = {for (final t in aiTokens) t: t.length > 4 ? 2.0 : 1.0};
  final maxScore =
      aiTokens.fold(0.0, (sum, t) => sum + (weights[t] ?? 1.0));

  final scored = <({Product product, double score})>[];

  for (final p in allProducts) {
    final pNorm = _normaliseName(p.name);

    // Fast path: product name contains the whole AI name → top score
    if (pNorm.contains(_normaliseName(aiName))) {
      scored.add((product: p, score: 1.5));
      continue;
    }

    final pTokens = _tokenise(p.name);
    double score = 0;

    for (final t in aiTokens) {
      // Match if the product name contains this token as a substring
      final w = weights[t] ?? 1.0;
      if (pNorm.contains(t)) {
        score += w;
      } else {
        // Partial: product token starts with AI token (prefix match)
        final prefixMatch = pTokens.any((pt) => pt.startsWith(t) && t.length >= 3);
        if (prefixMatch) score += w * 0.5;
      }
    }

    final normScore = score / maxScore;

    // Filter thresholds:
    // – If the AI name has significant long tokens, require ≥1 of them to match.
    // – Overall normalised score must be ≥ 0.25.
    final longTokens = aiTokens.where((t) => t.length > 4).toList();
    final hasLongMatch = longTokens.isEmpty ||
        longTokens.any((t) => pNorm.contains(t));

    if (normScore >= 0.25 && hasLongMatch) {
      scored.add((product: p, score: normScore));
    }
  }

  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(max).map((e) => e.product).toList();
}

// ---------------------------------------------------------------------------
// Dialog
// ---------------------------------------------------------------------------

class WaybillAnalysisDialog extends StatefulWidget {
  const WaybillAnalysisDialog({
    super.key,
    required this.result,
    required this.resolvedItems,
    required this.allProducts,
    required this.apiService,
  });

  final WaybillAnalysisResult result;
  final List<ResolvedWaybillItem> resolvedItems;
  final List<Product> allProducts;
  final ApiService apiService;

  @override
  State<WaybillAnalysisDialog> createState() => _WaybillAnalysisDialogState();
}

class _WaybillAnalysisDialogState extends State<WaybillAnalysisDialog> {
  late final List<ResolvedWaybillItem> _items;
  // Per-item search controllers and filtered suggestion lists
  late final List<TextEditingController> _searchCtrl;
  late final List<List<Product>> _filteredSuggestions;

  @override
  void initState() {
    super.initState();
    _items = widget.resolvedItems;

    _searchCtrl = List.generate(
      _items.length,
      (i) => TextEditingController(text: _items[i].aiItem.name ?? ''),
    );

    _filteredSuggestions = List.generate(_items.length, (i) {
      final item = _items[i];
      if (item.isMatched) return [];
      return findSuggestions(item.aiItem.name, widget.allProducts);
    });
  }

  @override
  void dispose() {
    for (final c in _searchCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateSearch(int index, String q) {
    setState(() {
      _filteredSuggestions[index] = q.trim().isEmpty
          ? findSuggestions(_items[index].aiItem.name, widget.allProducts)
          : widget.allProducts
              .where((p) => p.name.toLowerCase().contains(q.toLowerCase()))
              .take(6)
              .toList();
    });
  }

  /// Assign product + persist mapping to backend.
  Future<void> _assignProduct(int index, Product product) async {
    setState(() => _items[index].assignProduct(product));
    final aiName = _items[index].aiItem.name;
    if (aiName != null && aiName.isNotEmpty) {
      // Fire-and-forget — don't block the UI
      widget.apiService
          .saveWaybillMapping(aiName, product.id)
          .catchError((_) {});
    }
  }

  int get _selectedCount =>
      _items.where((e) => e.selected && e.isMatched).length;

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  Color _confidenceColor(String c) => switch (c) {
        'high' => const Color(0xFF4CAF50),
        'medium' => const Color(0xFFFF9800),
        _ => AppColors.danger,
      };

  String _confidenceLabel(String c) => switch (c) {
        'high' => 'Уверенно',
        'medium' => 'Средне',
        _ => 'Низкая',
      };

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
          maxWidth: 620,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(result),
            if (result.validation.warnings.isNotEmpty)
              _buildWarnings(result.validation.warnings),
            if (result.supplier != null || result.totals.totalAmount != null)
              _buildMeta(result),
            Expanded(child: _buildList()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(WaybillAnalysisResult r) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Анализ накладной (ИИ)',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  if (r.invoiceNumber != null || r.invoiceDate != null)
                    Text(
                      [
                        if (r.invoiceNumber != null) '№${r.invoiceNumber}',
                        if (r.invoiceDate != null) r.invoiceDate!,
                      ].join('  '),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ],
        ),
      );

  Widget _buildWarnings(List<String> warnings) => Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFFF3CD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.warning_amber_rounded,
                  size: 15, color: Color(0xFF856404)),
              SizedBox(width: 6),
              Text('Предупреждения ИИ',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Color(0xFF856404))),
            ]),
            const SizedBox(height: 4),
            ...warnings.map((w) => Text('• $w',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF856404)))),
          ],
        ),
      );

  Widget _buildMeta(WaybillAnalysisResult r) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.primaryLight,
        child: Row(
          children: [
            if (r.supplier != null) ...[
              const Icon(Icons.business_outlined,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(r.supplier!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
            if (r.totals.totalAmount != null)
              Text(
                'Итого: ${r.totals.totalAmount!.toStringAsFixed(2)} ${r.currency}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600),
              ),
          ],
        ),
      );

  Widget _buildList() {
    if (_items.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('ИИ не распознал ни одного товара.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54))));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _items.length,
      separatorBuilder: (context, i) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, i) => _buildItemCard(i),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final ai = item.aiItem;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: AI name + confidence + edit import values ─────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(ai.name ?? '—',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              _confidenceBadge(ai.confidence),
            ],
          ),

          // ── Row 2: import values (qty / price) with edit ─────────────────
          if (item.importQuantity != null || item.importPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (item.importQuantity != null)
                    _editableChip(
                      label:
                          '${_fmtNum(item.importQuantity!)} ${ai.unit ?? 'шт'}',
                      onEdit: () => _editImportValues(index),
                    ),
                  if (item.importPrice != null)
                    _editableChip(
                      label:
                          '${_fmtNum(item.importPrice!)} ${widget.result.currency}',
                      onEdit: () => _editImportValues(index),
                    ),
                  if (item.importQuantity != null && item.importPrice != null)
                    _chip(
                      '= ${_fmtNum(item.importQuantity! * item.importPrice!)} ${widget.result.currency}',
                    ),
                ],
              ),
            ),

          if (ai.notes != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(ai.notes!,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      fontStyle: FontStyle.italic)),
            ),

          const SizedBox(height: 10),

          // ── Match block ───────────────────────────────────────────────────
          if (item.status == ItemMatchStatus.matched)
            _buildMatchedRow(index)
          else
            _buildSearchBlock(index),
        ],
      ),
    );
  }

  // ── Matched row ──────────────────────────────────────────────────────────

  Widget _buildMatchedRow(int index) {
    final item = _items[index];
    return Row(
      children: [
        Checkbox(
          value: item.selected,
          onChanged: (v) => setState(() => item.selected = v ?? false),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.product!.name,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w500)),
              Text(
                'Закупочная: ${item.product!.purchasePrice.toStringAsFixed(2)} ₸  •  ${item.product!.unit}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
        // Edit product in DB
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18,
              color: Colors.black45),
          tooltip: 'Редактировать товар в базе',
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(),
          onPressed: () => _editProductInDb(index),
        ),
        // Change match
        TextButton(
          onPressed: () => setState(() {
            _items[index].clearProduct();
            _searchCtrl[index].text = _items[index].aiItem.name ?? '';
            _filteredSuggestions[index] = findSuggestions(
                _items[index].aiItem.name, widget.allProducts);
          }),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black45,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Изменить', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── Search + suggestions block ───────────────────────────────────────────

  Widget _buildSearchBlock(int index) {
    final suggestions = _filteredSuggestions[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field — first row
        TextField(
          controller: _searchCtrl[index],
          onChanged: (q) => _updateSearch(index, q),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Поиск товара...',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            suffixIcon: _searchCtrl[index].text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      _searchCtrl[index].clear();
                      _updateSearch(index, '');
                    },
                  )
                : null,
          ),
        ),

        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...suggestions.map(
            (p) => _buildSuggestionRow(index, p),
          ),
        ] else ...[
          const SizedBox(height: 8),
          const Text('Совпадений не найдено',
              style: TextStyle(fontSize: 12, color: Colors.black38)),
        ],

        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _quickCreateProduct(index),
          icon: const Icon(Icons.add_circle_outline, size: 15),
          label: const Text('Создать новый товар',
              style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionRow(int index, Product p) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                p.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${p.purchasePrice.toStringAsFixed(0)} ₸',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 28,
              child: FilledButton(
                onPressed: () => _assignProduct(index, p),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(fontSize: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Выбрать'),
              ),
            ),
          ],
        ),
      );

  // ── Footer ───────────────────────────────────────────────────────────────

  Widget _buildFooter() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('Выбрано: $_selectedCount из ${_items.length}',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Отмена'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _selectedCount == 0
                  ? null
                  : () => Navigator.of(context).pop(
                        _items
                            .where((e) => e.selected && e.isMatched)
                            .toList(),
                      ),
              icon: const Icon(Icons.download_done_rounded, size: 18),
              label: Text('Импортировать ($_selectedCount)'),
            ),
          ],
        ),
      );

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _confidenceBadge(String c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _confidenceColor(c).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(_confidenceLabel(c),
            style: TextStyle(
                fontSize: 10,
                color: _confidenceColor(c),
                fontWeight: FontWeight.w600)),
      );

  Widget _chip(String text) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text.trim(),
            style: const TextStyle(fontSize: 11, color: AppColors.primary)),
      );

  Widget _editableChip({required String label, required VoidCallback onEdit}) =>
      GestureDetector(
        onTap: onEdit,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.trim(),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.primary)),
              const SizedBox(width: 3),
              Icon(Icons.edit, size: 10,
                  color: AppColors.primary.withValues(alpha: 0.6)),
            ],
          ),
        ),
      );

  // ── Dialogs ──────────────────────────────────────────────────────────────

  /// Edit the import values (qty / price) that will be used when adding to receipt.
  Future<void> _editImportValues(int index) async {
    final item = _items[index];
    final ai = item.aiItem;

    final qtyCtrl = TextEditingController(
      text: item.importQuantity != null
          ? _fmtNum(item.importQuantity!)
          : '',
    );
    final priceCtrl = TextEditingController(
      text: item.importPrice != null
          ? _fmtNum(item.importPrice!)
          : '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          ai.name ?? 'Редактировать',
          style: const TextStyle(fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Значения, которые будут добавлены в поступление:',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Количество',
                suffixText: ai.unit ?? 'шт',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Закупочная цена',
                suffixText: '₸',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              setState(() {
                final q = double.tryParse(
                    qtyCtrl.text.replaceAll(',', '.').trim());
                final p = double.tryParse(
                    priceCtrl.text.replaceAll(',', '.').trim());
                if (q != null) item.importQuantity = q;
                if (p != null) item.importPrice = p;
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    qtyCtrl.dispose();
    priceCtrl.dispose();
  }

  /// Edit the matched product's name and purchase price in the database.
  Future<void> _editProductInDb(int index) async {
    final item = _items[index];
    if (item.product == null) return;

    final nameCtrl = TextEditingController(text: item.product!.name);
    final priceCtrl = TextEditingController(
      text: item.product!.purchasePrice.toStringAsFixed(2),
    );
    final salePriceCtrl = TextEditingController(
      text: item.product!.price.toStringAsFixed(2),
    );
    bool isSaving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Редактировать товар в базе'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 13)),
                  ),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Закупочная',
                        suffixText: '₸',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: salePriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Цена продажи',
                        suffixText: '₸',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(ctx).pop(),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setLocalState(() => error = 'Введите название');
                        return;
                      }
                      final pp = double.tryParse(
                              priceCtrl.text.replaceAll(',', '.')) ??
                          item.product!.purchasePrice;
                      final sp = double.tryParse(salePriceCtrl.text
                              .replaceAll(',', '.')) ??
                          item.product!.price;

                      setLocalState(() => isSaving = true);
                      try {
                        final updated =
                            await widget.apiService.updateProduct(
                          item.product!.id,
                          {
                            'name': name,
                            'purchase_price': pp,
                            'price': sp,
                          },
                        );
                        if (ctx.mounted) {
                          setState(() => item.product = updated);
                          Navigator.of(ctx).pop();
                        }
                      } catch (e) {
                        setLocalState(() {
                          isSaving = false;
                          error = 'Ошибка: $e';
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    priceCtrl.dispose();
    salePriceCtrl.dispose();
  }

  /// Quick product creation with pre-filled AI data.
  Future<void> _quickCreateProduct(int index) async {
    final ai = _items[index].aiItem;
    final product = await showDialog<Product>(
      context: context,
      builder: (_) => _QuickCreateProductDialog(
        apiService: widget.apiService,
        aiItem: ai,
      ),
    );
    if (product != null) {
      await _assignProduct(index, product);
    }
  }
}

// ---------------------------------------------------------------------------
// Quick product creation dialog
// ---------------------------------------------------------------------------

class _QuickCreateProductDialog extends StatefulWidget {
  const _QuickCreateProductDialog({
    required this.apiService,
    required this.aiItem,
  });

  final ApiService apiService;
  final WaybillAnalysisItem aiItem;

  @override
  State<_QuickCreateProductDialog> createState() =>
      _QuickCreateProductDialogState();
}

class _QuickCreateProductDialogState
    extends State<_QuickCreateProductDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _salePriceCtrl;
  String _unit = 'pcs';
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ai = widget.aiItem;
    _nameCtrl = TextEditingController(text: ai.name ?? '');
    final priceStr =
        ai.price != null ? ai.price!.toStringAsFixed(2) : '';
    _barcodeCtrl = TextEditingController(text: ai.barcode ?? '');
    _purchasePriceCtrl = TextEditingController(text: priceStr);
    _salePriceCtrl = TextEditingController(text: priceStr);

    if (ai.unit != null) {
      final u = ai.unit!.toLowerCase();
      if (u.contains('кг') ||
          u.contains('kg') ||
          u.contains('л') ||
          u.startsWith('l')) {
        _unit = 'kg';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _salePriceCtrl.dispose();
    super.dispose();
  }

  String _generateEan13() {
    final rnd = Random();
    final digits = List<int>.generate(12, (_) => rnd.nextInt(10));
    final sumOdd = digits
        .asMap()
        .entries
        .where((e) => e.key.isEven)
        .fold<int>(0, (s, e) => s + e.value);
    final sumEven = digits
        .asMap()
        .entries
        .where((e) => e.key.isOdd)
        .fold<int>(0, (s, e) => s + e.value);
    final check = (10 - ((sumOdd + sumEven * 3) % 10)) % 10;
    return '${digits.join()}$check';
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название товара');
      return;
    }
    final pp = double.tryParse(
            _purchasePriceCtrl.text.replaceAll(',', '.').trim()) ??
        0.0;
    final sp = double.tryParse(
            _salePriceCtrl.text.replaceAll(',', '.').trim()) ??
        0.0;
    final barcode = _barcodeCtrl.text.trim();

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final product = await widget.apiService.createProduct({
        'name': name,
        'barcode': barcode.isEmpty ? null : barcode,
        'price': sp,
        'purchase_price': pp,
        'unit': _unit,
        'is_active': true,
      });
      if (mounted) Navigator.of(context).pop(product);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'Ошибка создания: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать новый товар'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: const TextStyle(
                        color: AppColors.danger, fontSize: 13)),
              ),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Штрихкод',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _barcodeCtrl.text = _generateEan13();
                    });
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Сгенерировать'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _purchasePriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Закупочная',
                    suffixText: '₸',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _salePriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Цена продажи',
                    suffixText: '₸',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _unit,
              decoration: const InputDecoration(
                labelText: 'Единица',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'pcs', child: Text('шт')),
                DropdownMenuItem(value: 'kg', child: Text('кг')),
              ],
              onChanged: (v) => setState(() => _unit = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _isSaving
                ? null
                : () => Navigator.of(context).pop(null),
            child: const Text('Отмена')),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Создать'),
        ),
      ],
    );
  }
}
