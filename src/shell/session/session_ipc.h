#pragma once

class IpcService;
class LockScreen;
class SessionActionRunner;

void registerSessionIpc(IpcService& ipc, SessionActionRunner& runner, LockScreen& lockScreen);
