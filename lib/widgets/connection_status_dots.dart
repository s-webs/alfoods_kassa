import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/connection_link_status.dart';
import '../state/connectivity_state.dart';

/// Индикаторы связи в шапке: Сервер и ОФД (WebKassa).
class ConnectionStatusDots extends StatelessWidget {
  const ConnectionStatusDots({super.key});

  static Color _colorFor(ConnectionLinkStatus status) {
    switch (status) {
      case ConnectionLinkStatus.connected:
        return const Color(0xFF22C55E);
      case ConnectionLinkStatus.connecting:
        return const Color(0xFFF59E0B);
      case ConnectionLinkStatus.disconnected:
        return AppColors.danger;
    }
  }

  static String _labelFor(ConnectionLinkStatus status) {
    switch (status) {
      case ConnectionLinkStatus.connected:
        return 'Связь есть';
      case ConnectionLinkStatus.connecting:
        return 'Подключение…';
      case ConnectionLinkStatus.disconnected:
        return 'Нет связи';
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ConnectivityStateScope.of(context);

    return ListenableBuilder(
      listenable: connectivity,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusIndicator(
              label: 'Сервер',
              color: _colorFor(connectivity.backendStatus),
              statusLabel: _labelFor(connectivity.backendStatus),
            ),
            const SizedBox(width: 20),
            _StatusIndicator(
              label: 'ОФД',
              color: _colorFor(connectivity.webkassaStatus),
              statusLabel: _labelFor(connectivity.webkassaStatus),
            ),
          ],
        );
      },
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({
    required this.label,
    required this.color,
    required this.statusLabel,
  });

  final String label;
  final Color color;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final captionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.surface,
          fontWeight: FontWeight.w500,
        );

    return Tooltip(
      message: '$label: $statusLabel',
      child: Semantics(
        label: '$label, $statusLabel',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: captionStyle),
          ],
        ),
      ),
    );
  }
}
