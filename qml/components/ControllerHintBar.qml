import QtQuick
import QtQuick.Layouts

import Qcm.Material as MD

Rectangle {
    id: root

    implicitHeight: 50
    radius: 15
    color: MD.Token.color.surface_container_high
    border.width: 1
    border.color: MD.Token.color.outline_variant

    property string primaryAction: qsTr("Select")
    property string secondaryAction: qsTr("Back")

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 14

        RowLayout {
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
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
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 14
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
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 86
                Layout.preferredHeight: 28
                radius: 14
                color: MD.Token.color.surface_container_highest
                border.width: 1
                border.color: MD.Token.color.outline
                MD.Label {
                    anchors.centerIn: parent
                    text: "D-PAD / STICK"
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

        RowLayout {
            spacing: 6
            Rectangle {
                Layout.preferredWidth: 62
                Layout.preferredHeight: 28
                radius: 14
                color: MD.Token.color.surface_container_highest
                border.width: 1
                border.color: MD.Token.color.outline
                MD.Label {
                    anchors.centerIn: parent
                    text: "L1 / R1"
                    color: MD.Token.color.on_surface
                    typescale: MD.Token.typescale.label_small
                }
            }
            MD.Label {
                text: qsTr("Previous / Next")
                color: MD.Token.color.on_surface
                typescale: MD.Token.typescale.label_medium
            }
        }
    }
}
