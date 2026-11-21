#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <filesystem>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

bool IsElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  const bool elevated =
      GetTokenInformation(token, TokenElevation, &elevation,
                          sizeof(elevation), &size) &&
      elevation.TokenIsElevated;
  CloseHandle(token);
  return elevated;
}

bool RelaunchElevated(HWND window) {
  std::wstring path(32768, L'\0');
  const DWORD length =
      GetModuleFileName(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) return false;
  path.resize(length);
  const auto directory = std::filesystem::path(path).parent_path();
  return reinterpret_cast<INT_PTR>(
             ShellExecute(window, L"runas", path.c_str(), nullptr,
                          directory.c_str(), SW_SHOWNORMAL)) > 32;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Only the core spawned by this window belongs to this job.
  kernel_job_ = CreateJobObject(nullptr, nullptr);
  if (kernel_job_) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(kernel_job_, JobObjectExtendedLimitInformation,
                                 &limits, static_cast<DWORD>(sizeof(limits)))) {
      CloseHandle(kernel_job_);
      kernel_job_ = nullptr;
    }
  }
  kernel_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev.clashdeck/windows-kernel", &flutter::StandardMethodCodec::GetInstance());
  kernel_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "isElevated") {
          result->Success(flutter::EncodableValue(IsElevated()));
          return;
        }
        if (call.method_name() == "relaunchElevated") {
          result->Success(flutter::EncodableValue(RelaunchElevated(GetHandle())));
          return;
        }
        if (call.method_name() != "track") {
          result->NotImplemented();
          return;
        }
        const auto* pid = call.arguments()
                              ? std::get_if<int32_t>(call.arguments())
                              : nullptr;
        HANDLE process = pid && *pid > 0
                             ? OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE,
                                           FALSE, static_cast<DWORD>(*pid))
                             : nullptr;
        const bool attached = process && kernel_job_ &&
                              AssignProcessToJobObject(kernel_job_, process);
        if (process) CloseHandle(process);
        if (attached) {
          result->Success();
        } else {
          result->Error("kernel-job", "Windows could not track the core process");
        }
      });

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev.clashdeck/windows-window", &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const HWND window = GetHandle();
        if (call.method_name() == "minimize") {
          PostMessage(window, WM_SYSCOMMAND, SC_MINIMIZE, 0);
        } else if (call.method_name() == "toggleMaximize") {
          PostMessage(window, WM_SYSCOMMAND,
                      IsZoomed(window) ? SC_RESTORE : SC_MAXIMIZE, 0);
        } else if (call.method_name() == "close") {
          PostMessage(window, WM_CLOSE, 0, 0);
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  kernel_channel_.reset();
  if (kernel_job_) {
    CloseHandle(kernel_job_);
    kernel_job_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_SIZE: {
      const bool maximized = wparam == SIZE_MAXIMIZED;
      if (!window_channel_ || wparam == SIZE_MINIMIZED ||
          maximized == maximized_) break;
      maximized_ = maximized;
      window_channel_->InvokeMethod(
          "maximized", std::make_unique<flutter::EncodableValue>(maximized_));
      break;
    }
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
