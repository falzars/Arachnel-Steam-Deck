import QtQuick
import QtQuick.Layouts

import Arachnel.Core 1.0
import Qcm.Material as MD

Item {
    id: root

    required property int index
    required property string gameId
    required property string title
    required property string coverUrl
    required property string sourceName

    signal openDetails(string gameId)

    activeFocusOnTab: true

    readonly property string displayTitle: {
        const t = (root.title || "").trim()
        if (t.length && t !== root.gameId)
            return t
        const info = Core.entryDetails(root.gameId)
        const live = String(info.title || "").trim()
        return live.length ? live : (t.length ? t : root.gameId)
    }

    readonly property string displayCoverUrl: {
        const local = (root.coverUrl || "")
        if (local.startsWith("file:"))
            return local
        const info = Core.entryDetails(root.gameId)
        const live = String(info.coverUrl || "")
        if (live.startsWith("file:"))
            return live
        return local.startsWith("file:") ? local : ""
    }

    readonly property string displaySourceName: {
        const s = (root.sourceName || "").trim()
        if (s.length)
            return s
        const info = Core.entryDetails(root.gameId)
        return String(info.sourceName || info.sourceId || "")
    }

    function requestCover() {
        if (!root.gameId.length || !root.visible || !root.enabled)
            return
        Core.requestCatalogCover(root.gameId)
    }

    function focusIndex(nextIndex) {
        const view = GridView.view
        if (!view || nextIndex < 0 || nextIndex >= view.count)
            return false
        view.currentIndex = nextIndex
        Qt.callLater(function () {
            if (view.currentItem)
                view.currentItem.forceActiveFocus(Qt.TabFocusReason)
        })
        return true
    }

    function focusOutside(forward) {
        const item = root.nextItemInFocusChain(forward)
        if (item && item !== root)
            item.forceActiveFocus(Qt.TabFocusReason)
    }

    Keys.onPressed: function(event) {
        const view = GridView.view
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space || event.key === Qt.Key_Select) {
            root.openDetails(root.gameId)
            event.accepted = true
            return
        }
        if (!view)
            return

        const columns = Math.max(1, Math.floor(view.width / Math.max(1, view.cellWidth)))
        const col = root.index % columns
        let target = -1
        if (event.key === Qt.Key_Right) {
            if (col < columns - 1 && root.index + 1 < view.count)
                target = root.index + 1
            else
                root.focusOutside(true)
        } else if (event.key === Qt.Key_Left) {
            if (col > 0)
                target = root.index - 1
            else
                root.focusOutside(false)
        } else if (event.key === Qt.Key_Down) {
            if (root.index + columns < view.count)
                target = root.index + columns
            else
                root.focusOutside(true)
        } else if (event.key === Qt.Key_Up) {
            if (root.index - columns >= 0)
                target = root.index - columns
            else
                root.focusOutside(false)
        } else {
            return
        }

        if (target >= 0)
            root.focusIndex(target)
        event.accepted = true
    }

    onActiveFocusChanged: {
        if (activeFocus && GridView.view) {
            GridView.view.currentIndex = root.index
            GridView.view.positionViewAtIndex(root.index, GridView.Contain)
        }
    }

    Timer {
        id: coverTimer
        interval: 60
        onTriggered: root.requestCover()
    }

    Component.onCompleted: coverTimer.start()
    onGameIdChanged: coverTimer.restart()
    onVisibleChanged: {
        if (visible)
            coverTimer.restart()
    }

    Connections {
        target: Core
        function onEntryMetadataChanged(entryId) {
            if (entryId === root.gameId)
                coverTimer.restart()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.rightMargin: MD.Token.spacing.small
        spacing: MD.Token.spacing.small

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GamePoster {
                anchors.fill: parent
                source: root.displayCoverUrl
                seed: root.displayTitle
                fallbackText: root.displayTitle.length ? root.displayTitle.charAt(0) : "?"
                cornerRadius: MD.Token.shape.corner.large
                hoverScaleEnabled: true
                onClicked: {
                    root.forceActiveFocus(Qt.MouseFocusReason)
                    root.openDetails(root.gameId)
                }
                onLoadFailed: {
                    if (root.displayCoverUrl.startsWith("file:"))
                        Core.invalidateCatalogCover(root.gameId)
                }
            }
        }

        MD.Label {
            Layout.fillWidth: true
            text: root.displayTitle
            typescale: MD.Token.typescale.title_small
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        MD.Label {
            Layout.fillWidth: true
            visible: root.displaySourceName.length > 0
            text: root.displaySourceName
            color: MD.Token.color.on_surface_variant
            typescale: MD.Token.typescale.label_medium
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.rightMargin: MD.Token.spacing.small
        radius: MD.Token.shape.corner.large
        color: "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: MD.Token.color.primary
        visible: root.activeFocus
        z: 50
    }
}
