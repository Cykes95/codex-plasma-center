/*
 * SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as QtDialogs
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: view

    required property var controller
    spacing: Kirigami.Units.smallSpacing

    property url selectedWorkingDirectory: ""

    readonly property string workingDirectoryLabel:
        selectedWorkingDirectory.toString() === ""
        ? i18n("Home folder (default)")
        : decodeURIComponent(selectedWorkingDirectory.toString()
            .replace(/^file:\/\//, ""))

    readonly property var modelChoices: [{
        "label": i18n("Use Codex default"),
        "value": "",
        "efforts": []
    }].concat((controller.launcherModels || []).map(function(model) {
        return {
            "label": model.isDefault
                ? i18n("%1 (default)", model.displayName)
                : model.displayName,
            "value": model.id,
            "efforts": model.supportedReasoningEfforts || []
        };
    }))
    readonly property var selectedModel: modelCombo.currentIndex >= 0
        && modelCombo.currentIndex < modelChoices.length
        ? modelChoices[modelCombo.currentIndex]
        : modelChoices[0]
    readonly property var effortChoices: [{
        "label": i18n("Use configured/model default"),
        "value": ""
    }].concat((selectedModel.efforts || []).map(function(effort) {
        return {"label": controller.titleCase(effort), "value": effort};
    }))
    readonly property var sandboxChoices: [
        {"label": i18n("Inherit Codex configuration"), "value": ""},
        {"label": i18n("Read only"), "value": "read-only"},
        {"label": i18n("Workspace write"), "value": "workspace-write"},
        {"label": i18n("Full access"), "value": "danger-full-access"},
        {
            "label": i18n("Bypass all protections"),
            "value": "dangerously-bypass-approvals-and-sandbox"
        }
    ]
    readonly property var approvalChoices: [
        {"label": i18n("Inherit Codex configuration"), "value": ""},
        {"label": i18n("Untrusted commands"), "value": "untrusted"},
        {"label": i18n("When requested"), "value": "on-request"},
        {"label": i18n("Never ask"), "value": "never"}
    ]
    readonly property var terminalChoices: [{
        "label": i18n("Automatically detect"),
        "value": ""
    }].concat((controller.launcherTerminals || []).map(function(terminal) {
        return {
            "label": terminal.displayName,
            "value": terminal.id
        };
    }))

    function terminalIndex(terminalId) {
        for (let index = 0; index < terminalChoices.length; ++index) {
            if (terminalChoices[index].value === terminalId) {
                return index;
            }
        }
        return 0;
    }

    function syncTerminalSelection() {
        terminalCombo.currentIndex = terminalIndex(
            String(controller.preferredTerminal || ""));
    }

    function launchSelected() {
        view.controller.launchCodex(
            String(modelCombo.currentValue || ""),
            String(effortCombo.currentValue || ""),
            String(sandboxCombo.currentValue || ""),
            String(approvalCombo.currentValue || ""),
            selectedWorkingDirectory.toString(),
            String(terminalCombo.currentValue || ""));
    }

    Component.onCompleted: syncTerminalSelection()

    Connections {
        target: view.controller

        function onLauncherTerminalsChanged() {
            Qt.callLater(view.syncTerminalSelection);
        }
    }

    QtDialogs.FolderDialog {
        id: workingDirectoryDialog

        title: i18n("Choose working folder")
        onAccepted: view.selectedWorkingDirectory = selectedFolder
    }

    QQC2.Dialog {
        id: bypassConfirmDialog

        anchors.centerIn: parent
        modal: true
        focus: true
        title: i18n("Bypass every protection?")
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok

        onOpened: {
            const continueButton = standardButton(QQC2.Dialog.Ok);
            if (continueButton) {
                continueButton.text = i18n("Continue");
            }
        }
        onAccepted: bypassFinalDialog.open()

        contentItem: QQC2.Label {
            width: Kirigami.Units.gridUnit * 20
            text: i18n("The new CLI will run without a sandbox and will never ask for command approval. It can modify any data available to your user account.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    QQC2.Dialog {
        id: bypassFinalDialog

        anchors.centerIn: parent
        modal: true
        focus: true
        title: i18n("Final confirmation")
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok

        onOpened: {
            const launchButton = standardButton(QQC2.Dialog.Ok);
            if (launchButton) {
                launchButton.text = i18n("Open without protections");
            }
        }
        onAccepted: view.launchSelected()

        contentItem: QQC2.Label {
            width: Kirigami.Units.gridUnit * 20
            text: i18n("Open this Codex CLI with all sandboxing and approval prompts disabled?")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    RowLayout {
        Layout.fillWidth: true

        QQC2.Label {
            text: i18n("New Codex chat")
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }

        QQC2.BusyIndicator {
            visible: view.controller.launcherBusy
            running: visible
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Layout.preferredWidth
        }

        QQC2.ToolButton {
            icon.name: "view-refresh"
            text: i18n("Reload launch options")
            display: QQC2.AbstractButton.IconOnly
            enabled: !view.controller.launcherBusy
            onClicked: view.controller.loadLauncherOptions()

            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: text
        }
    }

    Kirigami.InlineMessage {
        visible: view.controller.launcherErrorCode !== ""
        text: view.controller.launcherErrorMessage(
            view.controller.launcherErrorCode)
        type: Kirigami.MessageType.Error
        Layout.fillWidth: true
    }

    Kirigami.InlineMessage {
        visible: view.controller.launcherNotice !== ""
        text: view.controller.launcherNotice
        type: Kirigami.MessageType.Positive
        Layout.fillWidth: true
    }

    QQC2.ScrollView {
        id: controlsScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            id: controlsContent
            width: controlsScroll.availableWidth
            spacing: Kirigami.Units.smallSpacing

            GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing
                Layout.fillWidth: true

        QQC2.Label {
            text: i18n("Model")
        }

        QQC2.ComboBox {
            id: modelCombo
            model: view.modelChoices
            textRole: "label"
            valueRole: "value"
            enabled: view.controller.launcherLoaded
                && !view.controller.launcherBusy
            Layout.fillWidth: true
            onCurrentIndexChanged: effortCombo.currentIndex = 0
        }

        QQC2.Label {
            text: i18n("Reasoning")
        }

        QQC2.ComboBox {
            id: effortCombo
            model: view.effortChoices
            textRole: "label"
            valueRole: "value"
            enabled: modelCombo.currentValue !== ""
                && !view.controller.launcherBusy
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: i18n("Access")
        }

        QQC2.ComboBox {
            id: sandboxCombo
            model: view.sandboxChoices
            textRole: "label"
            valueRole: "value"
            enabled: view.controller.launcherLoaded
                && !view.controller.launcherBusy
            Layout.fillWidth: true
            onActivated: {
                if (currentValue
                        === "dangerously-bypass-approvals-and-sandbox") {
                    approvalCombo.currentIndex = 0;
                }
            }
        }

        QQC2.Label {
            text: i18n("Approvals")
        }

        QQC2.ComboBox {
            id: approvalCombo
            model: view.approvalChoices
            textRole: "label"
            valueRole: "value"
            enabled: view.controller.launcherLoaded
                && !view.controller.launcherBusy
                && sandboxCombo.currentValue
                    !== "dangerously-bypass-approvals-and-sandbox"
            Layout.fillWidth: true
        }

        QQC2.Label {
            text: i18n("Working folder")
        }

        RowLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                text: view.workingDirectoryLabel
                readOnly: true
                selectByMouse: true
                Layout.fillWidth: true

                QQC2.ToolTip.visible: hovered
                    && view.selectedWorkingDirectory.toString() !== ""
                QQC2.ToolTip.text: text
            }

            QQC2.Button {
                text: i18n("Choose…")
                icon.name: "document-open-folder"
                enabled: !view.controller.launcherBusy
                onClicked: workingDirectoryDialog.open()
            }

            QQC2.ToolButton {
                icon.name: "edit-clear"
                text: i18n("Use home folder")
                display: QQC2.AbstractButton.IconOnly
                visible: view.selectedWorkingDirectory.toString() !== ""
                enabled: !view.controller.launcherBusy
                onClicked: view.selectedWorkingDirectory = ""

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: text
            }
        }

        QQC2.Label {
            text: i18n("Terminal")
        }

        QQC2.ComboBox {
            id: terminalCombo
            model: view.terminalChoices
            textRole: "label"
            valueRole: "value"
            enabled: view.controller.launcherLoaded
                && !view.controller.launcherBusy
            Layout.fillWidth: true
            onActivated: view.controller.setPreferredTerminal(
                String(currentValue || ""))
        }
            }

            QQC2.Label {
                text: i18n("These are official Codex CLI options and do not depend on your shell. Inherit leaves that setting unchanged. If no working folder is selected, the new CLI opens in your home folder.")
                color: Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }

    Kirigami.InlineMessage {
        visible: sandboxCombo.currentValue === "danger-full-access"
            || sandboxCombo.currentValue
                === "dangerously-bypass-approvals-and-sandbox"
            || approvalCombo.currentValue === "never"
        text: sandboxCombo.currentValue
            === "dangerously-bypass-approvals-and-sandbox"
            ? i18n("This mode disables both sandboxing and approval prompts. Opening it requires two confirmations.")
            : i18n("This selection reduces protections for the new CLI session. Use it only when you understand the impact.")
        type: Kirigami.MessageType.Warning
        Layout.fillWidth: true
    }

    QQC2.Button {
        text: i18n("Open new chat in terminal")
        icon.name: "utilities-terminal"
        enabled: view.controller.launcherLoaded
            && !view.controller.launcherBusy
        Layout.alignment: Qt.AlignRight
        onClicked: {
            if (sandboxCombo.currentValue
                    === "dangerously-bypass-approvals-and-sandbox") {
                bypassConfirmDialog.open();
            } else {
                view.launchSelected();
            }
        }
    }
}
