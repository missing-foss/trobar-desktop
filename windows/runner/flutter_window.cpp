#include "flutter_window.h"

#include <dbt.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

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

  volume_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "trobar/volumes",
      &flutter::StandardMethodCodec::GetInstance());
  volume_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            volume_sink_ = std::move(events);
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            volume_sink_ = nullptr;
            return nullptr;
          }));
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  volume_sink_ = nullptr;
  volume_channel_ = nullptr;
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DEVICECHANGE:
      // A top-level window gets volume broadcasts without registering: a
      // volume, or the media in an existing drive (DBTF_MEDIA), arriving or
      // going, with its drive letters in dbcv_unitmask.
      if ((wparam == DBT_DEVICEARRIVAL || wparam == DBT_DEVICEREMOVECOMPLETE) &&
          lparam != 0 && volume_sink_) {
        auto header = reinterpret_cast<const DEV_BROADCAST_HDR*>(lparam);
        if (header->dbch_devicetype == DBT_DEVTYP_VOLUME) {
          auto volume = reinterpret_cast<const DEV_BROADCAST_VOLUME*>(lparam);
          std::string letters;
          for (int i = 0; i < 26; i++) {
            if (volume->dbcv_unitmask & (1u << i)) {
              letters += static_cast<char>('A' + i);
            }
          }
          flutter::EncodableMap event{
              {flutter::EncodableValue("arrived"),
               flutter::EncodableValue(wparam == DBT_DEVICEARRIVAL)},
              {flutter::EncodableValue("letters"), flutter::EncodableValue(letters)},
              {flutter::EncodableValue("media"),
               flutter::EncodableValue((volume->dbcv_flags & DBTF_MEDIA) != 0)},
          };
          volume_sink_->Success(flutter::EncodableValue(event));
        }
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
