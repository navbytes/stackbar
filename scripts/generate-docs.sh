#!/bin/sh
# Regenerates the files that are copies of code: llms.txt from
# `stackbarctl docs`, and the ledger in docs/surface-parity.md from
# `stackbarctl parity`. AuthoringTests and SurfaceParityTests fail until
# they match.
set -eu
cd "$(dirname "$0")/.."
swift build --product stackbarctl
CTL="$(swift build --show-bin-path)/stackbarctl"

"$CTL" docs > llms.txt

# Only the table between the markers is generated; the prose around it is not.
"$CTL" parity > docs/surface-parity.ledger.tmp
awk -v ledger=docs/surface-parity.ledger.tmp '
    /^<!-- ledger:end -->$/ { skip = 0 }
    !skip { print }
    /^<!-- ledger:start -->$/ { while ((getline line < ledger) > 0) print line; skip = 1 }
' docs/surface-parity.md > docs/surface-parity.md.tmp
mv docs/surface-parity.md.tmp docs/surface-parity.md
rm docs/surface-parity.ledger.tmp
echo "generate-docs: ok"
