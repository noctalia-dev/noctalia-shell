#include "shell/avatar_path.h"

#include "config/config_service.h"
#include "config/config_types.h"
#include "dbus/accounts/accounts_service.h"

#include <string>
#include <string_view>
#include <vector>

namespace shell {

  std::string resolvedAvatarPath(const AccountsService* accounts, const Config& config) {
    if (accounts != nullptr) {
      const std::string& iconFile = accounts->iconFile();
      if (!iconFile.empty()) {
        return iconFile;
      }
    }
    return config.shell.avatarPath;
  }

  bool applyAvatarPath(AccountsService* accounts, ConfigService* config, std::string_view path) {
    if (config == nullptr) {
      return false;
    }
    if (!config->setOverride({"shell", "avatar_path"}, std::string(path))) {
      return false;
    }
    if (accounts != nullptr && !path.empty() && !accounts->setIconFile(path)) {
      return false;
    }
    return true;
  }

} // namespace shell
