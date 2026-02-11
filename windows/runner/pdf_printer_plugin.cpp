#include "pdf_printer_plugin.h"

#include <windows.h>
#include <winspool.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <fstream>
#include <sstream>
#include <codecvt>
#include <locale>

#include <flutter/plugin_registrar_windows.h>

#pragma comment(lib, "winspool.lib")
#pragma comment(lib, "shlwapi.lib")

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

// Конвертирует std::string в std::wstring
std::wstring StringToWString(const std::string& str) {
  if (str.empty()) return std::wstring();
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
  std::wstring wstrTo(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
  return wstrTo;
}

// Конвертирует std::wstring в std::string
std::string WStringToString(const std::wstring& wstr) {
  if (wstr.empty()) return std::string();
  int size_needed = WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
  std::string strTo(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &strTo[0], size_needed, NULL, NULL);
  return strTo;
}

// Получает путь к временной директории
std::wstring GetTempPath() {
  wchar_t temp_path[MAX_PATH];
  DWORD result = ::GetTempPathW(MAX_PATH, temp_path);
  if (result == 0 || result > MAX_PATH) {
    return L"C:\\Temp\\";
  }
  return std::wstring(temp_path);
}

}  // namespace

// C API wrapper - используем PluginRegistrarManager для правильного управления жизненным циклом
extern "C" __declspec(dllexport) void PdfPrinterPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  PdfPrinterPlugin::RegisterWithRegistrar(windows_registrar);
}

void PdfPrinterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "pdf_printer",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PdfPrinterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PdfPrinterPlugin::PdfPrinterPlugin() {}

PdfPrinterPlugin::~PdfPrinterPlugin() {}

void PdfPrinterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("printPdf") == 0) {
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("InvalidArguments", "Arguments must be a map");
      return;
    }

    // Получаем PDF байты
    auto pdf_bytes_iter = arguments->find(EncodableValue("pdfBytes"));
    if (pdf_bytes_iter == arguments->end()) {
      result->Error("InvalidArguments", "pdfBytes is required");
      return;
    }

    std::vector<uint8_t> pdf_bytes;
    // В Flutter MethodChannel байты передаются как List<int>
    const auto* pdf_bytes_list = std::get_if<EncodableList>(&pdf_bytes_iter->second);
    if (pdf_bytes_list) {
      pdf_bytes.reserve(pdf_bytes_list->size());
      for (const auto& item : *pdf_bytes_list) {
        if (const auto* int_val = std::get_if<int32_t>(&item)) {
          pdf_bytes.push_back(static_cast<uint8_t>(*int_val & 0xFF));
        } else if (const auto* int64_val = std::get_if<int64_t>(&item)) {
          pdf_bytes.push_back(static_cast<uint8_t>(*int64_val & 0xFF));
        } else {
          result->Error("InvalidArguments", "pdfBytes must be a list of integers");
          return;
        }
      }
    } else {
      result->Error("InvalidArguments", "pdfBytes must be a list");
      return;
    }

    // Получаем имя принтера (опционально)
    std::string printer_name;
    auto printer_name_iter = arguments->find(EncodableValue("printerName"));
    if (printer_name_iter != arguments->end()) {
      if (const auto* name = std::get_if<std::string>(&printer_name_iter->second)) {
        printer_name = *name;
      }
    }

    // Печатаем PDF
    bool success = PrintPdf(pdf_bytes, printer_name);
    result->Success(flutter::EncodableValue(success));
  } else if (method_call.method_name().compare("getAvailablePrinters") == 0) {
    auto printers = GetAvailablePrinters();
    std::vector<flutter::EncodableValue> printer_list;
    for (const auto& printer : printers) {
      printer_list.push_back(flutter::EncodableValue(printer));
    }
    result->Success(flutter::EncodableValue(printer_list));
  } else {
    result->NotImplemented();
  }
}

bool PdfPrinterPlugin::PrintPdf(const std::vector<uint8_t>& pdf_bytes, const std::string& printer_name) {
  // Создаем временный файл
  std::wstring temp_dir = GetTempPath();
  std::wstring temp_file = temp_dir + L"flutter_print_" + std::to_wstring(GetTickCount64()) + L".pdf";

  // Записываем PDF во временный файл
  std::ofstream file(temp_file, std::ios::binary);
  if (!file.is_open()) {
    return false;
  }
  file.write(reinterpret_cast<const char*>(pdf_bytes.data()), pdf_bytes.size());
  file.close();

  // Определяем принтер для печати
  std::wstring printer_w;
  if (printer_name.empty()) {
    // Используем принтер по умолчанию
    wchar_t default_printer[256];
    DWORD size = sizeof(default_printer) / sizeof(default_printer[0]);
    if (GetDefaultPrinterW(default_printer, &size)) {
      printer_w = default_printer;
    } else {
      // Если не удалось получить принтер по умолчанию, используем ShellExecute
      printer_w = L"";
    }
  } else {
    printer_w = StringToWString(printer_name);
  }

  bool success = false;

  // Используем ShellExecuteEx с максимальными флагами для скрытия окна
  // SEE_MASK_FLAG_NO_UI - не показывать диалоги ошибок
  // SEE_MASK_NOASYNC - синхронное выполнение
  // SEE_MASK_FLAG_DDEWAIT - ждать завершения DDE команды
  SHELLEXECUTEINFOW sei = {0};
  sei.cbSize = sizeof(SHELLEXECUTEINFOW);
  sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI | SEE_MASK_NOASYNC | SEE_MASK_FLAG_DDEWAIT;
  
  if (!printer_w.empty()) {
    // Печать на конкретный принтер через printto
    sei.lpVerb = L"printto";
    sei.lpFile = temp_file.c_str();
    sei.lpParameters = printer_w.c_str();
  } else {
    // Печать на принтер по умолчанию
    sei.lpVerb = L"print";
    sei.lpFile = temp_file.c_str();
  }
  sei.nShow = SW_HIDE;  // Скрываем окно

  if (ShellExecuteExW(&sei)) {
    success = true;
    if (sei.hProcess) {
      // Ждем очень короткое время (100мс), чтобы система успела обработать команду
      // но не блокируем UI и не даем окну PDF просмотрщика появиться
      WaitForSingleObject(sei.hProcess, 100);
      // Закрываем дескриптор сразу, не ждем полного завершения
      // Печать будет происходить в фоне, но окно уже не должно мелькать
      CloseHandle(sei.hProcess);
    }
  }

  // Удаляем временный файл после небольшой задержки
  // (даем системе время обработать файл)
  Sleep(1000);
  DeleteFileW(temp_file.c_str());

  return success;
}

std::vector<std::string> PdfPrinterPlugin::GetAvailablePrinters() {
  std::vector<std::string> printers;

  DWORD needed = 0;
  DWORD returned = 0;

  // Получаем размер буфера
  EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, NULL, 0, &needed, &returned);
  if (needed == 0) {
    return printers;
  }

  // Выделяем буфер
  std::vector<BYTE> buffer(needed);
  PRINTER_INFO_2W* printer_info = reinterpret_cast<PRINTER_INFO_2W*>(buffer.data());

  // Получаем список принтеров
  if (EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2,
                    buffer.data(), needed, &needed, &returned)) {
    for (DWORD i = 0; i < returned; i++) {
      if (printer_info[i].pPrinterName) {
        std::wstring printer_name_w(printer_info[i].pPrinterName);
        printers.push_back(WStringToString(printer_name_w));
      }
    }
  }

  return printers;
}
