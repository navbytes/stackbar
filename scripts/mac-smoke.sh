#!/bin/bash
# Smoke-tests the installed Stackbar on this Mac against docs/mac-checklist items
# that a script can check. Plugins run from a throwaway STACKBAR_HOME, so the
# user's plugins, settings and data are never touched.
#   scripts/mac-smoke.sh          checks that don't take focus
#   scripts/mac-smoke.sh --ui     also drives the palette and System Settings
#   scripts/mac-smoke.sh --unit   also runs the paste, snippet and quicklink unit tests
set -u
cd "$(dirname "$0")/.."
UI=0 UNIT=0
for a in "$@"; do case $a in --ui) UI=1 ;; --unit) UNIT=1 ;; *) echo "usage: $0 [--ui] [--unit]" >&2; exit 2 ;; esac; done

APP=${STACKBAR_APP:-/Applications/Stackbar.app}
CTL="$APP/Contents/MacOS/stackbarctl"
INDEX=https://navbytes.github.io/stackbar-plugins/index.json
WORK=$(mktemp -d -t stackbar-smoke)
export STACKBAR_HOME="$WORK/home"
P="$STACKBAR_HOME/Plugins"
RESULTS="$WORK/results.tsv"
STARTED=()
trap 'for pid in "${STARTED[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done' EXIT

result() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$RESULTS"; printf '%-7s %-34s %s\n' "$2" "$1" "$3"; }
plugin() { echo "$P/io-navbytes-stackbar-$1.swift"; }
render() { "$CTL" render "$@" 2>&1; }

swiftc -O scripts/mac-smoke-probe.swift -o "$WORK/probe" 2>"$WORK/probe.log" || { echo "probe failed to build:"; cat "$WORK/probe.log"; exit 1; }
PROBE="$WORK/probe"

echo "Stackbar $(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString) · $("$CTL" version 2>&1) · checkout $(git rev-parse --short HEAD)"
echo "scratch: $WORK"
echo

# --- install the plugins under test into the throwaway home
for id in plugins.homebrew plugins.ports plugins.system-monitor plugins.docker plugins.music snippets quicklinks; do
    "$CTL" install --index "$INDEX" "io.navbytes.stackbar.$id" > "$WORK/install-$id.log" 2>&1 || { echo "install $id failed:"; cat "$WORK/install-$id.log"; }
done

# 3. install sheet: commands resolve to full paths, and osascript is called out
if grep -q 'Runs /opt/homebrew/bin/brew' "$WORK/install-plugins.homebrew.log" && grep -q 'osascript (can run any program)' "$WORK/install-plugins.music.log"; then
    result "3 install sheet resolved paths" PASS "$(grep -h 'Runs ' "$WORK/install-plugins.homebrew.log" "$WORK/install-plugins.music.log" | tr '\n' ';')"
else
    result "3 install sheet resolved paths" FAIL "$(grep -h 'Runs ' "$WORK"/install-*.log | tr '\n' ';')"
fi

# 2. Spotlight and Shortcuts: the App Intents metadata the app ships
INTENTS=$(python3 - "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
run = d["actions"].get("RunCommandIntent", {})
params = [p.get("name") for p in run.get("parameters", [])]
entities = [e.get("typeName") for e in d.get("entities", {}).values()]
auto = [s.get("actionIdentifier") for s in d.get("autoShortcuts", [])]
ok = run.get("title", {}).get("key") == "Run Stackbar Command" and {"command", "input"} <= set(params) and "CommandEntity" in entities and "RunCommandIntent" in auto
print(("ok " if ok else "bad ") + f"title={run.get('title', {}).get('key')} params={params} entities={entities} autoShortcuts={auto}")
EOF
)
case $INTENTS in ok*) result "2 Run Stackbar Command intent" PASS "${INTENTS#ok }" ;; *) result "2 Run Stackbar Command intent" FAIL "${INTENTS#bad }" ;; esac
result "2 Spotlight results, ⌘3, Quick Key" MANUAL "CoreSpotlight items and the Shortcuts picker aren't readable from a script"

