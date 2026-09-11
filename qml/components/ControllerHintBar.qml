import QtQuick
import QtQuick.Layouts

import Qcm.Material as MD

Rectangle {
    id: root

    implicitHeight: 46
    radius: 14
    color: MD.Token.color.surface_container_high
    border.width: 1
    border.color: MD.Token.color.outline_variant

    property string primaryAction: qsTr("Select")
    property string secondaryAction: qsTr("Back")

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 18

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: 7
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: MD.Token.color.primary
                MD.Label {
                    anchors.centerIn: parent
                    text: "A"
                    color: MD.Token.color.on_primary
                    typescale: MD.Token.typescale.label_medium
                }
            }
            MD.Label {
                text: root.primaryAction
                color: MD.Token.color.on_surface
                typescale: MD.Token.typescale.label_medium
            }
        }

        RowLayout {
            spacing: 7
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: MD.Token.color.surface_container_highest
                border.width: 1
                border.color: MD.Token.color.outline
                MD.Label {
                    anchors.centerIn: parent
                    text: "B"
                    color: MD.Token.color.on_surface
                    typescale: MD.Token.typescale.label_medium
                }
            }
            MD.Label {
                text: root.secondaryAction
                color: MD.Token.color.on_surface
                typescale: MD.Token.typescale.label_medium
            }
        }

        RowLayout {
            spacing: 7
            Rectangle {
                Layout.preferredWidth: 54
                Layout.preferredHeight: 26
                radius: 13
                color: MD.Token.color.surface_container_highest
                border.width: 1
                border.color: MD.Token.color.outline
                MD.Label {
                    anchors.centerIn: parent
                    text: "D-PAD"
                    color: MD.Token.color.on_surface
                    typescale: MD.Token.typescale.label_small
                }
            }
            MD.Label {
                text: qsTr("Navigate")
                color: MD.Token.color.on_surface
                typescale: MD.Token.typescale.label_medium
            }
        }

        Item { Layout.fillWidth: true }
    }
}
