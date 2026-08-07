/*
 * SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
 * SPDX-License-Identifier: MIT
 */

import QtQuick

import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "configGeneral.qml"
    }
}
