#include "scripting/plugin_git.h"

#include "core/process.h"

#include <chrono>
#include <system_error>
#include <utility>
#include <vector>

namespace scripting::plugin_git {

  namespace {
    using namespace std::chrono_literals;

    // Network ops get a generous budget; local metadata ops are quick.
    constexpr auto kNetworkTimeout = 120s;
    constexpr auto kLocalTimeout = 20s;
    // File bodies we read (catalog.toml / plugin.toml) are small; cap defensively.
    constexpr std::size_t kFileCap = 4 * 1024 * 1024;
    constexpr std::size_t kProgressCap = 64 * 1024;

    GitResult run(std::vector<std::string> args, std::chrono::milliseconds timeout, std::size_t cap) {
      const auto r = process::runSyncWithTimeoutAndOutputLimit(args, timeout, cap);
      return GitResult{
          .ok = static_cast<bool>(r),
          .exitCode = r.exitCode,
          .out = r.out,
          .err = r.err,
          .timedOut = r.timedOut,
      };
    }

    std::string trimTrailingNewline(std::string s) {
      while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) {
        s.pop_back();
      }
      return s;
    }
  } // namespace

  bool available() { return process::commandExists("git"); }

  GitResult cloneBlobless(const std::string& url, const std::filesystem::path& dest) {
    // Blobless but NOT shallow: full commit/tree history (still tiny — no file
    // blobs until needed), so later fetch + fast-forward work normally. A `--depth 1`
    // shallow clone grafts fetched commits as disjoint roots ("unrelated histories").
    return run(
        {"git", "clone", "--filter=blob:none", "--no-checkout", url, dest.string()}, kNetworkTimeout, kProgressCap
    );
  }

  GitResult showFile(const std::filesystem::path& dest, std::string_view repoPath, std::string_view rev) {
    return run(
        {"git", "-C", dest.string(), "show", std::string(rev) + ":" + std::string(repoPath)}, kLocalTimeout, kFileCap
    );
  }

  GitResult materialize(const std::filesystem::path& dest, std::string_view rev, std::string_view subdir) {
    // Discard any prior copy first so the result exactly matches `rev` (no stale files
    // left over from an older revision, no tampered edits). `checkout <rev> -- <path>`
    // then recreates it from the object store, lazily fetching blobs.
    std::error_code ec;
    std::filesystem::remove_all(dest / std::filesystem::path(subdir), ec);
    return run(
        {"git", "-C", dest.string(), "checkout", std::string(rev), "--", std::string(subdir)}, kNetworkTimeout,
        kProgressCap
    );
  }

  GitResult fetch(const std::filesystem::path& dest) {
    // Updates remote-tracking refs + FETCH_HEAD without touching the working tree.
    return run({"git", "-C", dest.string(), "fetch", "origin"}, kNetworkTimeout, kProgressCap);
  }

  GitResult remoteHead(const std::filesystem::path& dest) {
    auto r = run({"git", "-C", dest.string(), "rev-parse", "FETCH_HEAD"}, kLocalTimeout, kProgressCap);
    r.out = trimTrailingNewline(std::move(r.out));
    return r;
  }

  GitResult setHead(const std::filesystem::path& dest, std::string_view rev) {
    return run({"git", "-C", dest.string(), "update-ref", "HEAD", std::string(rev)}, kLocalTimeout, kProgressCap);
  }

  GitResult headRevision(const std::filesystem::path& dest) {
    auto r = run({"git", "-C", dest.string(), "rev-parse", "HEAD"}, kLocalTimeout, kProgressCap);
    r.out = trimTrailingNewline(std::move(r.out));
    return r;
  }

  bool hasPath(const std::filesystem::path& dest, std::string_view repoPath, std::string_view rev) {
    return run({"git", "-C", dest.string(), "cat-file", "-e", std::string(rev) + ":" + std::string(repoPath)},
               kLocalTimeout, kProgressCap)
        .ok;
  }

} // namespace scripting::plugin_git
