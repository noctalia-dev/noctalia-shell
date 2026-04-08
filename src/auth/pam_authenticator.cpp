#include "auth/pam_authenticator.h"

#include <pwd.h>
#include <security/pam_appl.h>
#include <sys/types.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <vector>

namespace {

  void secureClear(std::string& value) {
    volatile char* ptr = value.empty() ? nullptr : &value[0];
    for (std::size_t i = 0; i < value.size(); ++i) {
      ptr[i] = '\0';
    }
    value.clear();
  }

  struct PamConversationData {
    const char* password = nullptr;
  };

  int pamConversation(int numMsg, const pam_message** msg, pam_response** response, void* appdataPtr) {
    if (numMsg <= 0 || msg == nullptr || response == nullptr || appdataPtr == nullptr) {
      return PAM_CONV_ERR;
    }

    auto* data = static_cast<PamConversationData*>(appdataPtr);
    auto* replies = static_cast<pam_response*>(std::calloc(static_cast<std::size_t>(numMsg), sizeof(pam_response)));
    if (replies == nullptr) {
      return PAM_BUF_ERR;
    }

    for (int i = 0; i < numMsg; ++i) {
      if (msg[i] == nullptr) {
        std::free(replies);
        return PAM_CONV_ERR;
      }

      switch (msg[i]->msg_style) {
      case PAM_PROMPT_ECHO_OFF:
        replies[i].resp = ::strdup(data->password != nullptr ? data->password : "");
        break;
      case PAM_PROMPT_ECHO_ON:
        replies[i].resp = ::strdup("");
        break;
      case PAM_ERROR_MSG:
      case PAM_TEXT_INFO:
        replies[i].resp = nullptr;
        break;
      default:
        for (int j = 0; j <= i; ++j) {
          if (replies[j].resp != nullptr) {
            std::free(replies[j].resp);
          }
        }
        std::free(replies);
        return PAM_CONV_ERR;
      }

      if ((msg[i]->msg_style == PAM_PROMPT_ECHO_OFF || msg[i]->msg_style == PAM_PROMPT_ECHO_ON) &&
          replies[i].resp == nullptr) {
        for (int j = 0; j <= i; ++j) {
          if (replies[j].resp != nullptr) {
            std::free(replies[j].resp);
          }
        }
        std::free(replies);
        return PAM_BUF_ERR;
      }
    }

    *response = replies;
    return PAM_SUCCESS;
  }

} // namespace

PamAuthenticator::Result PamAuthenticator::authenticateCurrentUser(std::string_view password) const {
  if (password.empty()) {
    return Result{.success = false, .message = "Password required"};
  }

  std::string user = currentUsername();
  if (user.empty()) {
    return Result{.success = false, .message = "Unable to resolve current user"};
  }

  std::string passwordCopy(password);
  PamConversationData convData{.password = passwordCopy.c_str()};
  pam_conv conv = {
      .conv = &pamConversation,
      .appdata_ptr = &convData,
  };

  pam_handle_t* pamh = nullptr;
  const int startRc = pam_start("login", user.c_str(), &conv, &pamh);
  if (startRc != PAM_SUCCESS || pamh == nullptr) {
    secureClear(passwordCopy);
    return Result{.success = false, .message = "PAM start failed"};
  }

  int rc = pam_authenticate(pamh, 0);
  if (rc == PAM_SUCCESS) {
    rc = pam_acct_mgmt(pamh, 0);
  }
  const char* err = pam_strerror(pamh, rc);
  pam_end(pamh, rc);

  secureClear(passwordCopy);

  if (rc == PAM_SUCCESS) {
    return Result{.success = true, .message = {}};
  }

  return Result{.success = false, .message = err != nullptr ? err : "Authentication failed"};
}

std::string PamAuthenticator::currentUsername() {
  const uid_t uid = getuid();
  passwd pwd{};
  passwd* result = nullptr;
  std::vector<char> buf(4096);

  while (true) {
    const int rc = getpwuid_r(uid, &pwd, buf.data(), buf.size(), &result);
    if (rc == 0 && result != nullptr) {
      return std::string(result->pw_name != nullptr ? result->pw_name : "");
    }
    if (rc != ERANGE) {
      return {};
    }
    buf.resize(buf.size() * 2);
    if (buf.size() > 1 << 20) {
      return {};
    }
  }
}
