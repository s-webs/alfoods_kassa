#include "custom_plugin_registrant.h"

#include "pdf_printer_plugin.h"

void RegisterCustomPlugins(flutter::PluginRegistry* registry) {
  // Регистрируем плагин через C API wrapper
  PdfPrinterPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PdfPrinterPlugin"));
}
