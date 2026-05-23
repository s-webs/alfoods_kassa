#include "custom_plugin_registrant.h"

#include "pdf_printer_plugin.h"
#include "receipt_native_printer_plugin.h"

void RegisterCustomPlugins(flutter::PluginRegistry* registry) {
  PdfPrinterPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PdfPrinterPlugin"));
  ReceiptNativePrinterPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ReceiptNativePrinterPlugin"));
}
