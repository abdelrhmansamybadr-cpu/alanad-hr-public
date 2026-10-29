#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// Messages sent to the main window (see main.cpp for the second one).
#define WM_TRAYICON (WM_APP + 1)   // the tray icon was clicked
#define WM_SHOW_APP (WM_APP + 2)   // another copy of the app was started: bring this one up

// A window that does nothing but host a Flutter view. It also lives in the system tray: the close button hides the
// window instead of ending the app, so meetings can still ring; "Exit" in the tray menu really quits.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Started with Windows: stay in the tray, do not show the window.
  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowAndFocus();
  void ShowTrayMenu();
  void ShowBalloon(const std::wstring& title, const std::wstring& body);
  void SetupChannel();

  // The "incoming meeting" card in the top corner of the screen (top-right, or top-left for right-to-left languages).
  void ShowPopup(const std::wstring& header, const std::wstring& title, const std::wstring& sub,
                 const std::wstring& join, const std::wstring& decline, bool rtl);
  void HidePopup();
  void PopupPaint(HWND hwnd);
  void PopupClick(int x, int y);
  RECT PopupButton(bool join_button, int dpi) const;
  static LRESULT CALLBACK PopupProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

  HWND popup_ = nullptr;
  std::wstring p_header_, p_title_, p_sub_, p_join_, p_decline_;
  bool p_rtl_ = false;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Talks to Dart (sound, tray notification, show window, start with Windows).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  bool start_hidden_ = false;
  bool quitting_ = false;
  bool tray_added_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
