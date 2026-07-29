#!/bin/bash
# Собирает ~/Applications/Jiggle.app из исходников в этой директории.
#
# Нужен, когда:
#   - поменял команду/настройки в jiggle-launcher.applescript
#   - переехал на новый ноут (там же: brew install cliclick + права Accessibility)
#
# osacompile каждый раз перезаписывает Resources, поэтому иконку ставим после
# компиляции, а подпись обновляем последней — иначе бандл будет считаться битым.

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Jiggle.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v osacompile >/dev/null || { echo "нет osacompile" >&2; exit 1; }

mkdir -p "$HOME/Applications"
rm -rf "$APP"
# osacompile всегда пишет в stderr "replacing existing signature" — это шум, но
# остальной stderr глушить нельзя, иначе реальная ошибка компиляции пройдёт молча.
osacompile -o "$APP" "$SRC/jiggle-launcher.applescript" 2>&1 \
    | grep -v "replacing existing signature" || true
echo "бандл собран: $APP"

# Кладём сам джигглер внутрь бандла: лаунчер ищет его относительно себя, поэтому
# приложение работает независимо от того, где лежат исходники.
cp "$SRC/jiggle.sh" "$APP/Contents/Resources/jiggle.sh"
chmod +x "$APP/Contents/Resources/jiggle.sh"
echo "jiggle.sh вложен в бандл"

# Иконка: icns требует размеры до 1024, поэтому режем iconset из исходного png.
mkdir -p "$TMP/Jiggle.iconset"
for pair in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    px=${pair% *}; name=${pair#* }
    sips -z "$px" "$px" "$SRC/jiggle-icon.png" --out "$TMP/Jiggle.iconset/${name}.png" >/dev/null 2>&1
done
iconutil -c icns "$TMP/Jiggle.iconset" -o "$TMP/icon.icns"
cp "$TMP/icon.icns" "$APP/Contents/Resources/applet.icns"
echo "иконка установлена"

codesign --force --deep -s - "$APP" >/dev/null 2>&1
touch "$APP"
echo "подписано (ad-hoc)"

echo ""
echo "Готово. Дальше вручную:"
echo "  1. перетащить $APP в Dock"
echo "  2. brew install cliclick"
echo "  3. System Settings → Privacy & Security → Accessibility → включить iTerm"
echo "  4. при первом запуске разрешить «Jiggle» управлять «iTerm»"
