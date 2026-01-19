#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") INPUT_IMAGE OUTPUT_PATH [--type TYPE] [--size WIDTHxHEIGHT] [--background COLOR]

Produces output tailored for different Android usage types (the file format depends on the type):
  - vector:  Produces an Android Vector Drawable XML (file format = Android Vector Drawable). This is the default.
  - banner:  Produces a PNG intended to be used as `android:banner` in an Android app (raster PNG).
  - icon:    Produces a PNG intended to be used as `android:icon` in an Android app (raster PNG).

Note: the `--type` selects the intended usage within an Android app (banner/icon/etc.), not the general image file format.

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
TYPE="vector"
SIZE=""
BG=""

# Consume the first two positional args and parse remaining flags
shift 2
while [ "$#" -gt 0 ]; do
  case "$1" in
    --background)
      BG="${2:-}"
      shift 2
      ;;
    --type)
      TYPE="${2:-}"
      shift 2
      ;;
    --size)
      SIZE="${2:-}"
      shift 2
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

case "$TYPE" in
  vector|banner|icon)
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    SVG="$TMPDIR/converted.svg"

    echo "Converting '$INPUT' -> temporary SVG..."
    if [ -n "$BG" ]; then
      "$IM_CMD" "$INPUT" -background "$BG" -flatten "$SVG"
    else
      "$IM_CMD" "$INPUT" "$SVG"
    fi

    echo "Running svg2vectordrawable to produce Android Vector Drawable -> '$OUTPUT'..."
    eval "$SVG2VD_CMD -i \"$SVG\" -o \"$OUTPUT\""

    # If user requested a specific usage type (banner/icon) or provided --size,
    # adjust the produced Vector Drawable's root attributes (width/height/viewport)
    # so the AVD carries metadata appropriate for that usage.
    if [ "$TYPE" != "vector" ] || [ -n "$SIZE" ]; then
      # Default sizes when not explicitly provided
      if [ -z "$SIZE" ]; then
        if [ "$TYPE" = "banner" ]; then
          SIZE="1920x720"
        else
          SIZE="512x512"
        fi
      fi

      WIDTH="${SIZE%x*}"
      HEIGHT="${SIZE#*x}"
      if ! [[ "$WIDTH" =~ ^[0-9]+$ ]] || ! [[ "$HEIGHT" =~ ^[0-9]+$ ]]; then
        echo "Error: invalid --size format. Use WIDTHxHEIGHT, e.g. 512x512" >&2
        exit 1
      fi

      # Update vector drawable attributes: android:width/android:height (px)
      # and android:viewportWidth/android:viewportHeight
      # Insert an intended-usage XML comment and adjust attributes robustly using perl
      echo "Annotating Vector Drawable for usage '$TYPE' (size ${WIDTH}x${HEIGHT})..."

      perl -0777 -i -pe '
        my $w = "$WIDTH"; my $h = "$HEIGHT"; my $usage = "$TYPE";
        # add intended-usage comment after XML declaration
        s/(<\?xml[^>]*\?>\s*)/$1."<!-- intended-usage: ".$usage." -->\n"/e;
        # replace or add android:width/android:height attributes (use px)
        if (s/(<vector\b[^>]*?)android:width="[^"]*"/ $1 . "android:width=\"".$w."px\"" /e) { }
        else { s/(<vector\b)/$1 . " android:width=\"".$w."px\""/e }
        if (s/(<vector\b[^>]*?)android:height="[^"]*"/ $1 . "android:height=\"".$h."px\"" /e) { }
        else { s/(<vector\b)/$1 . " android:height=\"".$h."px\""/e }
        # replace or add viewport attributes (numeric)
        if (s/(<vector\b[^>]*?)android:viewportWidth="[^"]*"/ $1 . "android:viewportWidth=\"".$w."\"" /e) { }
        else { s/(<vector\b)/$1 . " android:viewportWidth=\"".$w."\""/e }
        if (s/(<vector\b[^>]*?)android:viewportHeight="[^"]*"/ $1 . "android:viewportHeight=\"".$h."\"" /e) { }
        else { s/(<vector\b)/$1 . " android:viewportHeight=\"".$h."\""/e }
      ' "$OUTPUT"

      echo "Annotated: $OUTPUT"
    fi

    echo "Done: $OUTPUT"
    ;;

  *)
    echo "Error: unknown type '$TYPE'. Supported types: vector, banner, icon" >&2
    usage
    ;;
esac
