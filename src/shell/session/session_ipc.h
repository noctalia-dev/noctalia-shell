#pragma once

class ConfigService;
class IpcService;
class LockScreen;
class SessionActionRunner;

void registerSessionIpc(IpcService& ipc, SessionActionRunner& runner, LockScreen& lockScreen, ConfigService& config);
