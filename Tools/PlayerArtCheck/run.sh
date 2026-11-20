#!/bin/zsh
# The player art check: every sheet frame recoloured in a spread of looks, its map made, and
#   maps    - every map made exactly, looks of one shape making the same map (`PlayerMap.ShapeKey`);
#   gpu N   - every Nth frame drawn through the map shaders at several scales, turns and tints,
#             against its old pictures drawn as SpriteKit drew them: every pixel the same.
# Run from the project folder: Tools/PlayerArtCheck/run.sh [maps|gpu N]
set -e
here="${0:A:h}"
root="${here:h:h}"
build="${TMPDIR:-/tmp}/PlayerArtCheck"
mkdir -p "$build"
sed -n '/^enum HoodView {/,/^}/p' "$root/ProjectEsper/View/SpriteLibrary.swift" > "$build/hoodview.swift"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -O -o "$build/check" \
    "$root"/EsperSim/Sources/EsperSim/*.swift "$root/EsperSim/Greateraid.swift" \
    "$root/ProjectEsper/Art/PlayerPalette.swift" "$root/ProjectEsper/Art/PixelPalette.swift" \
    "$root/ProjectEsper/Art/PlayerRecolour.swift" "$root/ProjectEsper/Art/PlayerMap.swift" \
    "$here"/stub.swift "$build/hoodview.swift" "$here"/common.swift "$here"/maps.swift "$here"/gpu.swift "$here"/main.swift
"$build/check" "$root/ProjectEsper/Assets.xcassets/Sprites.spriteatlas" "$@" 2>&1 | grep -v "unused variable\|float extra\|^ *\^ *$"
