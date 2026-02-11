#ifndef PDF_PRINTER_PLUGIN_H_
#define PDF_PRINTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <memory>
#include <string>
#include <vector>

class PdfPrinterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  PdfPrinterPlugin();

  virtual ~PdfPrinterPlugin();

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Печатает PDF файл на указанный принтер
  bool PrintPdf(const std::vector<uint8_t>& pdf_bytes, const std::string& printer_name);

  // Получает список доступных принтеров
  std::vector<std::string> GetAvailablePrinters();
};

// C API wrapper для регистрации плагина (как у стандартных Windows‑плагинов)
extern "C" __declspec(dllexport) void PdfPrinterPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // PDF_PRINTER_PLUGIN_H_
