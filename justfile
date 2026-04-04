set positional-arguments

build-dir := "build"

default:
    @just --list

configure mode="debug":
    cmake -S . -B {{build-dir}} -DCMAKE_BUILD_TYPE={{ if mode == "release" { "Release" } else { "Debug" } }}

build:
    cmake --build {{build-dir}} --parallel

run:
    ./{{build-dir}}/noctalia

format:
    clang-format -i src/**/*.cpp src/**/*.h

clean:
    rm -rf {{build-dir}}

rebuild mode="debug":
    just clean
    just configure {{mode}}
    just build
