set positional-arguments

mode := "debug"
build-dir := "build-" + mode

default:
    @just --list

configure m=mode:
    #!/usr/bin/env bash
    set -euo pipefail
    args=(--buildtype={{ if m == "release" { "release" } else { "debug" } }})
    [[ "{{m}}" == "release" ]] && args+=(-Db_lto=true)
    [[ "{{m}}" == "asan"    ]] && args+=(-Db_sanitize=address,undefined)
    if [[ -d "build-{{m}}" ]]; then
        meson setup "build-{{m}}" "${args[@]}" --reconfigure
    else
        meson setup "build-{{m}}" "${args[@]}"
    fi

build m=mode:
    meson compile -C build-{{m}}

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
