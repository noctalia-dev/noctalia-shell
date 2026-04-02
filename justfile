set positional-arguments

build-dir := "build"
build-type := "Debug"

default:
    @just --list

configure type=build-type:
    cmake -S . -B {{build-dir}} -DCMAKE_BUILD_TYPE={{type}}

build:
    cmake --build {{build-dir}} --parallel

run:
    ./{{build-dir}}/noctalia

clean:
    rm -rf {{build-dir}}

rebuild type=build-type:
    just clean
    just configure {{type}}
    just build
