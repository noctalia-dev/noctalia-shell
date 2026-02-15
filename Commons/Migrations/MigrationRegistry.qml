pragma Singleton

import QtQuick

QtObject {
  id: root

  // Map of version number to migration component
  readonly property var migrations: ({
                                       27: migration27Component,
                                       28: migration28Component,
                                       32: migration32Component,
                                       33: migration33Component,
                                       35: migration35Component,
                                       36: migration36Component,
                                       37: migration37Component,
                                       38: migration38Component,
                                       40: migration40Component,
                                       42: migration42Component,
                                       43: migration43Component,
                                       44: migration44Component,
                                       45: migration45Component,
                                       46: migration46Component,
                                       47: migration47Component,
                                       48: migration48Component,
                                       49: migration49Component,
                                       50: migration50Component,
                                       53: migration53Component
                                     })

  // Migration components
  property Component migration27Component: Migration27 {}
  property Component migration28Component: Migration28 {}
  property Component migration32Component: Migration32 {}
  property Component migration33Component: Migration33 {}
  property Component migration35Component: Migration35 {}
  property Component migration36Component: Migration36 {}
  property Component migration37Component: Migration37 {}
  property Component migration38Component: Migration38 {}
  property Component migration40Component: Migration40 {}
  property Component migration42Component: Migration42 {}
  property Component migration43Component: Migration43 {}
  property Component migration44Component: Migration44 {}
  property Component migration45Component: Migration45 {}
  property Component migration46Component: Migration46 {}
  property Component migration47Component: Migration47 {}
  property Component migration48Component: Migration48 {}
  property Component migration49Component: Migration49 {}
  property Component migration50Component: Migration50 {}
  property Component migration53Component: Migration53 {}
}
