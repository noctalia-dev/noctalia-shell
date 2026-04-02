cmake_minimum_required(VERSION 3.20)
project(Noctalia VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Export compile_commands.json for tooling
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- Dependencies ---
find_package(sdbus-c++ REQUIRED)
set(SDBUS_TARGET SDBusCpp::sdbus-c++)

# --- Target ---
add_executable(noctalia
    src/main.cpp
    src/app/Application.cpp
    src/notification/NotificationManager.cpp
    src/dbus/notification/NotificationService.cpp
)

target_include_directories(noctalia PRIVATE src)
target_link_libraries(noctalia PRIVATE ${SDBUS_TARGET})

target_compile_options(noctalia PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wconversion
    -Wshadow
)
