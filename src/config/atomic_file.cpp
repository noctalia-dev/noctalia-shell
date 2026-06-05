#include "config/atomic_file.h"

#include <fstream>
#include <system_error>
#include <utility>

namespace {
  [[nodiscard]] std::filesystem::path
  resolveRelativeSymlinkTarget(const std::filesystem::path& linkPath, std::filesystem::path target) {
    if (target.is_relative()) {
      target = linkPath.parent_path() / target;
    }
    return target.lexically_normal();
  }
} // namespace

std::optional<AtomicWriteTarget> resolveAtomicWriteTarget(const std::filesystem::path& path) {
  if (path.empty()) {
    return std::nullopt;
  }

  std::error_code ec;
  const auto status = std::filesystem::symlink_status(path, ec);
  if (ec) {
    if (ec == std::errc::no_such_file_or_directory) {
      return AtomicWriteTarget{.path = path, .throughSymlink = false};
    }
    return std::nullopt;
  }

  if (status.type() != std::filesystem::file_type::symlink) {
    return AtomicWriteTarget{.path = path, .throughSymlink = false};
  }

  const auto canonicalTarget = std::filesystem::canonical(path, ec);
  if (!ec) {
    return AtomicWriteTarget{.path = canonicalTarget, .throughSymlink = true};
  }

  ec.clear();
  auto linkTarget = std::filesystem::read_symlink(path, ec);
  if (ec) {
    return std::nullopt;
  }

  return AtomicWriteTarget{.path = resolveRelativeSymlinkTarget(path, std::move(linkTarget)), .throughSymlink = true};
}

bool writeTextFileAtomic(const std::filesystem::path& path, std::string_view content) {
  const auto target = resolveAtomicWriteTarget(path);
  if (!target.has_value() || target->path.empty()) {
    return false;
  }

  std::error_code ec;
  const auto parent = target->path.parent_path();
  if (!parent.empty()) {
    std::filesystem::create_directories(parent, ec);
    if (ec) {
      return false;
    }
  }

  const std::filesystem::path tmpPath = target->path.string() + ".tmp";
  {
    std::ofstream out(tmpPath, std::ios::binary | std::ios::trunc);
    if (!out.is_open()) {
      return false;
    }
    out.write(content.data(), static_cast<std::streamsize>(content.size()));
    if (!out.good()) {
      std::filesystem::remove(tmpPath, ec);
      return false;
    }
  }

  std::filesystem::rename(tmpPath, target->path, ec);
  if (ec) {
    std::filesystem::remove(tmpPath, ec);
    return false;
  }
  return true;
}
