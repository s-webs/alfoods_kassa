import '../core/storage.dart';
import '../models/fiscal_receipt.dart';
import 'receipt_printer_service.dart';

/// Печать фискального чека WebKassa на термопринтер (без браузера).
class WebkassaReceiptPrintService {
  WebkassaReceiptPrintService(this._storage);

  final Storage _storage;

  Future<bool> printFiscalReceipt(FiscalReceipt? fiscal) async {
    if (fiscal == null || fiscal.printLines.isEmpty) {
      return false;
    }

    await ReceiptPrinterService.printWebkassaReceipt(
      lines: fiscal.printLines,
      printerName: _storage.receiptPrinterName,
      printMode: _storage.receiptPrintMode,
      rawEncoding: _storage.receiptRawEncoding,
      xprinterCyrillicPreamble: _storage.receiptRawXprinterPreamble,
    );

    return true;
  }
}