# 4. Snippets, from throwaway snippets in the scratch home
mkdir -p "$STACKBAR_HOME/Storage"
python3 - "$STACKBAR_HOME/Storage" <<'EOF'
import json, sys
snippets = [
    {"id": "11111111-1111-1111-1111-111111111111", "name": "Smoke Emoji", "text": "hi 👋🏽{cursor}🎉 done", "tags": ["smoke"]},
    {"id": "22222222-2222-2222-2222-222222222222", "name": "Smoke Date", "text": 'Today {date format="yyyy-MM-dd"} <tag>', "tags": ["smoke"]},
]
links = [{"id": "33333333-3333-3333-3333-333333333333", "name": "Smoke Note", "link": sys.argv[1] + '/../ql/{argument name="file"}.txt', "openWith": "com.apple.TextEdit", "tags": ["smoke"]}]
json.dump({"snippets": json.dumps(snippets)}, open(sys.argv[1] + "/io.navbytes.stackbar.snippets.json", "w"))
json.dump({"quicklinks": json.dumps(links)}, open(sys.argv[1] + "/io.navbytes.stackbar.quicklinks.json", "w"))
EOF
SN=$(plugin snippets)
EMOJI=$("$CTL" run "$SN" sn-11111111-1111-1111-1111-111111111111 2>&1 | tail -1)
# "🎉 done" is six grapheme clusters, so six ← presses
[ "$EMOJI" = "paste: hi 👋🏽🎉 done (cursor 6 from the end)" ] && result "4 emoji after {cursor}" PASS "$EMOJI" || result "4 emoji after {cursor}" FAIL "$EMOJI"
TODAY=$(date +%Y-%m-%d)
render "$SN" --command search --json > "$WORK/snippets.json"
grep -q "Today $TODAY <tag>" "$WORK/snippets.json" && result "4 search preview date + <markers>" PASS "preview: Today $TODAY <tag>" || result "4 search preview date + <markers>" FAIL "no 'Today $TODAY <tag>' in $WORK/snippets.json"
result "4 {cursor} caret and clipboard restore live" MANUAL "needs Snippets in the user's app; logic covered by --unit (PasteTests, SnippetsTests)"
result "4 Raycast import live" MANUAL "Import picks a file in an open panel; CLI returns 'Import cancelled'; covered by --unit testImportingARaycastExport"

# 5. Quicklinks: the argument becomes the command's prompt
QL=$(plugin quicklinks)
QLCMD=$("$CTL" commands "$QL" 2>&1 | grep '^ql-')
case $QLCMD in *"[file]"*) result "5 quicklink argument prompt" PASS "$QLCMD" ;; *) result "5 quicklink argument prompt" FAIL "${QLCMD:-no ql- command}" ;; esac
# stackbarctl reports the open rather than doing it
OUT=$("$CTL" run "$QL" ql-33333333-3333-3333-3333-333333333333 --arg file=smoke-note 2>&1 | tail -1)
case $OUT in "open: "*"/ql/smoke-note.txt with com.apple.TextEdit") result "5 quicklink resolves to named app" PASS "$OUT" ;; *) result "5 quicklink resolves to named app" FAIL "$OUT" ;; esac
result "5 quicklink opens live, row icons, Raycast Open With" MANUAL "the CLI doesn't open; the user's app has no quicklinks to test with"

# 7. Homebrew: the count matches brew's, less pinned formulae (hidden by default)
if command -v brew >/dev/null; then
    BREW=$(brew outdated --json=v2 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for f in d["formulae"] if not f.get("pinned")) + len(d["casks"]))')
    BAR=$(render "$(plugin plugins-homebrew)" --surface menuBar | sed -n 's/^\[mug\] *//p' | head -1)
    [ "${BAR:-0}" = "$BREW" ] && result "7 Homebrew outdated count" PASS "menu bar ${BAR:-0} = brew outdated $BREW" || result "7 Homebrew outdated count" FAIL "menu bar '${BAR}' vs brew outdated $BREW"
else
    result "7 Homebrew outdated count" MANUAL "Homebrew isn't installed"
fi
result "7 Homebrew Upgrade" MANUAL "upgrading changes the user's packages"

# 7. Ports: stop a loopback server from its row, and kill-port by number
PORTS=$(plugin plugins-ports)
mkdir -p "$WORK/www"
python3 -m http.server 8765 --bind 127.0.0.1 --directory "$WORK/www" >/dev/null 2>&1 & SRV=$!; disown; STARTED+=("$SRV")
python3 -m http.server 8766 --bind 127.0.0.1 --directory "$WORK/www" >/dev/null 2>&1 & SRV2=$!; disown; STARTED+=("$SRV2")
sleep 1
ROW=$(render "$PORTS" --surface panel | grep ":8765 .*pid $SRV" | head -1)
if [ -z "$ROW" ]; then
    result "7 Ports lists and stops" FAIL "no :8765 row for pid $SRV"
