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

install m=mode:
    meson install -C build-{{m}}

format:
    find src \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 clang-format -i
    find src \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 grep -ZlP '\s+$' | xargs -0 -r sed -i 's/[[:space:]]*$//'

clean m=mode:
    rm -rf build-{{m}}

rebuild m=mode:
    just clean {{m}}
    just configure {{m}}
    just build {{m}}
