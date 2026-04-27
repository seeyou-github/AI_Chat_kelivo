#include "win32_window.h"

#include <cmath>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <dwmapi.h>
#include <flutter_windows.h>
#include <regex>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;
static HBRUSH g_startup_background_brush = nullptr;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

struct StartupWindowPlacement {
  std::optional<int> width;
  std::optional<int> height;
};

struct PhysicalWindowPlacement {
  int x;
  int y;
  int width;
  int height;
};

bool GetSystemDarkModePreference() {
  DWORD light_mode = 1;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);
  return result == ERROR_SUCCESS ? light_mode == 0 : false;
}

std::optional<std::string> ReadPortablePreferencesJson() {
  static bool loaded = false;
  static std::optional<std::string> cached_content;
  if (loaded) {
    return cached_content;
  }
  loaded = true;

  wchar_t module_path[MAX_PATH];
  if (GetModuleFileName(nullptr, module_path, MAX_PATH) == 0) {
    return std::nullopt;
  }

  std::filesystem::path exe_path(module_path);
  const auto config_path =
      exe_path.parent_path() / L"AppData" / L"Config" / L"shared_preferences.json";
  std::ifstream input(config_path, std::ios::binary);
  if (!input.is_open()) {
    return std::nullopt;
  }

  cached_content = std::string((std::istreambuf_iterator<char>(input)),
                               std::istreambuf_iterator<char>());
  return cached_content;
}

std::optional<bool> GetConfiguredStartupDarkModePreference() {
  const auto content = ReadPortablePreferencesJson();
  if (!content.has_value()) {
    return std::nullopt;
  }

  std::smatch match;
  const std::regex theme_regex(
      "\"flutter\\\\.theme_mode_v1\"\\s*:\\s*\"(dark|light|system)\"");
  if (!std::regex_search(*content, match, theme_regex)) {
    return std::nullopt;
  }

  const std::string theme_mode = match[1].str();
  if (theme_mode == "dark") {
    return true;
  }
  if (theme_mode == "light") {
    return false;
  }
  return std::nullopt;
}

