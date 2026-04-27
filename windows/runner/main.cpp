#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <filesystem>

#include "flutter_window.h"
#include "utils.h"

namespace {

void ConfigurePortableEnvironment() {
  wchar_t exe_path[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    return;
  }

  std::filesystem::path exe_dir = std::filesystem::path(exe_path).parent_path();
  std::filesystem::path app_data = exe_dir / L"AppData";
  std::filesystem::path config_dir = app_data / L"Config";
  std::filesystem::path cache_dir = app_data / L"cache";

  std::error_code ec;
  std::filesystem::create_directories(config_dir, ec);
  ec.clear();
  std::filesystem::create_directories(cache_dir, ec);

  ::SetEnvironmentVariableW(L"APPDATA", config_dir.c_str());
  ::SetEnvironmentVariableW(L"LOCALAPPDATA", config_dir.c_str());
  ::SetEnvironmentVariableW(L"TEMP", cache_dir.c_str());
  ::SetEnvironmentVariableW(L"TMP", cache_dir.c_str());
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Enforce a single running instance on Windows using a named mutex.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"KelivoMutex");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is already running; try to bring its window to front
    // instead of creating a new one.
    Win32Window::SendAppLinkToInstance(L"kelivo");
    return 0;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ConfigurePortableEnvironment();

  flutter::DartProject project(L"data");

  // https://github.com/flutter/flutter/issues/175135
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 860);
  if (!window.Create(L"kelivo", origin, size)) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
