import 'package:flutter/material.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../services/z_report_formatter.dart';
import '../services/z_report_print_service.dart';

/// Просмотр и печать Z-отчёта WebKassa.
class ZReportDialog extends StatelessWidget {
  const ZReportDialog({
    super.key,
    required this.zReport,
    this.zReportAt,
    this.storage,
  });

  final Map<String, dynamic> zReport;
  final DateTime? zReportAt;
  final Storage? storage;

  static bool hasViewableData(Map<String, dynamic>? zReport) {
    return zReport != null && zReport.isNotEmpty;
  }

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> zReport,
    DateTime? zReportAt,
    Storage? storage,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ZReportDialog(
        zReport: zReport,
        zReportAt: zReportAt,
        storage: storage,
      ),
    );
  }

  List<({String label, String value})> _rows() {
    final lines = ZReportFormatter.formatLines(zReport, zReportAt: zReportAt);
    final rows = <({String label, String value})>[];
    for (final line in lines.skip(1)) {
      if (line.startsWith('---')) {
        rows.add((label: line, value: ''));
        continue;
      }
      final colon = line.indexOf(': ');
      if (colon > 0) {
        rows.add((
          label: line.substring(0, colon),
          value: line.substring(colon + 2),
        ));
      } else {
        rows.add((label: '', value: line));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();

    return AlertDialog(
      title: const Text('Z-отчёт WebKassa'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...rows.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: r.value.isEmpty
                      ? Text(
                          r.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 150,
                              child: Text(
                                r.label,
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                r.value,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (storage != null)
          TextButton.icon(
            onPressed: () async {
              await ZReportPrintService(storage!).print(
                context,
                zReport: zReport,
                zReportAt: zReportAt,
              );
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Печать'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
