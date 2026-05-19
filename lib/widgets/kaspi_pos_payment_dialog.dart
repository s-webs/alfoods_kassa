import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/kaspi_pos_service.dart';

typedef KaspiPosPollCallback = Future<KaspiPosProcessStatus> Function(
  String processId,
  void Function(KaspiPosProcessStatus status) onUpdate,
);

typedef KaspiPosActualizeCallback = Future<KaspiPosProcessStatus> Function(
  String processId,
);

class KaspiPosPaymentDialog extends StatefulWidget {
  const KaspiPosPaymentDialog({
    super.key,
    required this.amount,
    required this.processId,
    required this.poll,
    this.actualize,
    this.title = 'Оплата на терминале',
  });

  final int amount;
  final String processId;
  final KaspiPosPollCallback poll;
  final KaspiPosActualizeCallback? actualize;
  final String title;

  static Future<KaspiPosProcessStatus?> show({
    required BuildContext context,
    required int amount,
    required String processId,
    required KaspiPosPollCallback poll,
    KaspiPosActualizeCallback? actualize,
    String title = 'Оплата на терминале',
  }) {
    return showDialog<KaspiPosProcessStatus>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => KaspiPosPaymentDialog(
        amount: amount,
        processId: processId,
        poll: poll,
        actualize: actualize,
        title: title,
      ),
    );
  }

  @override
  State<KaspiPosPaymentDialog> createState() => _KaspiPosPaymentDialogState();
}

class _KaspiPosPaymentDialogState extends State<KaspiPosPaymentDialog> {
  KaspiPosProcessStatus? _status;
  String? _error;
  bool _isPolling = true;
  bool _isActualizing = false;

  @override
  void initState() {
    super.initState();
    _runPoll();
  }

  Future<void> _runPoll() async {
    setState(() {
      _isPolling = true;
      _error = null;
    });
    try {
      final result = await widget.poll(
        widget.processId,
        (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on KaspiPosException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isPolling = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isPolling = false;
      });
    }
  }

  Future<void> _onActualize() async {
    if (widget.actualize == null || _isActualizing) return;
    setState(() {
      _isActualizing = true;
      _error = null;
    });
    try {
      final result = await widget.actualize!(widget.processId);
      if (!mounted) return;
      if (result.isFinished) {
        Navigator.of(context).pop(result);
        return;
      }
      setState(() {
        _status = result;
        _isActualizing = false;
      });
    } on KaspiPosException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isActualizing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isActualizing = false;
      });
    }
  }

  String _subStatusLabel(String? sub) {
    if (sub == null || sub.isEmpty) return 'Ожидание клиента на терминале…';
    const labels = {
      'Initialize': 'Инициализация…',
      'WaitUser': 'Ожидание: QR или карта',
      'WaitForQrConfirmation': 'Подтверждение QR…',
      'ProcessingCard': 'Обработка карты…',
      'WaitForPinCode': 'Ввод PIN…',
      'ProcessRefund': 'Выполнение возврата…',
      'QrTransactionSuccess': 'QR: успех',
      'QrTransactionFailure': 'QR: ошибка',
      'CardTransactionSuccess': 'Карта: успех',
      'CardTransactionFailure': 'Карта: ошибка',
      'ProcessCancelled': 'Отменено',
    };
    return labels[sub] ?? sub;
  }

  @override
  Widget build(BuildContext context) {
    final showActualize =
        _status?.status == 'unknown' && widget.actualize != null;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сумма: ${widget.amount} ₸',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
              const SizedBox(height: 8),
            ],
            if (_isPolling && _error == null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _subStatusLabel(_status?.subStatus),
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
            if (_status?.message != null && _status!.message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _status!.message!,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (showActualize) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isActualizing ? null : _onActualize,
                child: _isActualizing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Актуализировать статус'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isPolling || _error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        if (_error != null)
          FilledButton(
            onPressed: _runPoll,
            child: const Text('Повторить'),
          ),
      ],
    );
  }
}
