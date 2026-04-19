#include "core/files/directory_scanner.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <system_error>

namespace {

  std::string lowerText(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (char ch : text) {
      out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
    }
    return out;
  }

  bool compareNames(const std::string& a, const std::string& b) {
    const std::string lowerA = lowerText(a);
    const std::string lowerB = lowerText(b);
    if (lowerA != lowerB) {
      return lowerA < lowerB;
    }
    return a < b;
  }

} // namespace

std::vector<FileEntry> DirectoryScanner::scan(const std::filesystem::path& dir,
                                              const std::vector<std::string>& extensions, bool showHiddenFiles,
                                              FileDialogSortField sortField, FileDialogSortOrder sortOrder) const {
  std::vector<FileEntry> entries;

  if (dir.empty()) {
    return entries;
  }

  std::error_code ec;
  if (!std::filesystem::exists(dir, ec) || ec || !std::filesystem::is_directory(dir, ec) || ec) {
    return entries;
  }

  std::vector<std::string> normalizedExtensions;
  normalizedExtensions.reserve(extensions.size());
  for (const auto& extension : extensions) {
    const std::string normalized = normalizeExtension(extension);
    if (!normalized.empty()) {
      normalizedExtensions.push_back(normalized);
    }
  }

  for (const auto& item :
       std::filesystem::directory_iterator(dir, std::filesystem::directory_options::skip_permission_denied, ec)) {
    if (ec) {
      break;
    }

    const std::string name = item.path().filename().string();
    if (!showHiddenFiles && isHiddenName(name)) {
      continue;
    }

    std::error_code typeEc;
    const bool isDir = item.is_directory(typeEc);
    if (typeEc) {
      continue;
    }

    if (!isDir) {
      const bool isRegular = item.is_regular_file(typeEc);
      if (typeEc || !isRegular || !matchesExtension(item.path(), normalizedExtensions)) {
        continue;
      }
    }

    FileEntry entry;
    entry.name = std::move(name);
    entry.absPath = std::filesystem::absolute(item.path(), ec);
    if (ec) {
      entry.absPath = item.path();
      ec.clear();
    }
    entry.isDir = isDir;
    if (!isDir) {
      entry.size = item.file_size(ec);
      if (ec) {
        entry.size = 0;
        ec.clear();
      }
    }
    entry.mtime = item.last_write_time(ec);
    if (ec) {
      entry.mtime = {};
      ec.clear();
    }
    entries.push_back(std::move(entry));
  }

  const bool ascending = sortOrder == FileDialogSortOrder::Ascending;
  std::sort(entries.begin(), entries.end(), [sortField, ascending](const FileEntry& a, const FileEntry& b) {
    if (a.isDir != b.isDir) {
      return a.isDir > b.isDir;
    }

    switch (sortField) {
    case FileDialogSortField::Size:
      if (!a.isDir && !b.isDir && a.size != b.size) {
        return ascending ? (a.size < b.size) : (a.size > b.size);
      }
      break;
    case FileDialogSortField::Modified:
      if (a.mtime != b.mtime) {
        return ascending ? (a.mtime < b.mtime) : (a.mtime > b.mtime);
      }
      break;
    case FileDialogSortField::Name:
      break;
    }

    if (a.name == b.name) {
      return a.absPath.string() < b.absPath.string();
    }
    return ascending ? compareNames(a.name, b.name) : compareNames(b.name, a.name);
  });

  return entries;
}

bool DirectoryScanner::isImagePath(const std::filesystem::path& path) {
  static constexpr std::array<std::string_view, 6> kImageExtensions = {
      ".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif",
  };

  const std::string ext = normalizeExtension(path.extension().string());
  return std::find(kImageExtensions.begin(), kImageExtensions.end(), ext) != kImageExtensions.end();
}

bool DirectoryScanner::matchesExtension(const std::filesystem::path& path, const std::vector<std::string>& extensions) {
  if (extensions.empty()) {
    return true;
  }

  const std::string ext = normalizeExtension(path.extension().string());
  return std::find(extensions.begin(), extensions.end(), ext) != extensions.end();
}

bool DirectoryScanner::isHiddenName(std::string_view name) { return !name.empty() && name.front() == '.'; }

std::string DirectoryScanner::normalizeExtension(std::string_view extension) {
  if (extension.empty()) {
    return {};
  }

  std::string out;
  out.reserve(extension.size() + 1);
  if (extension.front() != '.') {
    out.push_back('.');
  }
  for (char ch : extension) {
    out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
  }
  return out;
}

std::string DirectoryScanner::lower(std::string_view text) {
  std::string out;
  out.reserve(text.size());
  for (char ch : text) {
    out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
  }
  return out;
}