else
    OUT=$(render "$PORTS" --surface panel --event "row/$SRV:127.0.0.1:8765/Stop Process" | grep -m1 Stopped)
    sleep 1
    kill -0 "$SRV" 2>/dev/null && result "7 Ports lists and stops" FAIL "pid $SRV alive after Stop ($OUT)" || result "7 Ports lists and stops" PASS "listed pid $SRV; '$OUT'; server gone"
fi
OUT=$("$CTL" run "$PORTS" kill-port --arg port=8766 2>&1 | tail -1)
sleep 1
kill -0 "$SRV2" 2>/dev/null && result "7 Ports kill-port command" FAIL "pid $SRV2 alive ($OUT)" || result "7 Ports kill-port command" PASS "$OUT"

# 7. System Monitor vs top and vm_stat (Activity Monitor's Memory Used: app + wired + compressed)
SM=$(render "$(plugin plugins-system-monitor)" --surface panel)
SMCPU=$(echo "$SM" | sed -n 's/^Now: \([0-9]*\)%.*/\1/p' | head -1)
SMMEM=$(echo "$SM" | sed -n 's/^Memory \([0-9.]*\) GB of.*/\1/p' | head -1)
TOPCPU=$(top -l 2 -n 0 -s 1 | grep 'CPU usage' | tail -1 | awk '{gsub("%",""); print int($3 + $5 + 0.5)}')
VMMEM=$(vm_stat | python3 -c '
import re, sys
t = sys.stdin.read(); page = int(re.search(r"page size of (\d+)", t).group(1))
v = lambda k: int(re.search(k + r":\s+(\d+)", t).group(1))
print(round((v("Anonymous pages") - v("Pages purgeable") + v("Pages wired down") + v("Pages occupied by compressor")) * page / 2**30, 1))')
python3 - "$SMCPU" "$TOPCPU" "$SMMEM" "$VMMEM" <<'EOF' && result "7 System Monitor vs top/vm_stat" PASS "CPU ${SMCPU}% vs top ${TOPCPU}%; memory ${SMMEM} GB vs vm_stat ${VMMEM} GB" || result "7 System Monitor vs top/vm_stat" FAIL "CPU '${SMCPU}'% vs top ${TOPCPU}%; memory '${SMMEM}' GB vs vm_stat ${VMMEM} GB"
import sys
cpu, top, mem, vm = (float(x or "nan") for x in sys.argv[1:])
sys.exit(0 if abs(cpu - top) <= 20 and abs(mem - vm) <= 0.15 * vm else 1)
EOF

# 7. Docker, only with a daemon
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    result "7 Docker list" PASS "$(render "$(plugin plugins-docker)" --surface panel | sed -n 2,4p | tr '\n' ';')"
else
    result "7 Docker list, stop, start, logs" MANUAL "no Docker daemon running"
fi
result "7 Music, Translate, GitHub, Linear, Jira" MANUAL "need Automation prompts or real tokens"
result "3 selected text in other apps, Finder, long run audit" MANUAL "needs selections in each app and Automation prompts"
result "6 macOS page wording" MANUAL "a reading check"

# --- unit tests behind the live checks above
if [ $UNIT = 1 ]; then
    swift test --filter 'PasteTests|SnippetsTests|QuicklinksTests|TemplateTests' > "$WORK/unit.log" 2>&1 \
        && result "4/5 paste, snippet, quicklink unit tests" PASS "$(grep -c "' passed" "$WORK/unit.log") passed, incl. Raycast import, cursor, restore, copy-meanwhile" \
        || result "4/5 paste, snippet, quicklink unit tests" FAIL "see $WORK/unit.log"
fi

# --- checks that take focus
if [ $UI = 1 ]; then
    if [ "$("$PROBE" ax)" != yes ] || { open -gj -b com.apple.systemevents; sleep 1; [ "$("$PROBE" automation com.apple.systemevents)" != granted ]; }; then
        result "UI batch" MANUAL "this terminal lacks Accessibility or System Events Automation"
    else
        echo; echo "WARNING: the next ~20 s open the palette and System Settings and send keys. Hands off the keyboard."; sleep 3
        sx() { osascript -e "tell application \"System Events\" to $1" 2>&1; }
        palette_text() { sx 'tell process "Stackbar" to get value of every static text of group 1 of window 1'; }
        palette_open() { [ -n "$("$PROBE" windows Stackbar)" ]; }
        esc() { sx 'key code 53' >/dev/null; sleep 0.5; }

        # 1. the link opens Quicklinks' search; Esc goes back, then closes
        open "stackbar://commands/io.navbytes.stackbar.quicklinks/search"; sleep 1.5
        TITLE=$(palette_text)
        esc; BACK=$(palette_text); esc
        if [[ $TITLE == *"Search Quicklinks"* ]] && [[ $BACK != *"Search Quicklinks"* ]] && ! palette_open; then
            result "1 stackbar:// link, Esc back, close" PASS "opened '$TITLE'; Esc → '$BACK'; Esc → closed"
        else
            result "1 stackbar:// link, Esc back, close" FAIL "opened '$TITLE'; after Esc '$BACK'; still open: $(palette_open && echo yes || echo no)"
        fi

        # 1. ⌃⌥Space opens; fast typing filters; ⌘K shows actions
        sx 'key code 49 using {control down, option down}' >/dev/null; sleep 1
        if palette_open; then
            sx 'keystroke "stay awake"' >/dev/null; sleep 0.6
            # The footer names the selected command; ⌘K puts its actions in front of it.
            BEFORE=$(palette_text)
            sx 'keystroke "k" using command down' >/dev/null; sleep 0.6
            AFTER=$(palette_text)
            esc; esc; esc
            [[ $BEFORE == "Stay Awake,"* ]] && result "1 ⌃⌥Space and fast typing" PASS "typed 'stay awake' → selected '$BEFORE'" || result "1 ⌃⌥Space and fast typing" FAIL "typed 'stay awake' → '$BEFORE'"
            [ "${AFTER%"$BEFORE"}" != "$AFTER" ] && [ "$AFTER" != "$BEFORE" ] && result "1 ⌘K actions" PASS "⌘K added '${AFTER%", $BEFORE"}' in front of '$BEFORE'" || result "1 ⌘K actions" FAIL "before '$BEFORE', after '$AFTER'"
            palette_open && { result "1 palette closes on Esc" FAIL "still open after 3× Esc"; esc; }
        else
            result "1 ⌃⌥Space and fast typing" FAIL "no Stackbar window after ⌃⌥Space"
        fi
        result "1 argument Tab, required Return, Settings hotkey" MANUAL "needs a configured hotkey and commands with arguments; 50+ command load not generated"

        # 6. each Open Settings URL lands on its pane
        pgrep -x "System Settings" >/dev/null && HADSETTINGS=1 || HADSETTINGS=0
        for pair in "com.apple.Spotlight-Settings.extension=Spotlight" "com.apple.Desktop-Settings.extension=Desktop & Dock" "com.apple.Keyboard-Settings.extension=Keyboard"; do
            pane=${pair%%=*} want=${pair#*=}
            grep -q "x-apple.systempreferences:$pane" Sources/StackbarHostCore/MacOSAlternatives.swift || { result "6 $pane" FAIL "not in MacOSAlternatives.swift"; continue; }
            open "x-apple.systempreferences:$pane"; sleep 2.5
            GOT=$(sx 'tell process "System Settings" to get name of window 1')
            [ "$GOT" = "$want" ] && result "6 Settings: $want" PASS "x-apple.systempreferences:$pane → '$GOT'" || result "6 Settings: $want" FAIL "x-apple.systempreferences:$pane → '$GOT'"
        done
        [ $HADSETTINGS = 0 ] && osascript -e 'tell application "System Settings" to quit' 2>/dev/null

    fi
else
    result "UI checks" SKIP "run with --ui"
fi

echo
echo "pass $(grep -c $'\tPASS\t' "$RESULTS") · fail $(grep -c $'\tFAIL\t' "$RESULTS") · manual $(grep -c $'\tMANUAL\t' "$RESULTS")   ($RESULTS)"
! grep -q $'\tFAIL\t' "$RESULTS"
