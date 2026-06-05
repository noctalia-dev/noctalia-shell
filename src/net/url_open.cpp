#include "net/url_open.h"

#include "core/process.h"

namespace net {

  bool openInBrowser(const std::string& url) {
    return process::launchFirstAvailable({
        {"xdg-open", url.c_str()},
        {"gio", "open", url.c_str()},
        {"kde-open", url.c_str()},
    });
  }

} // namespace net