std::optional<double> ExtractDoublePreference(const std::string& content,
                                              const std::string& key) {
  const std::regex number_regex(
      std::string("\"flutter\\\\.") + key + "\"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)");
  std::smatch match;
  if (!std::regex_search(content, match, number_regex)) {
    return std::nullopt;
  }
  try {
    return std::stod(match[1].str());
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<int> SanitizeWindowDimension(std::optional<double> value) {
  if (!value.has_value() || !std::isfinite(*value)) {
    return std::nullopt;
  }
  int rounded = static_cast<int>(std::lround(*value));
  if (rounded < 960) rounded = 960;
  if (rounded > 8192) rounded = 8192;
  return rounded;
}

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

StartupWindowPlacement GetConfiguredStartupWindowPlacement() {
  StartupWindowPlacement placement;
  const auto content = ReadPortablePreferencesJson();
  if (!content.has_value()) {
    return placement;
  }

  placement.width = SanitizeWindowDimension(
      ExtractDoublePreference(*content, "window_width_v1"));
  placement.height = SanitizeWindowDimension(
      ExtractDoublePreference(*content, "window_height_v1"));
  return placement;
}

PhysicalWindowPlacement ResolveStartupPlacement(int fallback_x,
                                                int fallback_y,
                                                int logical_width,
                                                int logical_height) {
  POINT seed_point{static_cast<LONG>(fallback_x), static_cast<LONG>(fallback_y)};
  HMONITOR monitor = MonitorFromPoint(seed_point, MONITOR_DEFAULTTOPRIMARY);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;
  const int physical_width = Scale(logical_width, scale_factor);
  const int physical_height = Scale(logical_height, scale_factor);

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return PhysicalWindowPlacement{
        Scale(fallback_x, scale_factor),
        Scale(fallback_y, scale_factor),
        physical_width,
        physical_height,
    };
  }

  const RECT work_area = monitor_info.rcWork;
  const int centered_x =
      work_area.left + ((work_area.right - work_area.left) - physical_width) / 2;
  const int centered_y =
      work_area.top + ((work_area.bottom - work_area.top) - physical_height) / 2;
  return PhysicalWindowPlacement{
      centered_x,
      centered_y,
      physical_width,
      physical_height,
  };
}

bool ResolvePreferredDarkMode() {
  const auto configured = GetConfiguredStartupDarkModePreference();
  return configured.value_or(GetSystemDarkModePreference());
}

void EnsureStartupBackgroundBrush() {
  if (g_startup_background_brush != nullptr) {
    return;
  }

  const COLORREF dark_startup_color = RGB(18, 18, 19);
  const COLORREF light_startup_color = RGB(247, 247, 247);
  g_startup_background_brush = CreateSolidBrush(
      ResolvePreferredDarkMode() ? dark_startup_color : light_startup_color);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    EnsureStartupBackgroundBrush();
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = g_startup_background_brush;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  if (g_startup_background_brush != nullptr) {
    DeleteObject(g_startup_background_brush);
    g_startup_background_brush = nullptr;
  }
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  // Before creating a new window, first check whether there is already an
  // existing window with the same class name and title. If so, bring that
  // window to the foreground instead of creating another one.
  if (SendAppLinkToInstance(title)) {
    return false;
  }

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const auto startup_placement = GetConfiguredStartupWindowPlacement();
  const int logical_width =
      startup_placement.width.value_or(static_cast<int>(size.width));
  const int logical_height =
      startup_placement.height.value_or(static_cast<int>(size.height));

  const PhysicalWindowPlacement resolved_placement = ResolveStartupPlacement(
      static_cast<int>(origin.x), static_cast<int>(origin.y),
      logical_width, logical_height);

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      resolved_placement.x, resolved_placement.y,
      resolved_placement.width, resolved_placement.height,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme();

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme();
      InvalidateRect(hwnd, nullptr, TRUE);
      return 0;

    case WM_ERASEBKGND: {
      HBRUSH brush = background_brush_;
      if (brush == nullptr) {
        brush = g_startup_background_brush;
      }
      if (brush == nullptr) {
        return DefWindowProc(window_handle_, message, wparam, lparam);
      }
      RECT rect;
      GetClientRect(hwnd, &rect);
      FillRect(reinterpret_cast<HDC>(wparam), &rect, brush);
      return 0;
    }

    case WM_CONTEXTMENU:
      // Swallow default system context-menu for the main window.
      // Otherwise, when the tray plugin brings the app to front and
      // shows its own popup menu, Windows may also show the standard
      // window system menu at an offset position, making it look like
      // a "second" phantom menu and causing clicks to appear invalid.
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (background_brush_ != nullptr) {
    DeleteObject(background_brush_);
    background_brush_ = nullptr;
  }

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

// static
bool Win32Window::SendAppLinkToInstance(const std::wstring& title) {
  // 1. Look for a window that matches the Flutter runner window class and the
  //    given title.
  HWND hwnd = ::FindWindow(kWindowClassName, title.c_str());

  if (hwnd) {
    // 2. Query the current placement so we can restore it appropriately.
    WINDOWPLACEMENT place;
    place.length = sizeof(WINDOWPLACEMENT);
    if (::GetWindowPlacement(hwnd, &place)) {
      switch (place.showCmd) {
        case SW_SHOWMAXIMIZED:
          ::ShowWindow(hwnd, SW_SHOWMAXIMIZED);
          break;
        case SW_SHOWMINIMIZED:
          ::ShowWindow(hwnd, SW_RESTORE);
          break;
        default:
          ::ShowWindow(hwnd, SW_NORMAL);
          break;
      }
    } else {
      // If we cannot query placement, just try to show it normally.
      ::ShowWindow(hwnd, SW_NORMAL);
    }

    // 3. Bring the window to the front.
    ::SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                   SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
    ::SetForegroundWindow(hwnd);

    return true;
  }

  // No existing window found.
  return false;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateBackgroundBrush() {
  if (background_brush_ != nullptr) {
    DeleteObject(background_brush_);
    background_brush_ = nullptr;
  }

  const COLORREF color = dark_mode_enabled_
      ? RGB(18, 18, 19)
      : RGB(247, 247, 247);
  background_brush_ = CreateSolidBrush(color);
}

void Win32Window::UpdateTheme() {
  dark_mode_enabled_ = ResolvePreferredDarkMode();
  BOOL enable_dark_mode = dark_mode_enabled_;
  DwmSetWindowAttribute(window_handle_, DWMWA_USE_IMMERSIVE_DARK_MODE,
                        &enable_dark_mode, sizeof(enable_dark_mode));
  UpdateBackgroundBrush();
}
