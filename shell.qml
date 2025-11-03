

/*
 * Noctalia – made by https://github.com/noctalia-dev
 * Licensed under the MIT License.
 * Forks and modifications are allowed under the MIT License,
 * but proper credit must be given to the original author.
*/
import QtQuick
import Quickshell

ShellRoot {
  id: shellRoot

  readonly property bool runGreeter: Quickshell.env("NOCTALIA_RUN_GREETER") === "1" || Quickshell.env("NOCTALIA_RUN_GREETER") === "true"

  Loader {
    id: shellLoader
    asynchronous: false
    sourceComponent: NoctaliaShell {}
    active: !shellRoot.runGreeter
  }

  Loader {
    id: greeterLoader
    asynchronous: false
    sourceComponent: NoctaliaGreeter {}
    active: shellRoot.runGreeter
  }
}
