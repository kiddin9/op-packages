#!/bin/sh
# Rescan this package's sources into po/templates/footstrap-files.pot and merge it into every
# po/<lang>/footstrap-files.po. Run after adding or changing ANY _('…') string.
#
#   ./update-po.sh            rescan, merge, report what is still untranslated
#   ./update-po.sh --check    change nothing; fail if the .pot is stale or a string is untranslated
#
# A missing translation cannot fail loudly — an uncompiled _() falls through to its English msgid
# and renders in English with nothing reporting it — so --check is a gate rather than a suggestion.
#
# The directory is `po/`, which is what luci.mk's LUCI_LANGUAGES globs and what Weblate translates.
# Anything else stops luci.mk emitting the per-language packages.
#
# Nothing here runs on the buildbot — luci.mk calls po2lmo itself. This needs perl and gettext,
# which the OpenWrt build does not have.
#
# The scanner is LuCI's OWN build/i18n-scan.pl rather than a grep: it understands the `_('x', 'ctx')`
# second argument and would cover a .ut template if this package ever grew one. A grep would choke
# on the first apostrophe inside a string.
#
# The scanner is fetched from openwrt/luci at the commit in luci-upstream.pin and CHECKSUMMED
# before perl is pointed at it — it is a script downloaded over the network and then executed as
# the gate deciding whether the catalogue is complete, so off a moving branch the gate would be
# whatever upstream pushed last. A local checkout is preferred when there is one, so a developer's
# machine does not need the network; the checksum is verified either way, because a checkout
# sitting on a different commit is exactly the drift the pin exists to catch.
set -eu

cd "$(dirname "$0")"

POT='po/templates/footstrap-files.pot'
CHECK=0
[ "${1:-}" = '--check' ] && CHECK=1

for tool in perl xgettext msgmerge msgfmt msginit; do
	command -v "$tool" >/dev/null || { echo "update-po: $tool not found (install perl + gettext)" >&2; exit 1; }
done

# shellcheck disable=SC1091
. ./luci-upstream.pin

fetched=''; fresh=''; old_ids=''; new_ids=''
# shellcheck disable=SC2064  # expand nothing now: the names are assigned as the script proceeds
trap 'rm -f "$fetched" "$fresh" "$old_ids" "$new_ids"' EXIT INT TERM

scanner=''
for c in "${LUCI_SRC:-}/build/i18n-scan.pl" ../../luci/build/i18n-scan.pl ../../luci-fork/build/i18n-scan.pl; do
	[ -f "$c" ] && { scanner="$c"; break; }
done
if [ -z "$scanner" ]; then
	scanner=$(mktemp); fetched="$scanner"
	curl -sfL --proto '=https' --proto-redir '=https' \
		"https://raw.githubusercontent.com/openwrt/luci/$LUCI_PIN/build/i18n-scan.pl" -o "$scanner" || {
		echo "update-po: cannot fetch i18n-scan.pl — set LUCI_SRC to an openwrt/luci checkout" >&2
		exit 1
	}
fi
echo "$I18N_SCAN_SHA256  $scanner" | sha256sum -c - >/dev/null 2>&1 || {
	echo "update-po: i18n-scan.pl does not match luci-upstream.pin ($LUCI_PIN)" >&2
	exit 1
}

mkdir -p po/templates
fresh="$(mktemp)"
perl "$scanner" htdocs >"$fresh"

# Compare the msgids only. The .pot carries a POT-Creation-Date and source line numbers, so a byte
# comparison reports every run as a change and the gate becomes noise.
ids() { grep '^msgid ' "$1" | sort; }

if [ "$CHECK" = 1 ]; then
	[ -f "$POT" ] || { echo "update-po: $POT is missing" >&2; exit 1; }
	old_ids="$(mktemp)"; new_ids="$(mktemp)"
	ids "$POT" >"$old_ids"; ids "$fresh" >"$new_ids"
	diff -u "$old_ids" "$new_ids" || {
		echo "update-po: $POT is stale — run ./update-po.sh" >&2
		exit 1
	}
else
	cp "$fresh" "$POT"
fi

rc=0
for d in po/*/; do
	lang="${d%/}"; lang="${lang##*/}"
	[ "$lang" = 'templates' ] && continue
	po="$d/footstrap-files.po"
	if [ "$CHECK" = 0 ]; then
		if [ -f "$po" ]; then
			msgmerge --quiet --update --backup=none "$po" "$POT"
		else
			msginit --no-translator --locale="$lang" --input="$POT" --output-file="$po"
		fi
	fi
	[ -f "$po" ] || { echo "update-po: $po is missing" >&2; rc=1; continue; }
	msgfmt --check --statistics -o /dev/null "$po" 2>&1 | sed "s/^/$lang: /"
	# an empty msgstr is a string that will render in English on a translated UI
	untranslated=$(msgattrib --untranslated "$po" | grep -c '^msgid "' || true)
	if [ "$untranslated" -gt 1 ]; then
		echo "$lang: $((untranslated - 1)) untranslated" >&2
		[ "$CHECK" = 1 ] && rc=1
	fi
done

exit "$rc"
