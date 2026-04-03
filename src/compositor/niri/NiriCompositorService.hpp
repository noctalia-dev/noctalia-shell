#pragma once

#include <atomic>
#include <cstdint>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>

class NiriService {
public:
    NiriService();
    ~NiriService();

    NiriService(const NiriService&) = delete;
    NiriService& operator=(const NiriService&) = delete;

    [[nodiscard]] bool isRunning() const noexcept;

private:
    bool connectSocket();
    void startReader();
    void stopReader();
    void readerLoop();

    bool readLine(int fd, std::string& out);
    void handleEventLine(const std::string& line);
    void handleWorkspacesChanged(const std::string& line);
    void handleWorkspaceActivated(const std::string& line);

    static std::optional<std::string> parseJsonStringField(const std::string& input,
                                                           std::size_t from,
                                                           const char* key);
    static std::optional<std::uint64_t> parseJsonUintField(const std::string& input,
                                                           std::size_t from,
                                                           const char* key);
    static std::size_t findMatchingBracket(const std::string& input, std::size_t open_pos);
    static std::size_t findMatchingBrace(const std::string& input, std::size_t open_pos);

    void logFocusedWorkspace(std::uint64_t id);

    int m_socket_fd{-1};
    std::atomic<bool> m_running{false};
    std::thread m_reader_thread;
    std::string m_read_buffer;
    std::unordered_map<std::uint64_t, std::string> m_workspace_labels;
    std::optional<std::uint64_t> m_last_focused_workspace;
};
