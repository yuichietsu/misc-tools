#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") INPUT_IMAGE OUTPUT_PATH [--size WIDTHxHEIGHT|banner|icon] [--svg] [--background COLOR]

Produces an Android Vector Drawable XML. The `--size` flag controls whether the
tool will annotate the produced AVD with intended-usage metadata and set
`android:width`/`android:height` and `android:viewportWidth`/`android:viewportHeight`.

`--size` accepts either WIDTHxHEIGHT (e.g. 512x512) or the aliases `banner` and `icon`.
  - `--size banner` → 320x180
  - `--size icon`   → 108x108

Requires ImageMagick (`magick` or `convert`) and `svg2vectordrawable` (or `npx`) for `vector` mode.

Examples:
  $(basename "$0") input.png output.xml                      # vector (Android Vector Drawable)
  $(basename "$0") input.png banner.png --type banner         # PNG for android:banner
  $(basename "$0") input.png app_icon.png --type icon --size 512x512  # PNG for android:icon
  $(basename "$0") input.png output.xml --background white
EOF
  exit 2
}

if [ "$#" -lt 2 ]; then
  usage
fi

INPUT="$1"
OUTPUT="$2"

# Defaults
SIZE=""
BG=""
SAVE_SVG=0

# Consume the first two positional args and parse remaining flags
shift 2
while [ "$#" -gt 0 ]; do
  case "$1" in
    --background)
      BG="${2:-}"
      shift 2
      ;;
    --size)
      SIZE="${2:-}"
      shift 2
      ;;
    --svg)
      SAVE_SVG=1
      shift 1
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

command_exists() { command -v "$1" >/dev/null 2>&1; }

if command_exists magick; then
  IM_CMD="magick"
elif command_exists convert; then
  IM_CMD="convert"
else
  echo "Error: ImageMagick 'magick' or 'convert' is required." >&2
  exit 1
fi

if command_exists svg2vectordrawable; then
  SVG2VD_CMD="svg2vectordrawable"
elif command_exists npx; then
  SVG2VD_CMD="npx svg2vectordrawable"
else
  echo "Error: 'svg2vectordrawable' or 'npx' is required to produce Android Vector Drawable output." >&2
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: input file '$INPUT' not found." >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
SVG="$TMPDIR/converted.svg"

echo "Converting '$INPUT' -> temporary SVG..."
SRC_INPUT="$INPUT"

# Auto-detect dark-background / light-foreground images and invert before
# tracing so potrace traces the artwork instead of the background. Compute
# mean brightness (0..1); if < 0.5 we assume dark overall and invert.
MEAN=$("$IM_CMD" "$INPUT" -colorspace Gray -format "%[fx:mean]" info: 2>/dev/null || true)
NEED_INVERT=0
if [ -n "$MEAN" ]; then
  if [ "$(awk -v m="$MEAN" 'BEGIN{print(m<0.5?1:0)}')" -eq 1 ]; then
    NEED_INVERT=1
  fi
fi

if [ "$NEED_INVERT" -eq 1 ]; then
  PROC_INPUT="$TMPDIR/processed.png"
  echo "Inverting colors for better tracing (detected dark image)..."
  "$IM_CMD" "$INPUT" -channel RGB -negate "$PROC_INPUT"
  SRC_INPUT="$PROC_INPUT"
fi

if [ -n "$BG" ]; then
  # If a background color is requested, flatten to that color.
  "$IM_CMD" "$SRC_INPUT" -background "$BG" -flatten "$SVG"
else
  # Preserve transparency when converting to SVG so dark backgrounds don't appear.
  # Use explicit alpha and background none to keep transparent regions.
  "$IM_CMD" "$SRC_INPUT" -alpha set -background none "$SVG"
fi

# If we inverted before tracing, flip common fill colors in the SVG so the
# final artwork color matches the original (white on dark -> white fill).
if [ "$NEED_INVERT" -eq 1 ]; then
  perl -0777 -i -pe 's/fill="#000000"/fill="#ffffff"/gi; s/fill="#000"/fill="#ffffff"/gi' "$SVG"
fi

echo "Running svg2vectordrawable to produce Android Vector Drawable -> '$OUTPUT'..."
eval "$SVG2VD_CMD -i \"$SVG\" -o \"$OUTPUT\""

# If requested, save the intermediate SVG to a file derived from the OUTPUT path
if [ "$SAVE_SVG" -eq 1 ]; then
  SVG_OUTPUT="${OUTPUT%.*}.svg"
  echo "Saving intermediate SVG -> '$SVG_OUTPUT'..."
  cp "$SVG" "$SVG_OUTPUT"
fi

# If user provided --size (either WIDTHxHEIGHT or alias), adjust attributes and
# optionally add an intended-usage comment for alias values (banner/icon).
if [ -n "$SIZE" ]; then
  ORIG_SIZE="$SIZE"

  # Default sizes when alias used; numeric sizes pass through
  if [ "$SIZE" = "banner" ]; then
    SIZE="320x180"
  elif [ "$SIZE" = "icon" ]; then
    SIZE="108x108"
  fi

  WIDTH="${SIZE%x*}"
  HEIGHT="${SIZE#*x}"
  if ! [[ "$WIDTH" =~ ^[0-9]+$ ]] || ! [[ "$HEIGHT" =~ ^[0-9]+$ ]]; then
    echo "Error: invalid --size format. Use WIDTHxHEIGHT or 'banner'/'icon' aliases" >&2
    exit 1
  fi

  # Determine usage label only for aliases
  USAGE=""
  if [ "$ORIG_SIZE" = "banner" ] || [ "$ORIG_SIZE" = "icon" ]; then
    USAGE="$ORIG_SIZE"
  fi

  echo "Annotating Vector Drawable (size ${WIDTH}x${HEIGHT})..."

  # Use environment variables to pass size values into perl to avoid shell
  # quoting/expansion issues.
  PERL_W="$WIDTH" PERL_H="$HEIGHT" PERL_USAGE="$USAGE" \
    perl -0777 -i -pe '
      my $w = $ENV{"PERL_W"};
      my $h = $ENV{"PERL_H"};
      my $usage = $ENV{"PERL_USAGE"} // "";
      if ($usage ne "") {
        s/(<\?xml[^>]*\?>\s*)/$1."<!-- intended-usage: ".$usage." -->\n"/e;
      }
      if (s/(<vector\b[^>]*?)android:width="[^"]*"/ $1 . "android:width=\"".$w."px\"" /e) { }
      else { s/(<vector\b)/$1 . " android:width=\"".$w."px\""/e }
      if (s/(<vector\b[^>]*?)android:height="[^"]*"/ $1 . "android:height=\"".$h."px\"" /e) { }
      else { s/(<vector\b)/$1 . " android:height=\"".$h."px\""/e }
      if (s/(<vector\b[^>]*?)android:viewportWidth="[^"]*"/ $1 . "android:viewportWidth=\"".$w."\"" /e) { }
      else { s/(<vector\b)/$1 . " android:viewportWidth=\"".$w."\""/e }
      if (s/(<vector\b[^>]*?)android:viewportHeight="[^"]*"/ $1 . "android:viewportHeight=\"".$h."\"" /e) { }
      else { s/(<vector\b)/$1 . " android:viewportHeight=\"".$h."\""/e }
    ' "$OUTPUT"

  echo "Annotated: $OUTPUT"
fi

echo "Done: $OUTPUT"
