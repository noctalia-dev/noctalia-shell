set positional-arguments

mode := "debug"
build-dir := "build-" + mode
prefix := "/usr/local"

default:
    @just --list

configure m=mode p=prefix:
    #!/usr/bin/env bash
    set -euo pipefail
    args=(--buildtype={{ if m == "release" { "release" } else { "debug" } }})
    [[ "{{m}}" == "release" ]] && args+=(-Db_lto=true)
    [[ "{{m}}" == "asan"    ]] && args+=(-Db_sanitize=address,undefined)
    if [[ -d "build-{{m}}" ]]; then
        meson setup "build-{{m}}" "${args[@]}" --prefix={{p}} --reconfigure
    else
        meson setup "build-{{m}}" "${args[@]}" --prefix={{p}}
    fi
    ln -sfn "build-{{m}}/compile_commands.json" compile_commands.json

build m=mode: (_ensure-configured m)
    meson compile -C build-{{m}}

_ensure-configured m=mode:
    @if [ ! -d "build-{{m}}" ]; then just configure {{m}}; fi

run m=mode: (build m)
    ./build-{{m}}/noctalia

install m=mode p=prefix: (configure m p)
    meson install -C build-{{m}}

uninstall m=mode:
    ninja -C build-{{m}} uninstall

format:
    find src \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 clang-format -i
    find src \( -name '*.cpp' -o -name '*.h' \) -print0 | xargs -0 grep -ZlP '\s+$' | xargs -0 -r sed -i 's/[[:space:]]*$//'

clean m=mode:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -L compile_commands.json && "$(readlink compile_commands.json)" == "build-{{m}}/compile_commands.json" ]]; then
        rm -f compile_commands.json
    fi
    rm -rf build-{{m}}

rebuild m=mode: (clean m) (build m)
