#include "flutter_window.h"

#include <windows.h>
#include <shellapi.h>
#include <mmsystem.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayId = 1;
constexpr UINT kMenuOpen = 1001;
constexpr UINT kMenuExit = 1002;
constexpr wchar_t kRunValue[] = L"AlAnadHR";
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

std::wstring Widen(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring w(n > 0 ? n - 1 : 0, L'\0');
  if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
  return w;
}

const std::string* StringArg(const flutter::EncodableValue* v) {
  return v ? std::get_if<std::string>(v) : nullptr;
}

const flutter::EncodableValue* MapGet(const flutter::EncodableMap& m, const char* key) {
  auto it = m.find(flutter::EncodableValue(std::string(key)));
  return it == m.end() ? nullptr : &it->second;
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
  SetupChannel();
  AddTrayIcon();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!this->start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  HidePopup();
  RemoveTrayIcon();
  PlaySoundW(nullptr, nullptr, 0);
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// ------------------------------------------------------------------------------------------------ tray icon

void FlutterWindow::AddTrayIcon() {
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayId;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = WM_TRAYICON;
  nid.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(nid.szTip, L"Al Anad HR");
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &nid) == TRUE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayId;
  Shell_NotifyIconW(NIM_DELETE, &nid);
  tray_added_ = false;
}

void FlutterWindow::ShowAndFocus() {
  HWND h = GetHandle();
  if (!h) return;
  ShowWindow(h, IsIconic(h) ? SW_RESTORE : SW_SHOW);
  // Windows only lets the foreground app take focus. Borrow the foreground thread's input state for a moment, flip the
  // window to "topmost" and back so it ends up in front of everything, then take focus.
  HWND fg = GetForegroundWindow();
  DWORD fgThread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
  DWORD me = GetCurrentThreadId();
  bool attached = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, TRUE);
  SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  BringWindowToTop(h);
  SetForegroundWindow(h);
  SetFocus(h);
  if (attached) AttachThreadInput(me, fgThread, FALSE);
  if (GetForegroundWindow() != h) {
    // still blocked by Windows: at least make the taskbar button flash until the person looks
    FLASHWINFO fi = {sizeof(fi), h, FLASHW_ALL | FLASHW_TIMERNOFG, 0, 0};
    FlashWindowEx(&fi);
  }
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kMenuOpen, L"Open Al Anad HR");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExit, L"Exit");
  POINT p;
  GetCursorPos(&p);
  SetForegroundWindow(GetHandle());  // needed so the menu closes when the user clicks elsewhere
  UINT cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, p.x, p.y, 0, GetHandle(), nullptr);
  DestroyMenu(menu);
  if (cmd == kMenuOpen) {
    ShowAndFocus();
  } else if (cmd == kMenuExit) {
    quitting_ = true;
    PostMessageW(GetHandle(), WM_CLOSE, 0, 0);
  }
}

