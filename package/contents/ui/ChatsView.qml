/*
 * SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Item {
    id: view

    required property var controller
    property string deleteCandidateId: ""
    property string deleteCandidateTitle: ""
    property bool deleteCandidateArchived: false
    readonly property bool hasArchivedThreads: {
        const items = Array.isArray(controller.threads) ? controller.threads : [];
        for (let index = 0; index < items.length; ++index) {
            if (items[index].archived) {
                return true;
            }
        }
        return false;
    }

    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: Kirigami.Units.gridUnit * 25

    function requestDelete(thread) {
        deleteCandidateId = String(thread.id || "");
        deleteCandidateTitle = thread.title
            ? String(thread.title)
            : i18n("Untitled chat");
        deleteCandidateArchived = Boolean(thread.archived);
        deleteDialog.open();
    }

    function requestDeleteAllArchived() {
        bulkDeleteDialog.open();
    }

    QQC2.Dialog {
        id: deleteDialog

        anchors.centerIn: parent
        modal: true
        focus: true
        title: view.deleteCandidateArchived
            ? i18n("Delete archived chat?")
            : i18n("Delete active chat?")
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok

        onOpened: {
            const deleteButton = standardButton(QQC2.Dialog.Ok);
            if (deleteButton) {
                deleteButton.text = i18n("Delete permanently");
            }
        }
        onAccepted: {
            const threadId = view.deleteCandidateId;
            view.deleteCandidateId = "";
            view.deleteCandidateTitle = "";
            view.deleteCandidateArchived = false;
            if (threadId !== "") {
                view.controller.deleteThread(threadId);
            }
        }
        onRejected: {
            view.deleteCandidateId = "";
            view.deleteCandidateTitle = "";
            view.deleteCandidateArchived = false;
        }

        contentItem: QQC2.Label {
            text: view.deleteCandidateArchived
                ? i18n("The archived chat “%1” will be permanently deleted. Any chats created from it may also be deleted. This cannot be undone.",
                    view.deleteCandidateTitle)
                : i18n("The active chat “%1” will be permanently deleted. Any chats created from it may also be deleted. This cannot be undone.",
                    view.deleteCandidateTitle)
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            width: Kirigami.Units.gridUnit * 18
        }
    }

    QQC2.Dialog {
        id: bulkDeleteDialog

        anchors.centerIn: parent
        modal: true
        focus: true
        title: i18n("Delete all archived chats?")
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok

        onOpened: {
            const continueButton = standardButton(QQC2.Dialog.Ok);
            if (continueButton) {
                continueButton.text = i18n("Continue");
            }
        }
        onAccepted: bulkDeleteFinalDialog.open()

        contentItem: QQC2.Label {
            width: Kirigami.Units.gridUnit * 20
            text: i18n("Every archived chat will be permanently deleted. Descendant chats may also be deleted. If Codex fails during the operation, some deletions may already have completed.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    QQC2.Dialog {
        id: bulkDeleteFinalDialog

        anchors.centerIn: parent
        modal: true
        focus: true
        title: i18n("Final confirmation")
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok

        onOpened: {
            const deleteButton = standardButton(QQC2.Dialog.Ok);
            if (deleteButton) {
                deleteButton.text = i18n("Delete all archived");
            }
        }
        onAccepted: view.controller.deleteAllArchivedThreads()

        contentItem: QQC2.Label {
            width: Kirigami.Units.gridUnit * 20
            text: i18n("This is the final confirmation. Permanently delete all archived chats now?")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: i18n("Search chat titles")
                maximumLength: 120
                enabled: !view.controller.threadsBusy
                onAccepted: view.controller.searchThreads(text)
            }

            QQC2.ToolButton {
                icon.name: "edit-find"
                text: i18n("Search")
                display: QQC2.AbstractButton.IconOnly
                enabled: !view.controller.threadsBusy
                onClicked: view.controller.searchThreads(searchField.text)

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
            }

            QQC2.ToolButton {
                icon.name: "view-refresh"
                text: i18n("Refresh chats")
                display: QQC2.AbstractButton.IconOnly
                enabled: !view.controller.threadsBusy
                onClicked: view.controller.refreshThreads()

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
            }

            QQC2.ToolButton {
                visible: view.hasArchivedThreads
                icon.name: "edit-delete"
                text: i18n("Delete all archived chats")
                display: QQC2.AbstractButton.IconOnly
                enabled: !view.controller.threadsBusy
                onClicked: view.requestDeleteAllArchived()

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
            }

            QQC2.BusyIndicator {
                visible: view.controller.threadsBusy
                running: visible
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Layout.preferredWidth
            }
        }

        Kirigami.InlineMessage {
            visible: view.controller.threadsErrorCode !== ""
            text: view.controller.threadErrorMessage(
                view.controller.threadsErrorCode)
            type: Kirigami.MessageType.Error
            Layout.fillWidth: true
        }

        Kirigami.InlineMessage {
            visible: view.controller.threadsNotice !== ""
            text: view.controller.threadsNotice
            type: Kirigami.MessageType.Positive
            Layout.fillWidth: true
        }

        QQC2.Label {
            visible: view.controller.threadsLoaded
                && view.controller.threads.length === 0
                && !view.controller.threadsBusy
            text: searchField.text.trim() === ""
                ? i18n("No saved chats were found.")
                : i18n("No chats match this search.")
            color: Kirigami.Theme.disabledTextColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }

        ListView {
            id: chatList
            visible: view.controller.threads.length > 0
            clip: true
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: view.controller.threads
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: false

            delegate: Item {
                id: chatDelegate

                required property int index
                required property var modelData
                property bool editing: false
                readonly property bool startsSection: index === 0
                    || Boolean(chatList.model[index - 1].archived)
                        !== Boolean(modelData.archived)

                width: ListView.view ? ListView.view.width : 0
                height: chatRow.implicitHeight

                ColumnLayout {
                    id: chatRow

                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        visible: chatDelegate.startsSection
                        text: chatDelegate.modelData.archived
                            ? i18n("Archived chats")
                            : i18n("Active chats")
                        color: Kirigami.Theme.highlightColor
                        font.weight: Font.Bold
                        Layout.fillWidth: true
                        Layout.topMargin: chatDelegate.index === 0
                            ? 0
                            : Kirigami.Units.largeSpacing
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            QQC2.Label {
                                text: chatDelegate.modelData.title
                                    ? chatDelegate.modelData.title
                                    : i18n("Untitled chat")
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            QQC2.Label {
                                text: i18n("%1 · %2",
                                    view.controller.threadUpdatedLabel(
                                        chatDelegate.modelData.updatedAt),
                                    view.controller.threadStatusLabel(
                                        chatDelegate.modelData.status,
                                        chatDelegate.modelData.archived))
                                color: Kirigami.Theme.disabledTextColor
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        QQC2.ToolButton {
                            icon.name: "document-edit"
                            text: i18n("Rename")
                            display: QQC2.AbstractButton.IconOnly
                            enabled: !view.controller.threadsBusy
                            onClicked: {
                                chatDelegate.editing = true;
                                renameField.text = chatDelegate.modelData.title || "";
                                renameField.forceActiveFocus();
                                renameField.selectAll();
                            }

                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: text
                        }

                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            text: chatDelegate.modelData.archived
                                ? i18n("Delete archived chat")
                                : i18n("Delete active chat")
                            display: QQC2.AbstractButton.IconOnly
                            enabled: !view.controller.threadsBusy
                            onClicked: view.requestDelete(
                                chatDelegate.modelData)

                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: text
                        }

                        QQC2.ToolButton {
                            icon.name: "utilities-terminal"
                            text: chatDelegate.modelData.archived
                                ? i18n("Restore and open in terminal")
                                : i18n("Open in terminal")
                            display: QQC2.AbstractButton.IconOnly
                            enabled: !view.controller.threadsBusy
                            onClicked: view.controller.resumeThread(
                                chatDelegate.modelData.id,
                                Boolean(chatDelegate.modelData.archived))

                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: text
                        }
                    }

                    RowLayout {
                        visible: chatDelegate.editing
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.TextField {
                            id: renameField
                            Layout.fillWidth: true
                            maximumLength: 120
                            placeholderText: i18n("Chat name")
                            enabled: !view.controller.threadsBusy
                            onAccepted: saveButton.clicked()
                        }

                        QQC2.Button {
                            id: saveButton
                            text: i18n("Save")
                            enabled: !view.controller.threadsBusy
                                && renameField.text.trim() !== ""
                            onClicked: {
                                view.controller.renameThread(
                                    chatDelegate.modelData.id, renameField.text);
                                chatDelegate.editing = false;
                            }
                        }

                        QQC2.Button {
                            text: i18n("Cancel")
                            enabled: !view.controller.threadsBusy
                            onClicked: chatDelegate.editing = false
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                    }
                }
            }

            footer: Item {
                width: chatList.width
                height: loadMoreButton.visible
                    ? loadMoreButton.implicitHeight + Kirigami.Units.largeSpacing * 2
                    : 0

                QQC2.Button {
                    id: loadMoreButton
                    visible: view.controller.threadsNextCursor !== ""
                    text: i18n("Load more")
                    enabled: !view.controller.threadsBusy
                    anchors.centerIn: parent
                    onClicked: view.controller.loadMoreThreads()
                }
            }
        }

        QQC2.Label {
            text: i18np("%1 chat loaded", "%1 chats loaded",
                view.controller.threads.length)
            color: Kirigami.Theme.disabledTextColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
        }
    }
}
