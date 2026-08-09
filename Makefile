DOMAIN := plasma_applet_com.github.codexplasmacenter
VERSION := 0.7.1
PACKAGE := dist/codex-plasma-center-$(VERSION).plasmoid

.PHONY: check translations package clean

check:
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
	qmllint package/contents/ui/*.qml package/contents/config/*.qml
	msgfmt --check --check-format po/es.po -o /dev/null
	xmllint --noout package/contents/config/main.xml
	git diff --check

translations:
	sh Messages.sh
	mkdir -p package/contents/locale/es/LC_MESSAGES
	msgfmt --check --check-format po/es.po \
		-o package/contents/locale/es/LC_MESSAGES/$(DOMAIN).mo

package: translations
	mkdir -p dist
	cd package && bsdtar --format zip -cf ../$(PACKAGE) \
		metadata.json contents/config contents/icons contents/locale \
		contents/tools/codex_account_actions.py contents/tools/codex_launcher.py \
		contents/tools/codex_status.py contents/tools/codex_threads.py \
		contents/tools/terminal_launcher.py \
		contents/ui LICENSE NOTICE

clean:
	find . -type d -name __pycache__ -prune -exec rm -r {} +
	rm -f $(PACKAGE)
