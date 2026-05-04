import QtQuick
import Quickshell
import qs.Commons

QtObject {
  id: root

  function migrate(adapter, logger, rawJson) {
    logger.i("Migration44", "Updating PAM pam/password.conf");

    const configDir = Settings.configDir;
    const pamConfigDir = configDir + "pam";
    const pamConfigFile = pamConfigDir + "/password.conf";
    const pamConfigDirEsc = pamConfigDir.replace(/'/g, "'\\''");
    const pamConfigFileEsc = pamConfigFile.replace(/'/g, "'\\''");

    // Ensure directory exists
    Quickshell.execDetached(["mkdir", "-p", pamConfigDir]);

    // Generate the PAM config file content (updated version)
    var configContent = "auth sufficient pam_fprintd.so timeout=-1\n";
    configContent += "auth sufficient /run/current-system/sw/lib/security/pam_fprintd.so timeout=-1 # for NixOS\n";
    configContent += "auth required pam_unix.so\n";

    // Write the config file using heredoc
    var script = `cat > '${pamConfigFileEsc}' << 'EOF'\n`;
    script += configContent;
    script += "EOF\n";
    Quickshell.execDetached(["sh", "-c", script]);

    logger.d("Migration44", "PAM config file updated at:", pamConfigFile);

    return true;
  }
}
