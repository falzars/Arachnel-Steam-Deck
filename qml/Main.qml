import QtQuick
import QtQuick.Window

import Arachnel.Core 1.0
import Qcm.Material as MD

AppWindow {
    id: appWindow

    width: Core.gamingMode ? 1280 : 1450
    height: Core.gamingMode ? 800 : 900
    minimumWidth: Core.gamingMode ? 960 : 1100
    minimumHeight: Core.gamingMode ? 600 : 720
    visibility: Core.gamingMode ? Window.FullScreen : Window.Windowed

    // Keep a permanent, high-contrast indication of the item that A will act on.
    // The controller itself now follows Qt's single tab-focus path, so every
    // direction advances through one deterministic sequence instead of several
    // page-specific arrow handlers competing with each other.
    Rectangle {
        id: controllerFocusRing
        z: 4990
        color: "transparent"
        radius: 10
        border.width: 3
        border.color: MD.Token.color.primary
        visible: Core.gamingMode
                 && target
                 && target !== appWindow.contentItem
                 && target.visible !== false
                 && width > 10
                 && height > 10

        property var target: appWindow.activeFocusItem
        property point mappedPosition: target && target.mapToItem
                                       ? target.mapToItem(appWindow.contentItem, 0, 0)
                                       : Qt.point(0, 0)

        x: mappedPosition.x - 4
        y: mappedPosition.y - 4
        width: target ? target.width + 8 : 0
        height: target ? target.height + 8 : 0

        Behavior on x { NumberAnimation { duration: 80 } }
        Behavior on y { NumberAnimation { duration: 80 } }
        Behavior on width { NumberAnimation { duration: 80 } }
        Behavior on height { NumberAnimation { duration: 80 } }
    }

    ControllerHintBar {
        z: 5000
        visible: Core.gamingMode
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 14
        anchors.bottomMargin: 10
        width: Math.min(parent.width - 28, 790)
        primaryAction: qsTr("Select")
        secondaryAction: qsTr("Back")
    }
}
