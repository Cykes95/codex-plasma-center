/*
 * SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Item {
    id: root

    property string title: ""
    property alias cfg_refreshIntervalMinutes: refreshInterval.value
    property int cfg_refreshIntervalMinutesDefault: 5
    property alias cfg_showPercentage: percentageCheckBox.checked
    property bool cfg_showPercentageDefault: true

    implicitWidth: form.implicitWidth
    implicitHeight: form.implicitHeight

    Kirigami.FormLayout {
        id: form
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        QQC2.SpinBox {
            id: refreshInterval
            Kirigami.FormData.label: i18n("Refresh interval:")
            from: 1
            to: 60
            editable: true
            textFromValue: function (value) {
                return i18np("%1 minute", "%1 minutes", value);
            }
            valueFromText: function (text) {
                const parsed = parseInt(text, 10);
                return isNaN(parsed) ? root.cfg_refreshIntervalMinutesDefault : parsed;
            }
        }

        QQC2.CheckBox {
            id: percentageCheckBox
            Kirigami.FormData.label: i18n("Panel:")
            text: i18n("Show remaining percentage")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("The widget does not store account usage or display the account email.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
        }
    }
}
