#pragma once

#include <filesystem>
#include <string>
#include <string_view>

namespace scripting {

  // Outcome of a single git invocation. `out` is the captured stdout (file
  // contents for showFile, the revision for headRevision); `err` is stderr.
  struct GitResult {
    bool ok = false;
    int exitCode = -1;
    std::string out;
    std::string err;
    bool timedOut = false;

    explicit operator bool() const { return ok; }
  };

  // Thin synchronous wrapper over the `git` CLI for plugin sources. Every call
  // blocks on the subprocess, so callers MUST run these off the UI thread (the
  // plugin manager drives them on a worker). All ops target a single source
  // clone directory. `--filter=blob:none` is requested for lazy blob fetch;
  // servers that don't support it make git fall back to a normal shallow clone
  // on its own — no explicit degrade path here.
  namespace plugin_git {

    [[nodiscard]] bool available();

    // Blobless, no-checkout clone of `url` into `dest` (full history, no file blobs).
    [[nodiscard]] GitResult cloneBlobless(const std::string& url, const std::filesystem::path& dest);

    // `git -C dest show <rev>:<repoPath>` — lazily fetches one blob. out = file body.
    // `rev` defaults to HEAD; pass FETCH_HEAD to inspect a fetched-but-unapplied revision.
    [[nodiscard]] GitResult
    showFile(const std::filesystem::path& dest, std::string_view repoPath, std::string_view rev = "HEAD");

    // Re-derive `subdir` in the working tree from `rev`: wipe any prior/tampered/partial
    // copy, then `git checkout <rev> -- <subdir>` (clobbers unconditionally — no merge,
    // so a dirty working tree can't block it; blobs lazily fetch from the partial clone).
    // The materialized files are a disposable cache: always re-extractable from the
    // object store, so manual edits or interrupted runs self-heal on the next call.
    [[nodiscard]] GitResult
    materialize(const std::filesystem::path& dest, std::string_view rev, std::string_view subdir);

    // `git -C dest fetch origin` — update remote-tracking refs + FETCH_HEAD; the
    // working tree is untouched, so the new revision can be inspected before applying.
    [[nodiscard]] GitResult fetch(const std::filesystem::path& dest);

    // `git -C dest rev-parse FETCH_HEAD` — out = the just-fetched revision (trimmed).
    [[nodiscard]] GitResult remoteHead(const std::filesystem::path& dest);

    // `git -C dest update-ref HEAD <rev>` — advance HEAD (and its branch) to a fetched
    // revision after materializing it, so HEAD-relative reads (catalog, hasPath) reflect
    // the applied revision. Does not touch the working tree.
    [[nodiscard]] GitResult setHead(const std::filesystem::path& dest, std::string_view rev);

    // `git -C dest rev-parse HEAD` — out = commit sha (trimmed).
    [[nodiscard]] GitResult headRevision(const std::filesystem::path& dest);

    // `git -C dest cat-file -e <rev>:<repoPath>` — true if the path exists at `rev`
    // (tree metadata only, no blob fetch). Used to confirm a source actually ships a
    // plugin before materializing it. `rev` defaults to HEAD.
    [[nodiscard]] bool
    hasPath(const std::filesystem::path& dest, std::string_view repoPath, std::string_view rev = "HEAD");

  } // namespace plugin_git

} // namespace scripting