void FlutterWindow::ShowBalloon(const std::wstring& title, const std::wstring& body) {
  if (!tray_added_) return;
  NOTIFYICONDATAW nid = {};
  nid.cbSize = sizeof(nid);
  nid.hWnd = GetHandle();
  nid.uID = kTrayId;
  nid.uFlags = NIF_INFO;
  nid.dwInfoFlags = NIIF_INFO;  // no NIIF_NOSOUND: Windows plays its notification sound
  wcsncpy_s(nid.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(nid.szInfo, body.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &nid);
}

// ------------------------------------------------------------------------------------------------ incoming-meeting card

namespace {
constexpr wchar_t kPopupClass[] = L"AlAnadRingPopup";
constexpr int kPopupW = 380, kPopupH = 156, kMargin = 16;
}  // namespace

// The two buttons, in window coordinates (96-dpi design units scaled to |dpi|). Decline is on the outer side, Join on the inner side.
RECT FlutterWindow::PopupButton(bool join_button, int dpi) const {
  auto S = [dpi](int v) { return MulDiv(v, dpi, 96); };
  int pad = 16, gap = 12, h = 40, bw = (kPopupW - 2 * pad - gap) / 2;
  int top = kPopupH - pad - h;
  bool left_slot = p_rtl_ ? join_button : !join_button;   // LTR: Decline left, Join right. RTL: mirrored.
  int x = left_slot ? pad : pad + bw + gap;
  return RECT{S(x), S(top), S(x + bw), S(top + h)};
}

void FlutterWindow::PopupPaint(HWND hwnd) {
  PAINTSTRUCT ps;
  HDC dc = BeginPaint(hwnd, &ps);
  RECT rc;
  GetClientRect(hwnd, &rc);
  int dpi = GetDpiForWindow(hwnd);
  auto S = [dpi](int v) { return MulDiv(v, dpi, 96); };

  HBRUSH bg = CreateSolidBrush(RGB(0x06, 0x1B, 0x26));
  FillRect(dc, &rc, bg);
  DeleteObject(bg);
  SetBkMode(dc, TRANSPARENT);

  UINT align = (p_rtl_ ? DT_RIGHT | DT_RTLREADING : DT_LEFT) | DT_SINGLELINE | DT_NOPREFIX | DT_END_ELLIPSIS | DT_VCENTER;
  auto font = [&](int pt, int weight) {
    return CreateFontW(-MulDiv(pt, dpi, 72), 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                       CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  };
  auto text = [&](const std::wstring& s, int x, int y, int w, int h, int pt, int weight, COLORREF c) {
    HFONT f = font(pt, weight);
    HGDIOBJ old = SelectObject(dc, f);
    SetTextColor(dc, c);
    RECT r{S(x), S(y), S(x + w), S(y + h)};
    DrawTextW(dc, s.c_str(), -1, &r, align);
    SelectObject(dc, old);
    DeleteObject(f);
  };
  int inner = kPopupW - 32;
  text(p_header_, 16, 12, inner, 20, 10, FW_NORMAL, RGB(0xB5, 0xC4, 0xCC));
  text(p_title_, 16, 34, inner, 32, 15, FW_BOLD, RGB(0xFF, 0xFF, 0xFF));
  if (!p_sub_.empty()) text(p_sub_, 16, 68, inner, 22, 10, FW_NORMAL, RGB(0xB5, 0xC4, 0xCC));

  for (int b = 0; b < 2; b++) {
    bool join_b = b == 1;
    RECT r = PopupButton(join_b, dpi);
    HBRUSH br = CreateSolidBrush(join_b ? RGB(0x10, 0xB9, 0x81) : RGB(0xEF, 0x44, 0x44));
    HGDIOBJ oldb = SelectObject(dc, br);
    HGDIOBJ oldp = SelectObject(dc, GetStockObject(NULL_PEN));
    RoundRect(dc, r.left, r.top, r.right, r.bottom, S(12), S(12));
    SelectObject(dc, oldp);
    SelectObject(dc, oldb);
    DeleteObject(br);
    HFONT f = font(11, FW_SEMIBOLD);
    HGDIOBJ oldf = SelectObject(dc, f);
    SetTextColor(dc, RGB(0xFF, 0xFF, 0xFF));
    DrawTextW(dc, (join_b ? p_join_ : p_decline_).c_str(), -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX | (p_rtl_ ? DT_RTLREADING : 0));
    SelectObject(dc, oldf);
    DeleteObject(f);
  }
  EndPaint(hwnd, &ps);
}

void FlutterWindow::PopupClick(int x, int y) {
  int dpi = GetDpiForWindow(popup_);
  POINT p{x, y};
  const char* action = "open";
  RECT j = PopupButton(true, dpi), d = PopupButton(false, dpi);
  if (PtInRect(&j, p)) action = "join";
  else if (PtInRect(&d, p)) action = "decline";
  if (channel_) channel_->InvokeMethod("popupAction", std::make_unique<flutter::EncodableValue>(std::string(action)));
}

LRESULT CALLBACK FlutterWindow::PopupProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  if (msg == WM_NCCREATE) {
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams));
  }
  auto* self = reinterpret_cast<FlutterWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (msg) {
    case WM_PAINT:
      if (self) { self->PopupPaint(hwnd); return 0; }
      break;
    case WM_ERASEBKGND:
      return 1;
    case WM_LBUTTONUP:
      if (self) { self->PopupClick(static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))); return 0; }
      break;
    case WM_SETCURSOR:
      SetCursor(LoadCursorW(nullptr, IDC_HAND));
      return TRUE;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;   // clicking the card must not steal focus from what the person is doing
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

void FlutterWindow::ShowPopup(const std::wstring& header, const std::wstring& title, const std::wstring& sub,
                              const std::wstring& join, const std::wstring& decline, bool rtl) {
  p_header_ = header; p_title_ = title; p_sub_ = sub; p_join_ = join; p_decline_ = decline; p_rtl_ = rtl;
  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = PopupProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kPopupClass;
    wc.hCursor = LoadCursorW(nullptr, IDC_HAND);
    RegisterClassW(&wc);
    registered = true;
  }
  if (!popup_) {
    popup_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kPopupClass, L"Al Anad HR", WS_POPUP, 0, 0, 10, 10,
                             nullptr, nullptr, GetModuleHandleW(nullptr), this);
    if (!popup_) return;
  }
  int dpi = GetDpiForWindow(popup_);
  int w = MulDiv(kPopupW, dpi, 96), h = MulDiv(kPopupH, dpi, 96), m = MulDiv(kMargin, dpi, 96);
  RECT work;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  int x = rtl ? work.left + m : work.right - w - m;   // top-left for right-to-left languages, top-right otherwise
  int y = work.top + m;
  SetWindowPos(popup_, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE | SWP_SHOWWINDOW);
  HRGN rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, MulDiv(20, dpi, 96), MulDiv(20, dpi, 96));
  SetWindowRgn(popup_, rgn, TRUE);   // the system owns the region now
  InvalidateRect(popup_, nullptr, TRUE);
}

