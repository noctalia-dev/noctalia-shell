#pragma once

#include <string>

namespace net {

  // Open a URL in the user's default browser. Returns true if a handler was launched.
  bool openInBrowser(const std::string& url);

} // namespace net
