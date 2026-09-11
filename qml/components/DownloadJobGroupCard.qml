import QtQuick
import QtQuick.Layouts

import Arachnel.Core 1.0
import Qcm.Material as MD

MD.ElevationRectangle {
    id: root

    property var group: ({})
    property bool expanded: false
    property int controllerIndex: -1
    property var controllerView: null

    signal openDetails(string entryId)
    signal expansionToggled(bool expanded)

    readonly property var addons: group.addons ?? []
    readonly property bool hasAddons: !!(group.hasAddons) && addons.length > 0
    readonly property bool gameJobActive: jobIsActive(root.group)
    readonly property int expandColumnWidth: root.hasAddons ? 40 : 0

    activeFocusOnTab: true

    function focusChain(forward) {
        const item = root.nextItemInFocusChain(forward)
        if (item && item !== root)
            item.forceActiveFocus(Qt.TabFocusReason)
    }

    function focusControllerRow(nextIndex) {
        const view = root.controllerView
        if (!view || nextIndex < 0 || nextIndex >= view.count)
            return false
        view.currentIndex = nextIndex
        view.positionViewAtIndex(nextIndex, ListView.Contain)
        Qt.callLater(function () {
            if (view.currentItem && view.currentItem.cardItem)
                view.currentItem.cardItem.forceActiveFocus(Qt.TabFocusReason)
        })
        return true
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up) {
            if (!root.focusControllerRow(root.controllerIndex - 1))
                root.focusChain(false)
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            if (!root.focusControllerRow(root.controllerIndex + 1))
                root.focusChain(true)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            if (root.hasAddons && !root.expanded)
                root.expansionToggled(true)
            else
                root.focusChain(true)
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            if (root.hasAddons && root.expanded)
                root.expansionToggled(false)
            else
                root.focusChain(false)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            const entryId = root.group.entryId ?? ""
            if (entryId.length)
                root.openDetails(entryId)
            event.accepted = true
        }
    }

    onActiveFocusChanged: {
        if (activeFocus && root.controllerView && root.controllerIndex >= 0) {
            root.controllerView.currentIndex = root.controllerIndex
            root.controllerView.positionViewAtIndex(root.controllerIndex, ListView.Contain)
        }
    }

    function jobIsActive(job) {
        if (!job || !job.status)
            return false
        return ["starting", "checking", "metadata", "queued", "downloading", "seeding", "paused", "installing"].includes(job.status)
    }

    function addonTitle(job) {
        const full = job.title ?? ""
        const sep = " - "
        const idx = full.indexOf(sep)
        return idx >= 0 ? full.substring(idx + sep.length) : full
    }

    function toggleExpanded() {
        root.expansionToggled(!root.expanded)
    }

    function collapsedAddonSummary() {
        let active = 0
        let done = 0
        for (let i = 0; i < addons.length; ++i) {
            if (jobIsActive(addons[i]))
                ++active
            if (addons[i].status === "completed")
                ++done
        }
        if (active > 0)
            return qsTr("%1 add-ons · %2 downloading").arg(addons.length).arg(active)
        if (done === addons.length)
            return qsTr("%1 add-ons · done").arg(addons.length)
        return qsTr("%1 add-ons").arg(addons.length)
    }

    function parseSizeLabelBytes(label) {
        if (!label || !label.length)
            return 0
        const m = /^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)/i.exec(label.trim())
        if (!m)
            return 0
        let v = parseFloat(m[1])
        const unit = m[2].toUpperCase()
        if (unit === "KB")
            v *= 1024
        else if (unit === "MB")
            v *= 1024 * 1024
        else if (unit === "GB")
            v *= 1024 * 1024 * 1024
        else if (unit === "TB")
            v *= 1024 * 1024 * 1024 * 1024
        return v
    }

    readonly property var entryInfo: {
        const id = root.group.entryId ?? ""
        return id.length ? Core.entryDetails(id) : ({})
    }

    readonly property real catalogTotalBytes: root.parseSizeLabelBytes(root.entryInfo.sizeLabel ?? "")

    function groupAllTerminal() {
        if (!["completed", "failed", "cancelled"].includes(group.status ?? ""))
            return false
        for (let i = 0; i < addons.length; ++i) {
            if (!["completed", "failed", "cancelled"].includes(addons[i].status ?? ""))
                return false
        }
        return true
    }

    function removeWholeGroup() {
        Core.removeJob(group.jobId)
        for (let i = 0; i < addons.length; ++i)
            Core.removeJob(addons[i].jobId)
    }

    radius: MD.Token.shape.corner.extra_large
    color: MD.Token.color.surface_container
    elevation: MD.Token.elevation.level0
    implicitHeight: groupCol.implicitHeight + 2 * MD.Token.spacing.large

    ColumnLayout {
        id: groupCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: MD.Token.spacing.large
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: MD.Token.spacing.small

            Item {
                Layout.preferredWidth: root.hasAddons ? root.expandColumnWidth : 0
                Layout.preferredHeight: root.expandColumnWidth
                Layout.alignment: Qt.AlignTop
                // Keep the item in the layout tree — toggling visible caused
                // RowLayout "recursive rearrange" during job updates.
                opacity: root.hasAddons ? 1 : 0
                enabled: root.hasAddons
                clip: true

                MD.IconButton {
                    anchors.centerIn: parent
                    mdState.type: MD.Enum.IBtStandard
                    rotation: root.expanded ? 90 : 0
                    icon.name: MD.Token.icon.chevron_right
                    onClicked: root.toggleExpanded()

                    Behavior on rotation {
                        NumberAnimation {
                            duration: MD.Token.duration.short4
                            easing: MD.Token.easing.standard
                        }
                    }
                }
            }

            DownloadJobCard {
                id: gameCard
                Layout.fillWidth: true
                embedded: true
                showExternalRemove: root.groupAllTerminal()
                jobId: root.group.jobId ?? ""
                title: root.group.title ?? ""
                kindLabel: root.group.kindLabel ?? ""
                status: root.group.status ?? ""
                statusLabel: root.group.statusLabel ?? ""
                progress: root.group.progress ?? 0
                bytesDownloaded: root.group.bytesDownloaded ?? 0
                totalBytes: (root.group.totalBytes ?? 0) > 0
                              ? root.group.totalBytes
                              : root.catalogTotalBytes
                catalogTotalBytes: root.catalogTotalBytes
                detail: root.group.detail ?? ""
                coverUrl: root.group.coverUrl ?? ""
                entryId: root.group.entryId ?? ""
                fillProgress: root.gameJobActive ? (root.group.progress ?? 0) : -1
                onOpenDetails: function (entryId) { root.openDetails(entryId) }
                onRemoveRequested: root.hasAddons ? root.removeWholeGroup()
                                                  : Core.removeJob(root.group.jobId)
            }
        }

        MD.Label {
            Layout.fillWidth: true
            Layout.leftMargin: root.hasAddons
                               ? root.expandColumnWidth + MD.Token.spacing.small
                               : 0
            Layout.topMargin: MD.Token.spacing.extra_small
            visible: root.hasAddons && !root.expanded
            text: collapsedAddonSummary()
            color: MD.Token.color.on_surface_variant
            typescale: MD.Token.typescale.label_medium
            elide: Text.ElideRight
        }

        ColumnLayout {
            id: addonsPanel
            Layout.fillWidth: true
            Layout.leftMargin: root.hasAddons
                               ? root.expandColumnWidth + MD.Token.spacing.small
                               : 0
            Layout.topMargin: MD.Token.spacing.small
            visible: root.hasAddons && root.expanded
            spacing: MD.Token.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: MD.Token.spacing.small

                MD.Icon {
                    name: MD.Token.icon.extension
                    size: 18
                    color: MD.Token.color.primary
                }

                MD.Label {
                    Layout.fillWidth: true
                    text: qsTr("Add-ons")
                    typescale: MD.Token.typescale.label_large
                    color: MD.Token.color.on_surface_variant
                }

                MD.Label {
                    text: collapsedAddonSummary()
                    color: MD.Token.color.on_surface_variant
                    typescale: MD.Token.typescale.label_small
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: MD.Token.color.outline_variant
            }

            Repeater {
                model: root.addons

                ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0

                    DownloadJobCard {
                        Layout.fillWidth: true
                        embedded: true
                        compact: true
                        addonRow: true
                        jobId: modelData.jobId ?? ""
                        title: root.addonTitle(modelData)
                        kindLabel: modelData.kindLabel ?? ""
                        status: modelData.status ?? ""
                        statusLabel: modelData.statusLabel ?? ""
                        progress: modelData.progress ?? 0
                        bytesDownloaded: modelData.bytesDownloaded ?? 0
                        totalBytes: modelData.totalBytes ?? 0
                        detail: modelData.detail ?? ""
                        coverUrl: modelData.coverUrl ?? ""
                        entryId: modelData.entryId ?? ""
                        parentEntryId: modelData.parentEntryId ?? root.group.entryId ?? ""
                        onOpenDetails: function (entryId) { root.openDetails(entryId) }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: MD.Token.spacing.small
                        Layout.preferredHeight: 1
                        visible: index < root.addons.length - 1
                        color: MD.Util.transparent(MD.Token.color.outline_variant, 0.65)
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        z: 100
        visible: root.activeFocus
        color: "transparent"
        radius: root.radius
        border.width: 2
        border.color: MD.Token.color.primary
    }
}
