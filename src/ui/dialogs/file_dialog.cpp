#include "ui/dialogs/file_dialog.h"

#include <utility>

namespace {

  FileDialogOptions s_options;
  FileDialog::CompletionCallback s_callback;
  FileDialogPresenter* s_presenter = nullptr;
  bool s_hasPendingCallback = false;

  std::string defaultTitle(FileDialogMode mode) {
    switch (mode) {
    case FileDialogMode::Open:
      return "Open File";
    case FileDialogMode::Save:
      return "Save File";
    case FileDialogMode::SelectFolder:
      return "Select Folder";
    }
    return "File Dialog";
  }

} // namespace

void FileDialog::setPresenter(FileDialogPresenter* presenter) noexcept { s_presenter = presenter; }

bool FileDialog::open(FileDialogOptions options, CompletionCallback callback) {
  if (s_hasPendingCallback && s_callback) {
    auto previous = std::move(s_callback);
    s_hasPendingCallback = false;
    previous(std::nullopt);
  }

  if (options.title.empty()) {
    options.title = defaultTitle(options.mode);
  }

  s_options = std::move(options);
  s_callback = std::move(callback);
  s_hasPendingCallback = static_cast<bool>(s_callback);

  if (s_presenter == nullptr || !s_presenter->openFileDialog()) {
    auto pending = std::move(s_callback);
    s_callback = {};
    s_hasPendingCallback = false;
    s_options = {};
    if (pending) {
      pending(std::nullopt);
    }
    return false;
  }

  return true;
}

void FileDialog::complete(std::optional<std::filesystem::path> result) {
  auto callback = std::move(s_callback);
  s_callback = {};
  s_hasPendingCallback = false;
  s_options = {};
  if (callback) {
    callback(std::move(result));
  }
}

void FileDialog::cancelIfPending() {
  if (!s_hasPendingCallback) {
    return;
  }
  auto callback = std::move(s_callback);
  s_callback = {};
  s_hasPendingCallback = false;
  s_options = {};
  if (callback) {
    callback(std::nullopt);
  }
}

const FileDialogOptions& FileDialog::currentOptions() { return s_options; }
