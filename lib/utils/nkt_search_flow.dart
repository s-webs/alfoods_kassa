import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../widgets/nkt_variants_ui.dart';
import 'toast.dart';

/// Поиск в НКТ: штрихкод → при пустом ответе автоматически по наименованию.
class NktSearchFlow {
  NktSearchFlow._();

  static Future<NktSearchResult?> searchWithBarcodeFallback({
    required ApiService api,
    required int productId,
    required Product product,
    bool forceFresh = true,
    void Function(String message)? onStatus,
  }) async {
    try {
      var result = await api.nktSearch(
        productId,
        forceFresh: forceFresh,
        markNotFound: false,
      );

      if (result.variants.isEmpty) {
        final name = product.name.trim();
        if (name.isNotEmpty) {
          onStatus?.call('Пробуем по наименованию…');
          result = await api.nktSearch(
            productId,
            mode: NktSearchMode.byName,
            query: name,
            forceFresh: forceFresh,
            markNotFound: true,
          );
        } else {
          await api.nktSearch(
            productId,
            forceFresh: forceFresh,
            markNotFound: true,
          );
        }
      }

      return result;
    } on DioException catch (e) {
      throw NktSearchException(
        nktExtractDioError(e, fallback: 'Ошибка запроса в НКТ'),
      );
    }
  }

  static Future<String?> promptName(
    BuildContext context, {
    String initialQuery = '',
  }) async {
    final controller = TextEditingController(text: initialQuery);

    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Поиск по наименованию'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Наименование',
              hintText: 'Макаронные изделия',
            ),
            onSubmitted: (v) {
              final q = v.trim();
              if (q.isNotEmpty) Navigator.pop(ctx, q);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final q = controller.text.trim();
              if (q.isEmpty) {
                showToast(ctx, 'Введите наименование');
                return;
              }
              Navigator.pop(ctx, q);
            },
            child: const Text('Искать'),
          ),
        ],
      ),
    );
    controller.dispose();
    return query;
  }

  /// Диалог ввода NTIN — всегда с пустым полем (без подстановки NTIN/штрихкода товара).
  static Future<String?> promptNtin(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => const _NktNtinPromptDialog(),
    );
  }

  static Future<NktSearchResult?> searchByNtin({
    required ApiService api,
    required int productId,
    required String ntin,
    bool forceFresh = true,
  }) async {
    try {
      return await api.nktSearch(
        productId,
        mode: NktSearchMode.ntin,
        query: ntin,
        forceFresh: forceFresh,
        markNotFound: true,
      );
    } on DioException catch (e) {
      throw NktSearchException(
        nktExtractDioError(e, fallback: 'Ошибка запроса в НКТ'),
      );
    }
  }

  static Future<NktSearchResult?> searchByName({
    required ApiService api,
    required int productId,
    required String query,
    bool forceFresh = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return null;
    try {
      return await api.nktSearch(
        productId,
        mode: NktSearchMode.byName,
        query: q,
        forceFresh: forceFresh,
        markNotFound: true,
      );
    } on DioException catch (e) {
      throw NktSearchException(
        nktExtractDioError(e, fallback: 'Ошибка запроса в НКТ'),
      );
    }
  }
}

class _NktNtinPromptDialog extends StatefulWidget {
  const _NktNtinPromptDialog();

  @override
  State<_NktNtinPromptDialog> createState() => _NktNtinPromptDialogState();
}

class _NktNtinPromptDialogState extends State<_NktNtinPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 13) {
      showToast(context, 'NTIN должен содержать 13 цифр');
      return;
    }
    Navigator.pop(context, digits);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Поиск по NTIN'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 13,
          autofillHints: const <String>[],
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'NTIN (13 цифр)',
            hintText: 'Введите 13 цифр',
            counterText: '',
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Искать'),
        ),
      ],
    );
  }
}

class NktSearchException implements Exception {
  NktSearchException(this.message);
  final String message;

  @override
  String toString() => message;
}
