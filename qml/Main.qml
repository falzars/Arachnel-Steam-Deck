import QtQuick
import QtQuick.Window

import Arachnel.Core 1.0
import Qcm.Material as MD

AppWindow {
    id: appWindow

    // Steam Deck / Gamescope is a fixed 1280x800 target. Keep the normal desktop
    // geometry unchanged, but make Gaming Mode deliberately handheld-first.
    width: Core.gamingMode ? 1280 : 1450
    height: Core.gamingMode ? 800 : 900
    minimumWidth: Core.gamingMode ? 960 : 1100
    minimumHeight: Core.gamingMode ? 600 : 720
    visibility: Core.gamingMode ? Window.FullScreen : Window.Windowed

    ControllerHintBar {
        z: 5000
        visible: Core.gamingMode
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        width: Math.min(parent.width - 32, 760)
        primaryAction: appWindow.detailsOpen ? qsTr("Activate") : qsTr("Select")
        secondaryAction: qsTr("Back")
    }
}
