#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One copy only: the app keeps running in the tray when its window is closed, so starting it again
  // just brings the running copy back (two copies would ring twice).
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"AlAnadHR_SingleInstance");
  if (single != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND other = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
    if (other != nullptr) ::PostMessageW(other, WM_SHOW_APP, 0, 0);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Started with Windows ("--tray"): stay in the tray until someone calls or opens it.
  window.SetStartHidden(std::wstring(command_line).find(L"--tray") != std::wstring::npos);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1320, 780);
  if (!window.Create(L"Al Anad HR", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single != nullptr) ::CloseHandle(single);
  return EXIT_SUCCESS;
}
