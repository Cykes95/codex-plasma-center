/*
 * SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // Keep the compact, status-specific tooltip below; suppress Plasma's
    // generic metadata tooltip, which otherwise appears as a second popup.
    toolTipMainText: ""
    toolTipSubText: ""

    readonly property string helperUrl: Qt.resolvedUrl("../tools/codex_status.py").toString()
    readonly property string helperPath: decodeURIComponent(helperUrl.replace(/^file:\/\//, ""))
    readonly property string threadsHelperUrl: Qt.resolvedUrl("../tools/codex_threads.py").toString()
    readonly property string threadsHelperPath: decodeURIComponent(
        threadsHelperUrl.replace(/^file:\/\//, ""))
    readonly property string accountActionsHelperUrl: Qt.resolvedUrl(
        "../tools/codex_account_actions.py").toString()
    readonly property string accountActionsHelperPath: decodeURIComponent(
        accountActionsHelperUrl.replace(/^file:\/\//, ""))
    readonly property string launcherHelperUrl: Qt.resolvedUrl(
        "../tools/codex_launcher.py").toString()
    readonly property string launcherHelperPath: decodeURIComponent(
        launcherHelperUrl.replace(/^file:\/\//, ""))
    readonly property real textLuminance: 0.2126 * Kirigami.Theme.textColor.r
        + 0.7152 * Kirigami.Theme.textColor.g
        + 0.0722 * Kirigami.Theme.textColor.b
    readonly property url codexIcon: Qt.resolvedUrl(textLuminance >= 0.5
        ? "../icons/codex-blossom-white.svg"
        : "../icons/codex-blossom-black.svg")
    readonly property string statusCommand: "python3 " + shellQuote(helperPath)
    readonly property string addonVersion: "0.7.1"
    readonly property int refreshIntervalMinutes: Math.max(1, Math.min(60,
        Number(Plasmoid.configuration.refreshIntervalMinutes || 5)))
    readonly property bool showPercentage: Plasmoid.configuration.showPercentage !== false
    readonly property bool verticalPanel: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    property bool busy: false
    property string errorCode: ""
    property string codexVersion: ""
    property double generatedAt: 0
    property var account: ({
        "authenticated": false,
        "authType": null,
        "plan": null
    })
    property var limitRows: []
    property var usageSummary: ({})
    property bool usageAvailable: false
    property int resetCreditsAvailable: -1
    property bool threadsBusy: false
    property bool threadsLoaded: false
    property string threadsErrorCode: ""
    property string threadsNotice: ""
    property var threads: []
    property string threadsNextCursor: ""
    property string threadsSearchTerm: ""
    property string pendingThreadAction: ""
    property bool pendingThreadAppend: false
    property bool accountActionBusy: false
    property string accountActionErrorCode: ""
    property string accountActionNotice: ""
    property string pendingAccountAction: ""
    property string pendingResetKey: ""
    property bool launcherBusy: false
    property bool launcherLoaded: false
    property string launcherErrorCode: ""
    property string launcherNotice: ""
    property string pendingLauncherAction: ""
    property var launcherModels: []
    property var launcherTerminals: []

    readonly property string preferredTerminal: String(
        Plasmoid.configuration.preferredTerminal || "")

    readonly property var primaryRow: limitRows.length > 0 ? limitRows[0] : null
    readonly property real primaryRemaining: primaryRow
        && primaryRow.window.remainingPercent !== null
        ? Number(primaryRow.window.remainingPercent)
        : -1
    readonly property string panelPercentage: primaryRemaining >= 0
        ? i18n("%1%", Math.round(primaryRemaining))
        : ""
    readonly property color statusColor: {
        if (errorCode !== "") {
            return Kirigami.Theme.negativeTextColor;
        }
        if (busy) {
            return Kirigami.Theme.neutralTextColor;
        }
        if (!account.authenticated) {
            return Kirigami.Theme.disabledTextColor;
        }
        if (primaryRemaining >= 0 && primaryRemaining <= 10) {
            return Kirigami.Theme.negativeTextColor;
        }
        if (primaryRemaining >= 0 && primaryRemaining <= 25) {
            return Kirigami.Theme.neutralTextColor;
        }
        return Kirigami.Theme.positiveTextColor;
    }
    readonly property string accountLabel: {
        if (!account.authenticated) {
            return i18n("Sign-in required");
        }
        if (account.plan) {
            return i18n("%1 plan", titleCase(String(account.plan)));
        }
        return i18n("Authenticated");
    }
    readonly property string lastUpdatedLabel: generatedAt > 0
        ? i18n("Updated %1", Qt.formatDateTime(new Date(generatedAt * 1000), Locale.ShortFormat))
        : i18n("Not updated yet")

    Plasmoid.icon: codexIcon
    Plasmoid.status: errorCode !== ""
        ? PlasmaCore.Types.NeedsAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'";
    }

    function titleCase(value) {
        if (value.length === 0) {
            return value;
        }
        return value.charAt(0).toUpperCase() + value.slice(1);
    }

    function resetLabel(epochSeconds) {
        const value = Number(epochSeconds || 0);
        if (value <= 0) {
            return i18n("Reset time unavailable");
        }
        return i18n("Resets at %1",
            Qt.formatDateTime(new Date(value * 1000), Locale.ShortFormat));
    }

    function windowLabel(window, rowIndex) {
        const minutes = Number(window.windowDurationMins || 0);
        if (minutes > 0 && minutes <= 360) {
            return i18n("Session");
        }
        if (minutes >= 6 * 24 * 60 && minutes <= 8 * 24 * 60) {
            return i18n("Weekly");
        }
        if (minutes >= 27 * 24 * 60 && minutes <= 32 * 24 * 60) {
            return i18n("Monthly");
        }
        if (minutes > 0 && minutes % 1440 === 0) {
            return i18np("%1-day window", "%1-day window", minutes / 1440);
        }
        if (minutes > 0 && minutes % 60 === 0) {
            return i18np("%1-hour window", "%1-hour window", minutes / 60);
        }
        return i18n("Usage window %1", rowIndex + 1);
    }

    function flattenLimits(items) {
        const rows = [];
        const snapshots = Array.isArray(items) ? items : [];
        for (let index = 0; index < snapshots.length; ++index) {
            const snapshot = snapshots[index] || {};
            if (snapshot.primary) {
                const primaryLabel = windowLabel(snapshot.primary, rows.length);
                rows.push({
                    "label": snapshots.length > 1
                        ? i18n("%1 · limit %2", primaryLabel, index + 1)
                        : primaryLabel,
                    "window": snapshot.primary
                });
            }
            if (snapshot.secondary) {
                const secondaryLabel = windowLabel(snapshot.secondary, rows.length);
                rows.push({
                    "label": snapshots.length > 1
                        ? i18n("%1 · limit %2", secondaryLabel, index + 1)
                        : secondaryLabel,
                    "window": snapshot.secondary
                });
            }
        }
        return rows;
    }

    function errorMessage(code) {
        switch (code) {
        case "codex_not_found":
            return i18n("Codex CLI was not found in the Plasma environment.");
        case "app_server_start_failed":
        case "app_server_stopped":
            return i18n("Codex app-server could not be started.");
        case "incompatible_app_server":
        case "invalid_protocol_response":
            return i18n("This Codex version is not compatible with the widget.");
        case "app_server_timeout":
            return i18n("Codex did not answer before the request timed out.");
        case "account_unavailable":
            return i18n("Codex account status is currently unavailable.");
        default:
            return i18n("Codex status could not be read.");
        }
    }

    function threadErrorMessage(code) {
        switch (code) {
        case "codex_not_found":
            return i18n("Codex CLI was not found in the Plasma environment.");
        case "app_server_start_failed":
        case "app_server_stopped":
            return i18n("Codex app-server could not be started.");
        case "incompatible_app_server":
        case "invalid_protocol_response":
            return i18n("This Codex version is not compatible with the widget.");
        case "app_server_timeout":
            return i18n("Codex did not answer before the request timed out.");
        case "threads_unavailable":
            return i18n("Codex chats are currently unavailable.");
        case "invalid_title":
            return i18n("Enter a non-empty name of up to 120 characters.");
        case "invalid_thread_id":
        case "invalid_input":
            return i18n("The selected chat could not be validated.");
        case "rename_failed":
            return i18n("The chat could not be renamed.");
        case "delete_failed":
            return i18n("The chat could not be deleted.");
        case "bulk_delete_failed":
            return i18n("The archived chats could not be collected safely. Nothing was deleted.");
        case "bulk_delete_too_large":
            return i18n("More than 1,000 archived chats were found. Nothing was deleted.");
        case "bulk_delete_partial":
            return i18n("Codex stopped during bulk deletion. Some archived chats may already have been deleted; refresh the list before trying again.");
        case "terminal_not_found":
            return i18n("No supported terminal emulator was found.");
        case "invalid_terminal":
            return i18n("The selected terminal is not supported.");
        case "resume_failed":
            return i18n("The chat could not be opened in a terminal.");
        default:
            return i18n("The chat operation could not be completed.");
        }
    }

    function accountActionErrorMessage(code) {
        switch (code) {
        case "codex_not_found":
            return i18n("Codex CLI was not found in the Plasma environment.");
        case "reset_unavailable":
            return i18n("Limit reset is not available with this Codex version or account.");
        case "app_server_start_failed":
        case "app_server_stopped":
            return i18n("Codex app-server could not be started.");
        case "app_server_timeout":
            return i18n("Codex did not answer before the request timed out. Retry keeps the same reset attempt while this widget remains open.");
        case "invalid_input":
        case "invalid_protocol_response":
            return i18n("The reset request could not be validated safely.");
        default:
            return i18n("The limit reset could not be completed.");
        }
    }

    function launcherErrorMessage(code) {
        switch (code) {
        case "codex_not_found":
            return i18n("Codex CLI was not found in the Plasma environment.");
        case "terminal_not_found":
            return i18n("No supported terminal emulator was found.");
        case "invalid_terminal":
            return i18n("The selected terminal is not supported.");
        case "models_unavailable":
            return i18n("Codex models are currently unavailable.");
        case "launch_failed":
            return i18n("A new Codex CLI could not be opened in a terminal.");
        case "app_server_start_failed":
        case "app_server_stopped":
            return i18n("Codex app-server could not be started.");
        case "app_server_timeout":
            return i18n("Codex did not answer before the request timed out.");
        case "invalid_working_directory":
            return i18n("The selected working folder is no longer available.");
        case "invalid_input":
        case "invalid_protocol_response":
            return i18n("The selected launch options could not be validated.");
        default:
            return i18n("Codex launch options could not be loaded.");
        }
    }

    function threadStatusLabel(status, archived) {
        if (archived) {
            return i18n("Archived");
        }
        switch (status) {
        case "active":
            return i18n("Active");
        case "idle":
            return i18n("Idle");
        case "systemError":
            return i18n("Error");
        case "notLoaded":
            return i18n("Saved");
        default:
            return i18n("Unknown");
        }
    }

    function threadUpdatedLabel(epochSeconds) {
        const value = Number(epochSeconds || 0);
        return value > 0
            ? i18n("Updated %1", Qt.formatDateTime(
                new Date(value * 1000), Locale.ShortFormat))
            : i18n("Update time unavailable");
    }

    function encodedThreadArgument(value) {
        return encodeURIComponent(String(value || ""));
    }

    function threadCommand(action, actionArguments) {
        let command = "python3 " + shellQuote(threadsHelperPath)
            + " " + shellQuote(action);
        for (let index = 0; index < actionArguments.length; ++index) {
            command += " " + shellQuote(
                encodedThreadArgument(actionArguments[index]));
        }
        return command;
    }

    function helperActionCommand(helper, action, actionArguments) {
        let command = "python3 " + shellQuote(helper)
            + " " + shellQuote(action);
        for (let index = 0; index < actionArguments.length; ++index) {
            command += " " + shellQuote(
                encodedThreadArgument(actionArguments[index]));
        }
        return command;
    }

    function runThreadAction(action, actionArguments, context) {
        if (threadsBusy || threadsHelperPath === "") {
            return;
        }
        threadsBusy = true;
        threadsErrorCode = "";
        threadsNotice = "";
        pendingThreadAction = action;
        pendingThreadAppend = Boolean(context && context.append);
        const command = threadCommand(action, actionArguments);
        threadsSource.disconnectSource(command);
        threadsSource.connectSource(command);
    }

    function searchThreads(searchTerm) {
        threadsSearchTerm = String(searchTerm || "").trim().slice(0, 120);
        runThreadAction("list", ["", threadsSearchTerm], {
            "action": "list",
            "append": false
        });
    }

    function refreshThreads() {
        runThreadAction("list", ["", threadsSearchTerm], {
            "action": "list",
            "append": false
        });
    }

    function loadMoreThreads() {
        if (threadsNextCursor === "") {
            return;
        }
        runThreadAction("list", [threadsNextCursor, threadsSearchTerm], {
            "action": "list",
            "append": true
        });
    }

    function renameThread(threadId, title) {
        runThreadAction("rename", [threadId, title], {
            "action": "rename"
        });
    }

    function resumeThread(threadId, archived) {
        runThreadAction("resume", [threadId, archived ? "1" : "0",
            preferredTerminal], {
            "action": "resume"
        });
    }

    function setPreferredTerminal(terminalId) {
        Plasmoid.configuration.preferredTerminal = String(terminalId || "");
    }

    function deleteThread(threadId) {
        runThreadAction("delete", [threadId], {
            "action": "delete"
        });
    }

    function deleteAllArchivedThreads() {
        runThreadAction("delete_archived_all", [], {
            "action": "delete_archived_all"
        });
    }

    function generateResetKey() {
        let seed = Date.now();
        return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g,
            function(character) {
                const random = (seed + Math.random() * 16) % 16 | 0;
                seed = Math.floor(seed / 16);
                return (character === "x" ? random : (random & 0x3) | 0x8)
                    .toString(16);
            });
    }

    function requestResetCredit() {
        if (resetCreditsAvailable <= 0 || accountActionBusy) {
            return;
        }
        if (pendingResetKey === "") {
            pendingResetKey = generateResetKey();
        }
        resetConfirmDialog.open();
    }

    function consumeResetCredit() {
        if (accountActionBusy || pendingResetKey === ""
                || accountActionsHelperPath === "") {
            return;
        }
        accountActionBusy = true;
        accountActionErrorCode = "";
        accountActionNotice = "";
        pendingAccountAction = "consume_reset";
        const command = helperActionCommand(accountActionsHelperPath,
            "consume_reset", [pendingResetKey]);
        accountActionSource.disconnectSource(command);
        accountActionSource.connectSource(command);
    }

    function loadLauncherOptions() {
        if (launcherBusy || launcherHelperPath === "") {
            return;
        }
        launcherBusy = true;
        launcherErrorCode = "";
        launcherNotice = "";
        pendingLauncherAction = "options";
        const command = helperActionCommand(launcherHelperPath, "options", []);
        launcherSource.disconnectSource(command);
        launcherSource.connectSource(command);
    }

    function ensureLauncherOptionsLoaded() {
        if (!launcherLoaded && !launcherBusy) {
            loadLauncherOptions();
        }
    }

    function launchCodex(model, effort, sandboxMode, approvalPolicy,
            workingDirectory, terminalId) {
        if (launcherBusy || launcherHelperPath === "") {
            return;
        }
        launcherBusy = true;
        launcherErrorCode = "";
        launcherNotice = "";
        pendingLauncherAction = "launch";
        const command = helperActionCommand(launcherHelperPath, "launch",
            [model, effort, sandboxMode, approvalPolicy, workingDirectory,
                terminalId]);
        launcherSource.disconnectSource(command);
        launcherSource.connectSource(command);
    }

    function sortThreadsForDisplay(items) {
        return items.slice().sort(function(first, second) {
            const archiveDifference = Number(Boolean(first.archived))
                - Number(Boolean(second.archived));
            if (archiveDifference !== 0) {
                return archiveDifference;
            }
            return Number(second.updatedAt || 0) - Number(first.updatedAt || 0);
        });
    }

    function ensureThreadsLoaded() {
        if (!threadsLoaded && !threadsBusy) {
            refreshThreads();
        }
    }

    function parseThreadResult(output, context) {
        try {
            const snapshot = JSON.parse(output);
            if (!snapshot || Number(snapshot.schemaVersion) !== 1
                    || String(snapshot.action || "") !== String(context.action || "")) {
                throw new Error("Unsupported schema");
            }
            if (!snapshot.ok) {
                threadsErrorCode = String(snapshot.error && snapshot.error.code
                    || "unexpected_error");
                return;
            }

            const result = snapshot.result || {};
            if (context.action === "list") {
                const received = Array.isArray(result.items) ? result.items : [];
                threads = sortThreadsForDisplay(
                    context.append ? threads.concat(received) : received);
                threadsNextCursor = result.nextCursor ? String(result.nextCursor) : "";
                threadsLoaded = true;
            } else if (context.action === "rename") {
                const threadId = String(result.threadId || "");
                const title = String(result.title || "");
                threads = threads.map(function(thread) {
                    return thread.id === threadId
                        ? Object.assign({}, thread, {
                            "title": title,
                            "hasCustomName": true
                        })
                        : thread;
                });
                threadsNotice = i18n("Chat renamed.");
            } else if (context.action === "resume") {
                const threadId = String(result.threadId || "");
                if (result.unarchived) {
                    threads = threads.map(function(thread) {
                        return thread.id === threadId
                            ? Object.assign({}, thread, {"archived": false})
                            : thread;
                    });
                    threadsNotice = i18n(
                        "Chat restored and opened in a separate terminal window.");
                } else {
                    threadsNotice = i18n(
                        "Chat opened in a separate terminal window.");
                }
            } else if (context.action === "delete") {
                const threadId = String(result.threadId || "");
                threads = threads.filter(function(thread) {
                    return thread.id !== threadId;
                });
                threadsNotice = i18n("Chat permanently deleted.");
            } else if (context.action === "delete_archived_all") {
                const deletedCount = Math.max(0,
                    Number(result.deletedCount || 0));
                threads = threads.filter(function(thread) {
                    return !thread.archived;
                });
                threadsNextCursor = "";
                threadsNotice = deletedCount > 0
                    ? i18np("%1 archived chat permanently deleted.",
                        "%1 archived chats permanently deleted.", deletedCount)
                    : i18n("No archived chats were found.");
            }
        } catch (error) {
            threadsErrorCode = "invalid_protocol_response";
        }
    }

    function parseSnapshot(output) {
        try {
            const snapshot = JSON.parse(output);
            if (!snapshot || Number(snapshot.schemaVersion) !== 1) {
                throw new Error("Unsupported schema");
            }
            if (!snapshot.ok) {
                errorCode = String(snapshot.error && snapshot.error.code || "unexpected_error");
                return;
            }

            account = snapshot.account || {
                "authenticated": false,
                "authType": null,
                "plan": null
            };
            const rateLimits = snapshot.rateLimits || {};
            limitRows = flattenLimits(rateLimits.items);
            resetCreditsAvailable = rateLimits.resetCreditsAvailable === null
                || rateLimits.resetCreditsAvailable === undefined
                ? -1
                : Number(rateLimits.resetCreditsAvailable);
            const usage = snapshot.usage || {};
            usageAvailable = Boolean(usage.available);
            usageSummary = usage.summary || {};
            codexVersion = String(snapshot.codexVersion || "");
            generatedAt = Number(snapshot.generatedAt || 0);
            errorCode = "";
        } catch (error) {
            errorCode = "invalid_protocol_response";
        }
    }

    function parseAccountActionResult(output, action) {
        try {
            const snapshot = JSON.parse(output);
            if (!snapshot || Number(snapshot.schemaVersion) !== 1
                    || String(snapshot.action || "") !== action) {
                throw new Error("Unsupported schema");
            }
            if (!snapshot.ok) {
                accountActionErrorCode = String(snapshot.error
                    && snapshot.error.code || "unexpected_error");
                return;
            }
            const outcome = String(snapshot.result
                && snapshot.result.outcome || "");
            if (outcome === "reset") {
                accountActionNotice = i18n("Usage limits were reset.");
            } else if (outcome === "nothingToReset") {
                accountActionNotice = i18n("No current usage limit needs a reset.");
            } else if (outcome === "noCredit") {
                accountActionNotice = i18n("No limit reset is currently available.");
            } else if (outcome === "alreadyRedeemed") {
                accountActionNotice = i18n("This reset attempt was already completed.");
            } else {
                throw new Error("Unsupported outcome");
            }
            pendingResetKey = "";
            refresh();
        } catch (error) {
            accountActionErrorCode = "invalid_protocol_response";
        }
    }

    function parseLauncherResult(output, action) {
        try {
            const snapshot = JSON.parse(output);
            if (!snapshot || Number(snapshot.schemaVersion) !== 1
                    || String(snapshot.action || "") !== action) {
                throw new Error("Unsupported schema");
            }
            if (!snapshot.ok) {
                launcherErrorCode = String(snapshot.error
                    && snapshot.error.code || "unexpected_error");
                return;
            }
            const result = snapshot.result || {};
            if (action === "options") {
                launcherModels = Array.isArray(result.models) ? result.models : [];
                launcherTerminals = Array.isArray(result.terminals)
                    ? result.terminals : [];
                launcherLoaded = true;
            } else if (action === "launch" && result.launched === true) {
                launcherNotice = i18n("A new Codex CLI opened in a terminal.");
            } else {
                throw new Error("Unsupported result");
            }
        } catch (error) {
            launcherErrorCode = "invalid_protocol_response";
        }
    }

    function refresh() {
        if (busy || helperPath === "") {
            return;
        }
        busy = true;
        errorCode = "";
        statusSource.disconnectSource(statusCommand);
        statusSource.connectSource(statusCommand);
    }

    function formatInteger(value) {
        const number = Number(value);
        return isNaN(number) ? i18n("Unavailable")
            : number.toLocaleString(Qt.locale(), "f", 0);
    }

    onExpandedChanged: {
        if (root.expanded) {
            refresh();
            ensureLauncherOptionsLoaded();
        }
    }

    Component.onCompleted: {
        refresh();
        ensureThreadsLoaded();
    }

    Timer {
        interval: root.refreshIntervalMinutes * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Plasma5Support.DataSource {
        id: statusSource
        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.busy = false;

            const standardOutput = String(data["stdout"] || "").trim();
            if (standardOutput !== "") {
                root.parseSnapshot(standardOutput);
                return;
            }

            root.errorCode = Number(data["exit code"]) === 127
                ? "codex_not_found"
                : "unexpected_error";
        }
    }

    Plasma5Support.DataSource {
        id: threadsSource
        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.threadsBusy = false;

            const context = {
                "action": root.pendingThreadAction,
                "append": root.pendingThreadAppend
            };
            root.pendingThreadAction = "";
            root.pendingThreadAppend = false;

            const standardOutput = String(data["stdout"] || "").trim();
            if (standardOutput !== "") {
                root.parseThreadResult(standardOutput, context);
                return;
            }

            root.threadsErrorCode = Number(data["exit code"]) === 127
                ? "codex_not_found"
                : "unexpected_error";
        }
    }

    Plasma5Support.DataSource {
        id: accountActionSource
        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.accountActionBusy = false;
            const action = root.pendingAccountAction;
            root.pendingAccountAction = "";
            const standardOutput = String(data["stdout"] || "").trim();
            if (standardOutput !== "") {
                root.parseAccountActionResult(standardOutput, action);
                return;
            }
            root.accountActionErrorCode = Number(data["exit code"]) === 127
                ? "codex_not_found"
                : "unexpected_error";
        }
    }

    Plasma5Support.DataSource {
        id: launcherSource
        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.launcherBusy = false;
            const action = root.pendingLauncherAction;
            root.pendingLauncherAction = "";
            const standardOutput = String(data["stdout"] || "").trim();
            if (standardOutput !== "") {
                root.parseLauncherResult(standardOutput, action);
                return;
            }
            root.launcherErrorCode = Number(data["exit code"]) === 127
                ? "codex_not_found"
                : "unexpected_error";
        }
    }

    QQC2.Dialog {
        id: resetConfirmDialog

        anchors.centerIn: parent
        modal: true
        focus: true
        title: i18n("Use a limit reset?")
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok

        onOpened: {
            const continueButton = standardButton(QQC2.Dialog.Ok);
            if (continueButton) {
                continueButton.text = i18n("Continue");
            }
        }
        onAccepted: resetFinalDialog.open()

        contentItem: QQC2.Label {
            width: Kirigami.Units.gridUnit * 20
            text: i18n("One available reset will be used to reset every eligible Codex usage window.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    QQC2.Dialog {
        id: resetFinalDialog

        anchors.centerIn: parent
        modal: true
        focus: true
        title: i18n("Final confirmation")
        standardButtons: QQC2.Dialog.Cancel | QQC2.Dialog.Ok

        onOpened: {
            const resetButton = standardButton(QQC2.Dialog.Ok);
            if (resetButton) {
                resetButton.text = i18n("Use reset now");
            }
        }
        onAccepted: root.consumeResetCredit()

        contentItem: QQC2.Label {
            width: Kirigami.Units.gridUnit * 20
            text: i18n("Use one limit reset now? This action cannot be undone.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    compactRepresentation: Item {
        implicitWidth: compactLayout.implicitWidth + Kirigami.Units.largeSpacing * 2
        implicitHeight: Math.max(Kirigami.Units.gridUnit * 2, compactLayout.implicitHeight)
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth

        RowLayout {
            id: compactLayout
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: root.codexIcon
                color: root.statusColor
                Layout.preferredWidth: 16
                Layout.preferredHeight: Layout.preferredWidth
            }

            QQC2.Label {
                visible: root.showPercentage && !root.verticalPanel
                    && root.panelPercentage !== ""
                text: root.panelPercentage
                font.weight: Font.DemiBold
                color: root.statusColor
            }
        }

        MouseArea {
            id: compactMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = !root.expanded

            QQC2.ToolTip.visible: containsMouse
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: root.busy
                ? i18n("Refreshing Codex status…")
                : root.errorCode !== ""
                    ? root.errorMessage(root.errorCode)
                    : root.primaryRemaining >= 0
                        ? i18n("Codex · %1% remaining", Math.round(root.primaryRemaining))
                        : i18n("Codex · %1", root.accountLabel)
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        id: fullView

        readonly property bool shortScreen: Screen.height <= 1200
        readonly property real requestedPopupHeight: Kirigami.Units.gridUnit
            * (shortScreen ? 42 : 38)
        readonly property real availablePopupHeight: Math.max(
            Kirigami.Units.gridUnit * 24,
            Screen.availableHeight - Kirigami.Units.largeSpacing * 2)
        readonly property real stablePopupHeight: Math.min(
            requestedPopupHeight,
            availablePopupHeight * 0.9)

        implicitWidth: Kirigami.Units.gridUnit * 27
        implicitHeight: stablePopupHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredWidth: Kirigami.Units.gridUnit * 27
        Layout.maximumWidth: Kirigami.Units.gridUnit * 34
        Layout.minimumHeight: stablePopupHeight
        Layout.preferredHeight: stablePopupHeight
        Layout.maximumHeight: stablePopupHeight

        collapseMarginsHint: true

        ColumnLayout {
            id: content
            anchors {
                fill: parent
                margins: Kirigami.Units.largeSpacing
            }
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: root.codexIcon
                    color: root.statusColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Layout.preferredWidth
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    QQC2.Label {
                        text: i18n("Codex Plasma Center")
                        font.weight: Font.DemiBold
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                        Layout.fillWidth: true
                    }

                    QQC2.Label {
                        text: i18n("%1 · Addon %2", root.accountLabel,
                            root.addonVersion)
                        color: root.statusColor
                        Layout.fillWidth: true
                    }
                }

                QQC2.BusyIndicator {
                    visible: viewTabs.currentIndex === 0 && root.busy
                    running: visible
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Layout.preferredWidth
                }

                QQC2.ToolButton {
                    visible: viewTabs.currentIndex === 0
                    icon.name: "view-refresh"
                    text: i18n("Refresh")
                    display: QQC2.AbstractButton.IconOnly
                    enabled: !root.busy
                    onClicked: root.refresh()

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: text
                }
            }

            QQC2.TabBar {
                id: viewTabs
                Layout.fillWidth: true

                onCurrentIndexChanged: {
                    if (currentIndex === 1) {
                        root.ensureLauncherOptionsLoaded();
                    } else if (currentIndex === 2) {
                        root.ensureThreadsLoaded();
                    }
                }

                QQC2.TabButton {
                    text: i18n("Status")
                }

                QQC2.TabButton {
                    text: i18n("New chat")
                }

                QQC2.TabButton {
                    text: i18n("History")
                }
            }

            Kirigami.InlineMessage {
                visible: viewTabs.currentIndex === 0 && root.errorCode !== ""
                text: root.errorMessage(root.errorCode)
                type: Kirigami.MessageType.Error
                Layout.fillWidth: true
            }

            Kirigami.InlineMessage {
                visible: viewTabs.currentIndex === 0 && root.errorCode === ""
                    && !root.account.authenticated && !root.busy
                text: i18n("Open Codex in a terminal and sign in before checking account usage.")
                type: Kirigami.MessageType.Information
                Layout.fillWidth: true
            }

            ColumnLayout {
                visible: viewTabs.currentIndex === 0 && root.errorCode === ""
                    && root.account.authenticated
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                QQC2.Label {
                    text: i18n("Usage limits")
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                QQC2.Label {
                    visible: root.limitRows.length === 0 && !root.busy
                    text: i18n("Usage windows are not available for this authentication mode.")
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Repeater {
                    model: root.limitRows

                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true

                            QQC2.Label {
                                text: modelData.label
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }

                            QQC2.Label {
                                text: modelData.window.remainingPercent === null
                                    ? i18n("Unavailable")
                                    : i18n("%1% remaining",
                                        Math.round(Number(modelData.window.remainingPercent)))
                                color: Kirigami.Theme.disabledTextColor
                            }
                        }

                        QQC2.ProgressBar {
                            from: 0
                            to: 100
                            value: modelData.window.remainingPercent === null
                                ? 0
                                : Number(modelData.window.remainingPercent)
                            indeterminate: modelData.window.remainingPercent === null
                            Layout.fillWidth: true
                        }

                        QQC2.Label {
                            text: root.resetLabel(modelData.window.resetsAt)
                            color: Kirigami.Theme.disabledTextColor
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            Layout.fillWidth: true
                        }
                    }
                }

                RowLayout {
                    visible: root.resetCreditsAvailable >= 0
                    Layout.fillWidth: true

                    QQC2.Label {
                        text: i18np("%1 limit reset available",
                            "%1 limit resets available", root.resetCreditsAvailable)
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }

                    QQC2.Button {
                        visible: root.resetCreditsAvailable > 0
                        text: i18n("Use reset")
                        enabled: !root.accountActionBusy && !root.busy
                        onClicked: root.requestResetCredit()
                    }
                }
            }

            Kirigami.InlineMessage {
                visible: viewTabs.currentIndex === 0
                    && root.accountActionErrorCode !== ""
                text: root.accountActionErrorMessage(
                    root.accountActionErrorCode)
                type: Kirigami.MessageType.Error
                Layout.fillWidth: true
            }

            Kirigami.InlineMessage {
                visible: viewTabs.currentIndex === 0
                    && root.accountActionNotice !== ""
                text: root.accountActionNotice
                type: Kirigami.MessageType.Positive
                Layout.fillWidth: true
            }

            Kirigami.Separator {
                visible: viewTabs.currentIndex === 0 && root.usageAvailable
                Layout.fillWidth: true
            }

            ColumnLayout {
                visible: viewTabs.currentIndex === 0 && root.usageAvailable
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: i18n("Token activity")
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }

                GridLayout {
                    columns: 2
                    columnSpacing: Kirigami.Units.largeSpacing
                    rowSpacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    QQC2.Label {
                        visible: root.usageSummary.lifetimeTokens !== undefined
                        text: i18n("Lifetime tokens")
                        color: Kirigami.Theme.disabledTextColor
                    }
                    QQC2.Label {
                        visible: root.usageSummary.lifetimeTokens !== undefined
                        text: root.formatInteger(root.usageSummary.lifetimeTokens)
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                    }

                    QQC2.Label {
                        visible: root.usageSummary.peakDailyTokens !== undefined
                        text: i18n("Peak daily tokens")
                        color: Kirigami.Theme.disabledTextColor
                    }
                    QQC2.Label {
                        visible: root.usageSummary.peakDailyTokens !== undefined
                        text: root.formatInteger(root.usageSummary.peakDailyTokens)
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                    }

                    QQC2.Label {
                        visible: root.usageSummary.currentStreakDays !== undefined
                        text: i18n("Current streak")
                        color: Kirigami.Theme.disabledTextColor
                    }
                    QQC2.Label {
                        visible: root.usageSummary.currentStreakDays !== undefined
                        text: i18np("%1 day", "%1 days",
                            Number(root.usageSummary.currentStreakDays))
                        horizontalAlignment: Text.AlignRight
                        Layout.fillWidth: true
                    }
                }
            }

            LauncherView {
                visible: viewTabs.currentIndex === 1
                controller: root
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
            }

            ChatsView {
                visible: viewTabs.currentIndex === 2
                controller: root
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            Item {
                visible: viewTabs.currentIndex === 0
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.smallSpacing
            }

            Kirigami.Separator {
                visible: viewTabs.currentIndex === 0
                Layout.fillWidth: true
            }

            RowLayout {
                visible: viewTabs.currentIndex === 0
                Layout.fillWidth: true

                QQC2.Label {
                    text: root.lastUpdatedLabel
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    Layout.fillWidth: true
                }

                QQC2.Label {
                    visible: root.codexVersion !== ""
                    text: i18n("Codex %1", root.codexVersion)
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }
    }
}
