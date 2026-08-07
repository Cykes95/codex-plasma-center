/*
 * SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
 * SPDX-License-Identifier: MIT
 *
 * Synthetic English screenshot fixture. It never contacts Codex or reads
 * account, conversation, path, or usage data.
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window

import org.kde.kirigami as Kirigami

Window {
    id: window

    width: 620
    height: 560
    visible: true
    color: "transparent"

    Rectangle {
        id: frame

        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        radius: 12
        border.color: Kirigami.Theme.separatorColor
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 2
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true

                Image {
                    source: Qt.resolvedUrl(
                        "../package/contents/icons/codex-blossom-black.svg")
                    sourceSize.width: 42
                    sourceSize.height: 42
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true

                    QQC2.Label {
                        text: "Codex Plasma Center"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    QQC2.Label {
                        text: "Start and manage Codex sessions"
                        color: "#5f6368"
                    }
                }

                QQC2.Label {
                    text: "Addon 0.7.0"
                    color: "#5f6368"
                }
            }

            QQC2.TabBar {
                Layout.fillWidth: true

                QQC2.TabButton { text: "Status" }
                QQC2.TabButton { text: "New chat"; checked: true }
                QQC2.TabButton { text: "History" }
            }

            RowLayout {
                Layout.fillWidth: true

                QQC2.Label {
                    text: "New Codex chat"
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                }
            }

            GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.largeSpacing
                Layout.fillWidth: true

                QQC2.Label { text: "Model" }
                QQC2.ComboBox {
                    model: ["Use Codex default", "Example coding model"]
                    Layout.fillWidth: true
                }

                QQC2.Label { text: "Reasoning" }
                QQC2.ComboBox {
                    model: ["Use configured/model default"]
                    Layout.fillWidth: true
                }

                QQC2.Label { text: "Access" }
                QQC2.ComboBox {
                    model: ["Inherit Codex configuration"]
                    Layout.fillWidth: true
                }

                QQC2.Label { text: "Approvals" }
                QQC2.ComboBox {
                    model: ["Inherit Codex configuration"]
                    Layout.fillWidth: true
                }

                QQC2.Label { text: "Working folder" }
                RowLayout {
                    Layout.fillWidth: true

                    QQC2.TextField {
                        text: "Home folder (default)"
                        readOnly: true
                        Layout.fillWidth: true
                    }

                    QQC2.Button {
                        text: "Choose…"
                        icon.name: "document-open-folder"
                    }
                }

                QQC2.Label { text: "Terminal" }
                QQC2.ComboBox {
                    model: ["Automatically detect", "Example terminal"]
                    Layout.fillWidth: true
                }
            }

            QQC2.Label {
                text: "Official Codex CLI options are passed without depending on shell aliases. If no working folder is selected, the new CLI opens in the home folder."
                color: "#5f6368"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true }

            QQC2.Button {
                text: "Open new chat in terminal"
                icon.name: "utilities-terminal"
                Layout.alignment: Qt.AlignRight
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: frame.grabToImage(function(result) {
            if (!result.saveToFile("docs/screenshot-en.png")) {
                console.error("Could not save screenshot")
                Qt.exit(1)
                return
            }
            console.log("Saved docs/screenshot-en.png")
            Qt.quit()
        })
    }
}
