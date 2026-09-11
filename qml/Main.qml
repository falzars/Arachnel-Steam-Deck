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

    function moveControllerFocus(forward) {
        let current = appWindow.activeFocusItem
        if (!current || !current.nextItemInFocusChain)
            current = appWindow.contentItem

        let next = current.nextItemInFocusChain(forward)
        let guard = 0
        while (next && next !== current && guard++ < 128) {
            if (next.visible !== false && next.enabled !== false && next.forceActiveFocus) {
                next.forceActiveFocus(Qt.TabFocusReason)
                if (appWindow.activeFocusItem === next)
                    return
            }
            next = next.nextItemInFocusChain(forward)
        }
    }

    // Native Steam Deck gamepad input is translated to private function keys in
    // C++. Keeping those keys separate from ordinary arrow keys prevents a page
    // and the global controller layer from moving focus twice for one press.
    Shortcut {
        sequence: "F13"
        context: Qt.ApplicationShortcut
        onActivated: appWindow.moveControllerFocus(false)
    }
    Shortcut {
        sequence: "F14"
        context: Qt.ApplicationShortcut
        onActivated: appWindow.moveControllerFocus(true)
    }
    Shortcut {
        sequence: "F15"
        context: Qt.ApplicationShortcut
        onActivated: appWindow.moveControllerFocus(false)
    }
    Shortcut {
        sequence: "F16"
        context: Qt.ApplicationShortcut
        onActivated: appWindow.moveControllerFocus(true)
    }
    Shortcut {
        sequence: "F19"
        context: Qt.ApplicationShortcut
        onActivated: appWindow.moveControllerFocus(false)
    }
    Shortcut {
        sequence: "F20"
        context: Qt.ApplicationShortcut
        onActivated: appWindow.moveControllerFocus(true)
    }

    // A persistent focus frame makes it obvious what A will activate. This is
    // intentionally visual-only and does not change Arachnel's existing layout.
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

        Behavior on x { NumberAnimation { duration: 90 } }
        Behavior on y { NumberAnimation { duration: 90 } }
        Behavior on width { NumberAnimation { duration: 90 } }
        Behavior on height { NumberAnimation { duration: 90 } }
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
