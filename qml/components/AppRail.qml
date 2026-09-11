import QtQuick
import QtQuick.Layouts

import Qcm.Material as MD

MD.Pane {
    id: root

    property int currentIndex: 0
    property var model: []
    property int downloadBadge: 0
    // model.length is a real final controller slot: Settings.
    property int keyboardIndex: currentIndex

    signal activated(int index)
    signal settingsRequested()

    padding: 0
    backgroundColor: MD.Token.color.surface_container
    implicitWidth: 108
    activeFocusOnTab: true
    focus: true

    function isInsideRail(item) {
        let current = item
        while (current) {
            if (current === root)
                return true
            current = current.parent
        }
        return false
    }

    function focusPageContent() {
        let next = root.nextItemInFocusChain(true)
        let guard = 0
        while (next && root.isInsideRail(next) && guard++ < 64)
            next = next.nextItemInFocusChain(true)
        if (next && next !== root)
            next.forceActiveFocus(Qt.TabFocusReason)
    }

    function activateKeyboardItem(enterContent) {
        const count = root.model ? root.model.length : 0
        if (root.keyboardIndex >= count) {
            root.settingsRequested()
            return
        }
        root.activated(root.keyboardIndex)
        if (!enterContent)
            return
        Qt.callLater(root.focusPageContent)
    }

    Keys.onPressed: function(event) {
        const count = root.model ? root.model.length : 0
        if (count === 0)
            return

        const backwardsTab = event.key === Qt.Key_Backtab
                             || (event.key === Qt.Key_Tab
                                 && (event.modifiers & Qt.ShiftModifier))
        const forwardsTab = event.key === Qt.Key_Tab && !backwardsTab

        if (forwardsTab) {
            // Steam Deck directions are translated to Tab. While focus is on
            // the rail, keep that traversal inside the rail until A is pressed.
            root.keyboardIndex = Math.min(count, root.keyboardIndex + 1)
            event.accepted = true
        } else if (backwardsTab) {
            root.keyboardIndex = Math.max(0, root.keyboardIndex - 1)
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            root.keyboardIndex = Math.min(count, root.keyboardIndex + 1)
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            root.keyboardIndex = Math.max(0, root.keyboardIndex - 1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            root.activateKeyboardItem(true)
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space || event.key === Qt.Key_Select) {
            root.activateKeyboardItem(true)
            event.accepted = true
        } else if (event.key === Qt.Key_S) {
            root.settingsRequested()
            event.accepted = true
        }
    }

    onCurrentIndexChanged: {
        if (!root.activeFocus || root.keyboardIndex < (root.model ? root.model.length : 0))
            keyboardIndex = currentIndex
    }

    onActiveFocusChanged: {
        if (activeFocus && keyboardIndex < 0)
            keyboardIndex = currentIndex
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: MD.Token.spacing.medium
        anchors.bottomMargin: MD.Token.spacing.medium
        spacing: MD.Token.spacing.extra_small

        MD.ElevationRectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            radius: MD.Token.shape.corner.extra_large
            color: MD.Token.color.primary_container
            elevation: MD.Token.elevation.level0

            SpiderWebMark {
                anchors.centerIn: parent
                width: 28
                height: 28
                strokeColor: MD.Token.color.on_primary_container
                strokeWidth: 1.6
                rings: 3
                spokes: 8
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.keyboardIndex = 0
                    root.forceActiveFocus()
                    root.activated(0)
                }
            }
        }

        Item { Layout.preferredHeight: MD.Token.spacing.small }

        Repeater {
            model: root.model

            Item {
                id: railEntry
                required property int index
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 72
                Layout.leftMargin: MD.Token.spacing.small
                Layout.rightMargin: MD.Token.spacing.small

                readonly property bool selected: index === root.currentIndex
                readonly property bool deckFocused: root.activeFocus && index === root.keyboardIndex

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 36

                        MD.ElevationRectangle {
                            anchors.centerIn: parent
                            width: 64
                            height: 36
                            radius: MD.Token.shape.corner.full
                            color: railEntry.selected
                                   ? MD.Token.color.secondary_container
                                   : railEntry.deckFocused
                                     ? MD.Token.color.surface_container_highest
                                     : "transparent"
                            border.width: railEntry.deckFocused ? 2 : 0
                            border.color: MD.Token.color.primary
                            elevation: MD.Token.elevation.level0
                            scale: railEntry.selected ? 1 : 0.92
                            transformOrigin: Item.Center

                            Behavior on color { ColorAnimation { duration: MD.Token.duration.short4 } }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: MD.Token.duration.short4
                                    easing: MD.Token.easing.emphasized_decelerate
                                }
                            }

                            MD.Icon {
                                anchors.centerIn: parent
                                name: railEntry.modelData.icon
                                size: 24
                                color: railEntry.selected
                                       ? MD.Token.color.on_secondary_container
                                       : MD.Token.color.on_surface_variant
                            }

                            MD.Badge {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: 4
                                anchors.topMargin: 2
                                visible: !!railEntry.modelData.showDownloadBadge && root.downloadBadge > 0
                                text: root.downloadBadge > 9 ? "9+" : String(root.downloadBadge)
                                backgroundColor: MD.Token.color.primary
                                textColor: MD.Token.color.on_primary
                            }
                        }
                    }

                    MD.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: 2
                        Layout.rightMargin: 2
                        horizontalAlignment: Text.AlignHCenter
                        text: railEntry.modelData.name
                        typescale: MD.Token.typescale.label_small
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: railEntry.selected ? MD.Token.color.on_surface : MD.Token.color.on_surface_variant
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.keyboardIndex = railEntry.index
                    onClicked: {
                        root.keyboardIndex = railEntry.index
                        root.forceActiveFocus()
                        root.activated(railEntry.index)
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: root.activeFocus && root.keyboardIndex === (root.model ? root.model.length : 0) ? 2 : 0
                border.color: MD.Token.color.primary
            }

            MD.IconButton {
                anchors.centerIn: parent
                mdState.type: MD.Enum.IBtStandard
                icon.name: MD.Token.icon.settings
                onClicked: {
                    root.keyboardIndex = root.model ? root.model.length : 0
                    root.forceActiveFocus()
                    root.settingsRequested()
                }
            }
        }
    }
}
