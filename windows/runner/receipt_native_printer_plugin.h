#ifndef RECEIPT_NATIVE_PRINTER_PLUGIN_H_
#define RECEIPT_NATIVE_PRINTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <memory>

class ReceiptNativePrinterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  ReceiptNativePrinterPlugin();
  virtual ~ReceiptNativePrinterPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

extern "C" __declspec(dllexport) void ReceiptNativePrinterPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // RECEIPT_NATIVE_PRINTER_PLUGIN_H_
