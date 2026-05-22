import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/nkt_request_ui.dart';
import '../utils/toast.dart';
import 'nkt_variants_ui.dart';

/// Lifecycle actions for NKT portal product request (status, moderation, publish).
class NktRequestActionsPanel extends StatelessWidget {
  const NktRequestActionsPanel({
    super.key,
    required this.api,
    required this.product,
    required this.onProductUpdated,
    this.compact = false,
    this.lifecycleOnly = false,
    this.onOpenRequestTab,
  });

  final ApiService api;
  final Product product;
  final ValueChanged<Product> onProductUpdated;
  final bool compact;
  /// Only status chips and lifecycle buttons (form is on the request tab).
  final bool lifecycleOnly;
  final VoidCallback? onOpenRequestTab;

  Future<void> _run(
    BuildContext context,
    String loadingText,
    Future<Product> Function() action, {
    String? successMessage,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(loadingText)),
          ],
        ),
      ),
    );
    try {
      final updated = await action();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      onProductUpdated(updated);
      if (context.mounted && successMessage != null) {
        showToast(context, successMessage);
      }
    } on DioException catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        showToast(
          context,
          nktExtractDioError(e, fallback: 'Ошибка операции'),
        );
      }
    } catch (_) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        showToast(context, 'Ошибка операции');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (product.isLinkedToNkt && !product.hasNktRequest && lifecycleOnly) {
      return const SizedBox.shrink();
    }

    if (!lifecycleOnly &&
        !product.hasNktRequest &&
        nktCanCreateRequest(product)) {
      if (compact) {
        return OutlinedButton(
          onPressed: onOpenRequestTab,
          child: const Text('Заявка', style: TextStyle(fontSize: 12)),
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: onOpenRequestTab,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Создать заявку в НКТ'),
        ),
      );
    }

    if (!product.hasNktRequest) return const SizedBox.shrink();

    final statusColor = nktRequestStatusColor(product.nktRequestStatus);
    final chips = <Widget>[
      _ChipBadge(
        label: 'Заявка: ${product.nktRequestStatusDisplay}',
        color: statusColor,
        icon: Icons.assignment_outlined,
      ),
      if (product.nktRequestUpdatedAt != null)
        Text(
          'обновлено ${_fmt(product.nktRequestUpdatedAt!)}',
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
    ];

    final actions = <Widget>[
      IconButton(
        tooltip: 'Обновить статус',
        onPressed: () => _run(
          context,
          'Обновляем статус...',
          () => api.nktRefreshRequestStatus(product.id),
          successMessage: 'Статус обновлён',
        ),
        icon: const Icon(Icons.sync, size: 20),
      ),
      if (nktCanSubmitModeration(product))
        TextButton(
          onPressed: () => _run(
            context,
            'Отправляем на модерацию...',
            () => api.nktSubmitRequestModeration(product.id),
            successMessage: 'Отправлено на модерацию',
          ),
          child: const Text('На модерацию'),
        ),
      if (nktCanPublishRequest(product))
        FilledButton(
          onPressed: () => _run(
            context,
            'Публикуем...',
            () => api.nktPublishRequest(product.id),
            successMessage: 'Публикация запущена',
          ),
          child: const Text('Опубликовать'),
        ),
      if (nktCanCancelRequest(product))
        TextButton(
          onPressed: () => _confirmCancel(context),
          child: const Text('Отозвать'),
        ),
      if (!lifecycleOnly && nktCanEditRequest(product))
        TextButton(
          onPressed: onOpenRequestTab,
          child: const Text('Изменить'),
        ),
    ];

    if (compact) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!lifecycleOnly) ...[
            Flexible(child: chips.first),
          ],
          PopupMenuButton<String>(
            tooltip: 'Действия с заявкой',
            onSelected: (v) => _onMenu(context, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Text('Статус')),
              if (nktCanSubmitModeration(product))
                const PopupMenuItem(
                  value: 'moderation',
                  child: Text('На модерацию'),
                ),
              if (nktCanPublishRequest(product))
                const PopupMenuItem(
                  value: 'publish',
                  child: Text('Опубликовать'),
                ),
              if (nktCanCancelRequest(product))
                const PopupMenuItem(value: 'cancel', child: Text('Отозвать')),
              if (!lifecycleOnly && nktCanEditRequest(product))
                const PopupMenuItem(value: 'edit', child: Text('Изменить')),
            ],
            child: const Icon(Icons.more_vert, size: 20),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 4, children: chips),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: actions),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    switch (value) {
      case 'refresh':
        await _run(
          context,
          'Обновляем статус...',
          () => api.nktRefreshRequestStatus(product.id),
          successMessage: 'Статус обновлён',
        );
      case 'moderation':
        await _run(
          context,
          'Отправляем на модерацию...',
          () => api.nktSubmitRequestModeration(product.id),
          successMessage: 'Отправлено на модерацию',
        );
      case 'publish':
        await _run(
          context,
          'Публикуем...',
          () => api.nktPublishRequest(product.id),
          successMessage: 'Публикация запущена',
        );
      case 'cancel':
        await _confirmCancel(context);
      case 'edit':
        onOpenRequestTab?.call();
    }
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отозвать заявку?'),
        content: const Text(
          'Заявка будет отозвана в портале НКТ (статус «Отозвано»).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      'Отзываем заявку...',
      () => api.nktCancelRequest(product.id),
      successMessage: 'Заявка отозвана',
    );
  }

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
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
