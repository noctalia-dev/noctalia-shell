set positional-arguments

mode := "debug"
build-dir := "build-" + mode

default:
    @just --list

configure m=mode:
    cmake -S . -B build-{{m}} \
      -DCMAKE_BUILD_TYPE={{ if m == "release" { "Release" } else { "Debug" } }} \
      -DSANITIZE={{ if m == "asan" { "ON" } else { "OFF" } }}

build m=mode:
    cmake --build build-{{m}} --parallel

run m=mode:
    ./build-{{m}}/noctalia

format:
    clang-format -i src/**/*.cpp src/**/*.h
    find src \( -name '*.cpp' -o -name '*.h' \) | xargs grep -rlP '\s+$' | xargs -r sed -i 's/[[:space:]]*$//'

clean m=mode:
    rm -rf build-{{m}}

rebuild m=mode:
    just clean {{m}}
    just configure {{m}}
    just build {{m}}
