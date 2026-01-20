#!/usr/bin/env bash
set -euo pipefail

# img2ftvappicons.sh
# 入力画像から Fire TV 用のアイコンセットを生成します。
# Usage: img2ftvappicons.sh input.png output_dir
# 生成するファイル:
#  - banner_320x180.png  (App Banner)
#  - launcher_108x108.png (Launcher Icon)

SCALE=100
VSHIFT=0
HSHIFT=0

print_usage() {
  cat <<EOF
Usage: $0 [--scale PERCENT|MULTIPLIER] [--vshift PIXELS] INPUT_IMAGE OUTPUT_DIR

Options:
  --scale    Scale input around its center. Accepts percent (e.g. 120) or multiplier (e.g. 1.2). Default: 100
  --vshift   Vertical shift in pixels applied after centering (positive moves image down). Default: 0
  --hshift   Horizontal shift in pixels applied after centering (positive moves image right). Default: 0
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -s|--scale)
      shift
      SCALE="$1"
      ;;
    -y|--vshift|--vshift-px)
      shift
      VSHIFT="$1"
      ;;
    -x|--hshift|--hshift-px)
      shift
      HSHIFT="$1"
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1"
      print_usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
  shift || true
done

if [ "$#" -ne 2 ]; then
  print_usage
  exit 2
fi

INPUT="$1"
OUTDIR="$2"

if [ ! -f "$INPUT" ]; then
  echo "Input file not found: $INPUT"
  exit 3
fi

if ! command -v convert >/dev/null 2>&1; then
  echo "ImageMagick 'convert' is required but not found in PATH."
  exit 4
fi

mkdir -p "$OUTDIR"

# Helper: generate an image for target WxH. We use '^' to ensure the image
# fills the box on the short side, then center-crop with -extent.
generate() {
  local in="$1"
  local out="$2"
  local W="$3"
  local H="$4"

  # Determine background color from the top-left pixel of the input.
  # If the sampled pixel is fully transparent, fall back to white.
  local bg
  bg=$(convert "${in}[0]" -format "%[pixel:p{0,0}]" info:- 2>/dev/null || echo "white")
  if echo "$bg" | grep -Eq ",[[:space:]]*0\)?$"; then
    bg="white"
  fi

  # Normalize SCALE: accept multiplier like 1.2 or percent like 120
  local scale_pct
  if echo "$SCALE" | grep -q '\.'; then
    # multiplier -> percent
    scale_pct=$(awk -v s="$SCALE" 'BEGIN{printf "%.0f", s*100}')
  else
    scale_pct="$SCALE"
  fi

  # Create temporary files for intermediate steps
  local tmp_base tmp_scaled
  tmp_base=$(mktemp --suffix=.png)
  tmp_scaled=$(mktemp --suffix=.png)
  trap 'rm -f "$tmp_base" "$tmp_scaled"' RETURN

  # Initial resize to fill/fit depending on target shape
  if [ "$W" -gt "$H" ]; then
    convert "$in" -resize "x${H}" "$tmp_base"
  else
    convert "$in" -resize "${W}x${H}^" "$tmp_base"
  fi

  # Apply additional scale (around center)
  if [ "$scale_pct" -ne 100 ] 2>/dev/null; then
    convert "$tmp_base" -resize "${scale_pct}%" "$tmp_scaled"
  else
    mv "$tmp_base" "$tmp_scaled"
    : > "$tmp_base"
  fi

  # Composite scaled image onto background canvas with horizontal/vertical shift
  local offs
  offs=$(printf "%+d%+d" "$HSHIFT" "$VSHIFT")
  convert -size "${W}x${H}" canvas:"$bg" "$tmp_scaled" -gravity center -geometry "$offs" -composite "$out"
}

# App Banner: 320x180
generate "$INPUT" "$OUTDIR/banner_320x180.png" 320 180

# Launcher Icon: 108x108
generate "$INPUT" "$OUTDIR/launcher_108x108.png" 108 108

echo "Generated:
 - $OUTDIR/banner_320x180.png
 - $OUTDIR/launcher_108x108.png"
