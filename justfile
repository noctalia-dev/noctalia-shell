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
    @if [ "{{m}}" = "debug" ] || [ "{{m}}" = "asan" ]; then \
      cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/noctalia"; \
      mkdir -p "$cache_dir"; \
      logfile="$cache_dir/noctalia-$(date +%Y%m%d-%H%M%S).log"; \
      echo "Writing logs to $logfile"; \
      ./build-{{m}}/noctalia 2>&1 | tee -a "$logfile"; \
    else \
      ./build-{{m}}/noctalia; \
    fi

format:
    clang-format -i src/**/*.cpp src/**/*.h
    find src \( -name '*.cpp' -o -name '*.h' \) | xargs grep -rlP '\s+$' | xargs -r sed -i 's/[[:space:]]*$//'

clean m=mode:
    rm -rf build-{{m}}

rebuild m=mode:
    just clean {{m}}
    just configure {{m}}
    just build {{m}}
