#!/bin/bash
# Builds the app icon from the web app's cake mark.
#
#   ./scripts/make-icon.sh [path-to-sudoku-and-cake]
#
# The mark is the same slice of cake as sudoku.andcake.dev, because the two apps
# are one product and an icon is the only part of that anyone sees before
# installing. Rendered from the web repo's logo.svg rather than copied from its
# PNGs: the PNGs are 512 px with transparency, and an iOS icon needs 1024 px with
# none.
#
# Three variants, which is what iOS 18 asks for:
#   light   dark mark on warm cream, the default
#   dark    cream mark on near-black, for a dark Home Screen
#   tinted  greyscale, for the system to tint — so it must carry no colour at all
#
# Committed as a script rather than just its output for the same reason as the
# sounds: an icon defined by a command can be adjusted, and one that arrived as a
# binary cannot.
set -euo pipefail

cd "$(dirname "$0")/.."

WEB=${1:-../sudoku-and-cake}
LOGO="$WEB/frontend/public/logo.svg"
OUT=SudokuApp/Resources/Assets.xcassets/AppIcon.appiconset

if [ ! -f "$LOGO" ]; then
    echo "No logo at $LOGO — pass the path to the sudoku-and-cake checkout." >&2
    exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is needed to rasterise the SVG: brew install imagemagick" >&2
    exit 1
fi

mkdir -p "$OUT"

# The mark sits at 72% of the canvas. iOS rounds the corners and, on the Home
# Screen, shrinks what is inside them; a mark drawn to the edges reads as
# cramped next to every other icon on the row, and one drawn much smaller
# disappears into it.
INSET=740

# The logo is a line drawing, and a line drawing scaled down to 40 points is a
# line drawing you cannot see. Thickening the strokes before the system ever
# shrinks it is the difference between a recognisable slice of cake and a smudge
# — checked at 120 px, which is where it actually has to work.
WEIGHT="Octagon:3"

render() {
    local background=$1 foreground=$2 output=$3
    magick -background none "$LOGO" -resize ${INSET}x${INSET} \
        -channel RGB -fill "$foreground" -colorize 100 +channel \
        -morphology Dilate "$WEIGHT" \
        -background "$background" -gravity center -extent 1024x1024 \
        -alpha remove -alpha off \
        "PNG24:$output"
}

# Warm cream rather than white: the mark is a brown line drawing, and white
# behind it is colder than anything on either app's screens.
render "#FDF6EC" "#5C4033" "$OUT/icon-light.png"
render "#0A0A0A" "#E8D5C4" "$OUT/icon-dark.png"

# The tinted variant is composited by the system against its own background, so
# it ships as a greyscale mark on black — any colour here would survive tinting
# and clash with whatever the player has chosen.
magick -background none "$LOGO" -resize ${INSET}x${INSET} \
    -channel RGB -fill white -colorize 100 +channel \
    -morphology Dilate "$WEIGHT" \
    -background black -gravity center -extent 1024x1024 \
    -alpha remove -alpha off -colorspace Gray \
    "PNG24:$OUT/icon-tinted.png"

cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon-light.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Wrote $OUT:"
ls -1 "$OUT"
