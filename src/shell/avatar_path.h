#pragma once

#include <string>
#include <string_view>

class AccountsService;
class ConfigService;
struct Config;

namespace shell {

  [[nodiscard]] std::string resolvedAvatarPath(const AccountsService* accounts, const Config& config);

  // Persists shell.avatar_path and updates AccountsService when it is connected.
  [[nodiscard]] bool applyAvatarPath(AccountsService* accounts, ConfigService* config, std::string_view path);

} // namespace shell
