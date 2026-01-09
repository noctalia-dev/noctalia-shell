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
                                       38: migration38Component
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
}
