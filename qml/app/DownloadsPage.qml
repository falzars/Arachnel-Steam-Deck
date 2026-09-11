import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window

import Arachnel.Core 1.0
import Qcm.Material as MD

Item {
    id: root

    readonly property int pageMargin: MD.Token.spacing.large
    property var expandedGroups: ({})
    readonly property bool downloadsEmpty: groupsModel.count === 0

    ListModel {
        id: groupsModel
    }

    function refreshGroups() {
        refreshDebounce.restart()
    }

    function applyGroups(nextGroups) {
        const next = nextGroups || []
        const list = jobsList

        let structural = groupsModel.count !== next.length
        if (!structural) {
            for (let i = 0; i < next.length; ++i) {
                if ((groupsModel.get(i).jobId ?? "") !== (next[i].jobId ?? "")) {
                    structural = true
                    break
                }
            }
        }

        if (structural) {
            const restore = list.visible && list.count > 0
                    && !list.moving && !list.flicking && !list.dragging
            const y = restore ? list.contentY : 0
            const selectedJobId = list.currentIndex >= 0 && list.currentIndex < groupsModel.count
                    ? (groupsModel.get(list.currentIndex).jobId ?? "") : ""
            groupsModel.clear()
            let restoredIndex = -1
            for (let i = 0; i < next.length; ++i) {
                groupsModel.append({ group: next[i], jobId: next[i].jobId ?? "" })
                if (selectedJobId.length && selectedJobId === (next[i].jobId ?? ""))
                    restoredIndex = i
            }
            if (groupsModel.count > 0)
                list.currentIndex = restoredIndex >= 0 ? restoredIndex : Math.min(Math.max(0, list.currentIndex), groupsModel.count - 1)
            else
                list.currentIndex = -1
            if (!restore)
                return
            function restoreY() {
                if (!list || list.moving || list.flicking || list.dragging)
                    return
                const maxY = Math.max(0, list.contentHeight - list.height)
                list.contentY = Math.min(Math.max(0, y), maxY)
            }
            Qt.callLater(function () {
                restoreY()
                Qt.callLater(restoreY)
            })
            return
        }

        // Same job rows — update in place so progress bars don't remount / re-animate.
        for (let i = 0; i < next.length; ++i) {
            groupsModel.setProperty(i, "group", next[i])
            groupsModel.setProperty(i, "jobId", next[i].jobId ?? "")
        }
    }

    Timer {
        id: refreshDebounce
        interval: 120
        onTriggered: root.applyGroups(Core.jobs.downloadGroups())
    }

    function isGroupExpanded(entryId) {
        return !!(entryId && expandedGroups[entryId])
    }

    function setGroupExpanded(entryId, value) {
        if (!entryId)
            return
        const next = Object.assign({}, expandedGroups)
        if (value)
            next[entryId] = true
        else
            delete next[entryId]
        expandedGroups = next
    }

    function countFinished() {
        return Core.jobs.count - Core.jobs.activeCount
    }

    function selectedGroup() {
        if (jobsList.currentIndex < 0 || jobsList.currentIndex >= groupsModel.count)
            return null
        return groupsModel.get(jobsList.currentIndex).group
    }

    function moveControllerSelection(delta) {
        if (groupsModel.count <= 0)
            return
        jobsList.currentIndex = Math.max(0, Math.min(groupsModel.count - 1,
                                                     jobsList.currentIndex + delta))
        jobsList.positionViewAtIndex(jobsList.currentIndex, ListView.Contain)
    }

    function moveControllerFocus(forward) {
        const window = root.Window.window
        const current = window ? window.activeFocusItem : null
        const source = current && current.nextItemInFocusChain ? current : root
        const next = source.nextItemInFocusChain(forward)
        if (next && next !== source)
            next.forceActiveFocus(Qt.TabFocusReason)
    }

    function focusSelectedRowActions() {
        const row = jobsList.currentItem
        const card = row ? row.cardItem : null
        if (!card)
            return
        card.forceActiveFocus(Qt.TabFocusReason)
        Qt.callLater(function () { card.focusChain(true) })
    }

    // Download rows handle their own D-pad navigation. If focus is on a normal
    // action button (for example Clear finished / pause / cancel), keep the D-pad
    // moving through the focus chain rather than stranding controller users.
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
            root.moveControllerFocus(true)
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
            root.moveControllerFocus(false)
            event.accepted = true
        }
    }

    Connections {
        target: Core.jobs
        function onJobsChanged() { root.refreshGroups() }
        function onCountChanged() { root.refreshGroups() }
    }

    Component.onCompleted: refreshGroups()

    signal openGame(string gameId)

    Item {
        anchors.fill: parent
        visible: root.downloadsEmpty

        ColumnLayout {
            anchors.centerIn: parent
            spacing: MD.Token.spacing.medium
            width: Math.min(parent.width - pageMargin * 2, 420)

            SpiderWebMark {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                width: 160
                height: 160
                strokeColor: MD.Token.color.primary
                strokeWidth: 2.5
                opacity: 0.35
            }

            MD.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("No downloads")
                typescale: MD.Token.typescale.title_large
            }

            MD.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Messages.downloadsEmptyHint
                color: MD.Token.color.on_surface_variant
                typescale: MD.Token.typescale.body_medium
                wrapMode: Text.WordWrap
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: MD.Token.spacing.medium
        visible: !root.downloadsEmpty

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: pageMargin
            Layout.rightMargin: pageMargin
            Layout.topMargin: MD.Token.spacing.large
            spacing: MD.Token.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                MD.Label {
                    text: qsTr("Downloads")
                    typescale: MD.Token.typescale.headline_medium
                }

                MD.Label {
                    text: {
                        const active = Core.jobs.activeCount
                        const finished = root.countFinished()
                        if (active > 0 && finished > 0)
                            return qsTr("%1 active · %2 finished").arg(active).arg(finished)
                        if (active > 0)
                            return qsTr("%1 active · will resume after restart").arg(active)
                        if (finished > 0)
                            return qsTr("%1 finished").arg(finished)
                        return qsTr("No downloads yet")
                    }
                    color: MD.Token.color.on_surface_variant
                    typescale: MD.Token.typescale.body_medium
                    elide: Text.ElideRight
                }
            }

            MD.Button {
                visible: root.countFinished() > 0
                text: qsTr("Clear finished")
                icon.name: MD.Token.icon.delete_sweep
                mdState.type: MD.Enum.BtText
                onClicked: Core.clearFinishedJobs()
            }
        }

        ListView {
            id: jobsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: pageMargin
            Layout.rightMargin: pageMargin
            Layout.bottomMargin: pageMargin
            clip: true
            spacing: MD.Token.spacing.medium
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            cacheBuffer: height * 2
            model: groupsModel
            activeFocusOnTab: true
            currentIndex: count > 0 ? 0 : -1

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                    root.moveControllerSelection(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.moveControllerSelection(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    const group = root.selectedGroup()
                    const entryId = group ? (group.entryId ?? "") : ""
                    const canExpand = group && !!group.hasAddons
                    if (canExpand && entryId.length && !root.isGroupExpanded(entryId))
                        root.setGroupExpanded(entryId, true)
                    else
                        root.focusSelectedRowActions()
                    event.accepted = true
                } else if (event.key === Qt.Key_Left) {
                    const group = root.selectedGroup()
                    if (group && (group.entryId ?? "").length && root.isGroupExpanded(group.entryId)) {
                        root.setGroupExpanded(group.entryId, false)
                    } else {
                        const previous = jobsList.nextItemInFocusChain(false)
                        if (previous && previous !== jobsList)
                            previous.forceActiveFocus(Qt.TabFocusReason)
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                           || event.key === Qt.Key_Space || event.key === Qt.Key_Select) {
                    const group = root.selectedGroup()
                    const entryId = group ? (group.entryId ?? "") : ""
                    if (entryId.length)
                        root.openGame(entryId)
                    event.accepted = true
                }
            }

            ScrollBar.vertical: MD.ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            highlightFollowsCurrentItem: true
            highlightMoveDuration: 90
            highlight: Rectangle {
                radius: MD.Token.shape.corner.extra_large
                color: "transparent"
                border.width: jobsList.activeFocus ? 2 : 0
                border.color: MD.Token.color.primary
            }

            delegate: Item {
                id: rowRoot
                width: jobsList.width
                height: Math.ceil(card.implicitHeight)
                required property int index
                required property var group
                required property string jobId
                property alias cardItem: card

                DownloadJobGroupCard {
                    id: card
                    width: parent.width
                    group: rowRoot.group
                    controllerIndex: rowRoot.index
                    controllerView: jobsList
                    expanded: root.isGroupExpanded(rowRoot.group.entryId ?? "")
                    onExpansionToggled: function (value) {
                        root.setGroupExpanded(rowRoot.group.entryId ?? "", value)
                    }
                    onOpenDetails: function (entryId) { root.openGame(entryId) }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    onEntered: jobsList.currentIndex = rowRoot.index
                    z: -1
                }
            }
        }
    }
}
