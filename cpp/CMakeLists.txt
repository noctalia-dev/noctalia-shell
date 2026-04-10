cmake_minimum_required(VERSION 3.24)
project(NoctaliaMultimedia LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick DBus OpenGL)
find_package(PkgConfig REQUIRED)

# nixpkgs' libprojectm ships a broken projectM-4.pc that emits "-l:projectM-4"
# (GCC exact-filename syntax) instead of "-lprojectM-4". The literal filename
# doesn't exist (the real file is libprojectM-4.so), so pkg_check_modules fails
# to link. Workaround: pull cflags + libdir from pkg-config, then resolve the
# library via find_library() to get a full path the linker can handle.
execute_process(
    COMMAND pkg-config --cflags-only-I projectM-4
    OUTPUT_VARIABLE PROJECTM_INCLUDE_FLAGS
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
execute_process(
    COMMAND pkg-config --variable=libdir projectM-4
    OUTPUT_VARIABLE PROJECTM_LIBDIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)
# Convert "-I/path/to/include" flags into a bare path list for target_include_directories
string(REGEX REPLACE "-I" "" PROJECTM_INCLUDE_DIRS_RAW "${PROJECTM_INCLUDE_FLAGS}")
separate_arguments(PROJECTM_INCLUDE_DIRS UNIX_COMMAND "${PROJECTM_INCLUDE_DIRS_RAW}")

find_library(PROJECTM_LIB
    NAMES "projectM-4"
    HINTS "${PROJECTM_LIBDIR}"
    NO_DEFAULT_PATH
    REQUIRED
)

pkg_check_modules(PULSE REQUIRED libpulse-simple)

add_library(noctaliaMultimediaplugin SHARED
    plugin.cpp
    ProjectMItem.h
    ProjectMItem.cpp
)

target_include_directories(noctaliaMultimediaplugin PRIVATE
    ${PROJECTM_INCLUDE_DIRS}
    ${PULSE_INCLUDE_DIRS}
)

target_link_directories(noctaliaMultimediaplugin PRIVATE
    ${PULSE_LIBRARY_DIRS}
)

target_link_libraries(noctaliaMultimediaplugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::DBus
    Qt6::OpenGL
    ${PROJECTM_LIB}
    ${PULSE_LIBRARIES}
)

install(TARGETS noctaliaMultimediaplugin
    LIBRARY DESTINATION lib/qt6/qml/qs/Multimedia
)
install(FILES qmldir DESTINATION lib/qt6/qml/qs/Multimedia)
