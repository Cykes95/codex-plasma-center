#!/bin/sh

set -eu

translation_domain="plasma_applet_com.github.codexplasmacenter"
project_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pot_directory="$project_root/po"

mkdir -p "$pot_directory"
cd "$project_root"
find package/contents -name '*.qml' -print0 \
    | xargs -0 xgettext \
        --from-code=UTF-8 \
        --language=JavaScript \
        --keyword=i18n \
        --keyword=i18np:1,2 \
        --package-name="Codex Plasma Center" \
        --output="$pot_directory/$translation_domain.pot"

sed -i \
    -e 's/^# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR\.$/# Codex Plasma Center contributors, 2026./' \
    -e 's/"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\n"/"Last-Translator: Codex Plasma Center contributors\\n"/' \
    -e 's/"Language-Team: LANGUAGE <LL@li\.org>\\n"/"Language-Team: translators\\n"/' \
    "$pot_directory/$translation_domain.pot"
