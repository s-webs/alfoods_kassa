import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Акцентная рамка для toast о заказах (согласовано с подсветкой меню).
const Color _orderToastAccent = Color(0xFF7C6FAD);

/// Показывает toast-уведомление в правом верхнем углу.
/// По умолчанию закрывается через 2 секунды.
void showToast(
  BuildContext context,
  String message, {
  Duration? duration,
  bool orderAccent = false,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  final hideAfter = duration ?? const Duration(seconds: 2);

  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: 16,
      right: 16,
      left: MediaQuery.of(context).size.width * 0.3,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: orderAccent
                    ? Border.all(
                        color: _orderToastAccent.withValues(alpha: 0.9),
                        width: 2,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);

  Future.delayed(hideAfter, () {
    try {
      entry.remove();
    } catch (_) {}
  });
}
