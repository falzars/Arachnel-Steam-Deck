import QtQuick
import QtQuick.Layouts

import Qcm.Material as MD

Flickable {
    id: root

    property int contentMargin: MD.Token.spacing.large
    readonly property bool onLinux: Qt.platform.os === "linux"
    property int controllerIndex: 0

    signal openSection(string sectionId)

    readonly property var sectionModel: {
        const sections = [
            {
                id: "plugins",
                title: qsTr("Plugins"),
                subtitle: qsTr("Install plugins to browse and play games.")
            },
            {
                id: "sources",
                title: qsTr("Hydra catalogs"),
                subtitle: qsTr("JSON catalog URLs")
            },
            {
                id: "friends",
                title: qsTr("Friends"),
                subtitle: qsTr("Invite codes and relay presence")
            },
            {
                id: "storage",
                title: qsTr("Storage"),
                subtitle: qsTr("Library and download folders")
            },
            {
                id: "updates",
                title: qsTr("Updates"),
                subtitle: qsTr("Game and launcher updates")
            },
            {
                id: "launch",
                title: qsTr("Launch"),
                subtitle: qsTr("Launch options and Proton on Linux")
            },
            {
                id: "appearance",
                title: qsTr("Appearance"),
                subtitle: qsTr("Theme, colors, and language")
            },
            {
                id: "about",
                title: qsTr("About"),
                subtitle: qsTr("Version and app data")
            }
        ]
        if (root.onLinux)
            return sections
        return sections.filter(function (entry) { return entry.id !== "launch" })
    }

    contentWidth: width
    contentHeight: body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    activeFocusOnTab: true

    function ensureControllerVisible() {
        const item = sectionRepeater.itemAt(root.controllerIndex)
        if (!item)
            return
        const p = item.mapToItem(body, 0, 0)
        const top = p.y - MD.Token.spacing.small
        const bottom = p.y + item.height + MD.Token.spacing.small
        if (top < root.contentY)
            root.contentY = Math.max(0, top)
        else if (bottom > root.contentY + root.height)
            root.contentY = Math.min(Math.max(0, root.contentHeight - root.height),
                                     bottom - root.height)
    }

    function activateControllerItem() {
        const entry = root.sectionModel[root.controllerIndex]
        if (entry)
            root.openSection(entry.id)
    }

    Keys.onPressed: function(event) {
        if (!root.sectionModel || root.sectionModel.length === 0)
            return
        if (event.key === Qt.Key_Down) {
            root.controllerIndex = Math.min(root.sectionModel.length - 1, root.controllerIndex + 1)
            root.ensureControllerVisible()
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            root.controllerIndex = Math.max(0, root.controllerIndex - 1)
            root.ensureControllerVisible()
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.key === Qt.Key_Right) {
            root.activateControllerItem()
            event.accepted = true
        }
    }

    Component.onCompleted: Qt.callLater(function () { root.forceActiveFocus(Qt.TabFocusReason) })
    onVisibleChanged: {
        if (visible)
            Qt.callLater(function () { root.forceActiveFocus(Qt.TabFocusReason) })
    }

    ColumnLayout {
        id: body
        width: root.width
        spacing: MD.Token.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: contentMargin
            Layout.rightMargin: contentMargin
            Layout.topMargin: MD.Token.spacing.small
            Layout.bottomMargin: MD.Token.spacing.small
            spacing: MD.Token.spacing.small

            Repeater {
                id: sectionRepeater
                model: root.sectionModel

                MD.Card {
                    id: sectionCard
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    type: MD.Enum.CardOutlined
                    verticalPadding: MD.Token.spacing.medium
                    horizontalPadding: MD.Token.spacing.medium
                    onClicked: {
                        root.controllerIndex = sectionCard.index
                        root.forceActiveFocus(Qt.MouseFocusReason)
                        root.openSection(sectionCard.modelData.id)
                    }

                    contentItem: RowLayout {
                        id: sectionRow
                        spacing: MD.Token.spacing.medium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            MD.Label {
                                Layout.fillWidth: true
                                text: sectionCard.modelData.title
                                typescale: MD.Token.typescale.title_small
                            }

                            MD.Label {
                                Layout.fillWidth: true
                                text: sectionCard.modelData.subtitle
                                color: MD.Token.color.on_surface_variant
                                typescale: MD.Token.typescale.body_small
                                wrapMode: Text.WordWrap
                            }
                        }

                        MD.Icon {
                            name: MD.Token.icon.chevron_right
                            size: 24
                            color: MD.Token.color.on_surface_variant
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: MD.Token.shape.corner.large
                        color: "transparent"
                        border.width: root.activeFocus && root.controllerIndex === sectionCard.index ? 2 : 0
                        border.color: MD.Token.color.primary
                        visible: border.width > 0
                        z: 20
                    }
                }
            }
        }
    }
}