void FlutterWindow::HidePopup() {
  if (popup_) {
    DestroyWindow(popup_);
    popup_ = nullptr;
  }
}

// ------------------------------------------------------------------------------------------------ Dart channel

void FlutterWindow::SetupChannel() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "alanad/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const std::string& m = call.method_name();
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (m == "playLoop" || m == "playOnce") {
          const std::string* path = args ? StringArg(MapGet(*args, "path")) : nullptr;
          if (!path) { result->Success(flutter::EncodableValue(false)); return; }
          DWORD flags = SND_FILENAME | SND_ASYNC | SND_NODEFAULT | (m == "playLoop" ? SND_LOOP : 0);
          result->Success(flutter::EncodableValue(PlaySoundW(Widen(*path).c_str(), nullptr, flags) == TRUE));
        } else if (m == "showPopup") {
          auto str = [&](const char* k) { const std::string* s = args ? StringArg(MapGet(*args, k)) : nullptr; return s ? Widen(*s) : std::wstring(); };
          const flutter::EncodableValue* rv = args ? MapGet(*args, "rtl") : nullptr;
          const bool* rtl = rv ? std::get_if<bool>(rv) : nullptr;
          ShowPopup(str("header"), str("title"), str("sub"), str("join"), str("decline"), rtl && *rtl);
          result->Success(flutter::EncodableValue(true));
        } else if (m == "hidePopup") {
          HidePopup();
          result->Success(flutter::EncodableValue(true));
        } else if (m == "stopSound") {
          PlaySoundW(nullptr, nullptr, 0);
          result->Success(flutter::EncodableValue(true));
        } else if (m == "notify") {
          const std::string* title = args ? StringArg(MapGet(*args, "title")) : nullptr;
          const std::string* body = args ? StringArg(MapGet(*args, "body")) : nullptr;
          ShowBalloon(title ? Widen(*title) : L"Al Anad HR", body ? Widen(*body) : L"");
          result->Success(flutter::EncodableValue(true));
        } else if (m == "show") {
          ShowAndFocus();
          result->Success(flutter::EncodableValue(true));
        } else if (m == "isFocused") {
          // true only while the app window is the one the person is working in (visible, not minimized, in front)
          result->Success(flutter::EncodableValue(IsWindowVisible(GetHandle()) && !IsIconic(GetHandle()) && GetForegroundWindow() == GetHandle()));
        } else if (m == "setAutoStart") {
          const flutter::EncodableValue* v = args ? MapGet(*args, "on") : nullptr;
          const bool* on = v ? std::get_if<bool>(v) : nullptr;
          HKEY key;
          bool ok = false;
          if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
            if (on && *on) {
              wchar_t exe[MAX_PATH];
              GetModuleFileNameW(nullptr, exe, MAX_PATH);
              std::wstring cmd = std::wstring(L"\"") + exe + L"\" --tray";
              ok = RegSetValueExW(key, kRunValue, 0, REG_SZ, reinterpret_cast<const BYTE*>(cmd.c_str()),
                                  static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
            } else {
              RegDeleteValueW(key, kRunValue);
              ok = true;
            }
            RegCloseKey(key);
          }
          result->Success(flutter::EncodableValue(ok));
        } else {
          result->NotImplemented();
        }
      });
}

// ------------------------------------------------------------------------------------------------ messages

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // The close button hides the window (the app keeps running in the tray so meetings still ring).
  if (message == WM_CLOSE && !quitting_) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (message == WM_TRAYICON) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
      case NIN_BALLOONUSERCLICK:
        ShowAndFocus();
        if (channel_ && LOWORD(lparam) == NIN_BALLOONUSERCLICK) {
          channel_->InvokeMethod("balloonClicked", nullptr);
        }
        break;
      case WM_RBUTTONUP:
        ShowTrayMenu();
        break;
    }
    return 0;
  }
  if (message == WM_SHOW_APP) {
    ShowAndFocus();
    return 0;
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
