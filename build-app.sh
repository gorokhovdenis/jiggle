#!/bin/bash
# Собирает Jiggle.app — menu bar приложение — из исходников в app/.
#
# Зависимости: только Xcode Command Line Tools (swiftc). Ни Homebrew,
# ни cliclick тут не нужны: события мыши шлются напрямую через CGEvent.
#
# Сборка идёт на машине пользователя, поэтому бандл не получает атрибут
# карантина и Gatekeeper к нему претензий не имеет.

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
# /Applications, а не ~/Applications: Finder в сайдбаре показывает только
# общесистемную папку, и приложение в домашней выглядит «не установленным».
# Плюс dmg кладёт именно туда — одна копия, одно место на всех машинах.
APP="${JIGGLE_APP_PATH:-/Applications/Jiggle.app}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v swiftc >/dev/null || {
    echo "Нет swiftc. Поставь Command Line Tools: xcode-select --install" >&2
    exit 1
}

echo "компилирую..."
# Явный deployment target обязателен: без него swiftc молча берёт версию
# хост-системы, и бинарь, собранный на macOS 26, не запускается на более
# старых — при том что Info.plist обещает 13.0. Только arm64: Intel
# сознательно не поддерживаем (отмечено в README).
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
    "$SRC/app/Log.swift" "$SRC/app/Jiggler.swift" "$SRC/app/main.swift" \
    -o "$TMP/Jiggle"

# --- Каркас бандла ------------------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TMP/Jiggle" "$APP/Contents/MacOS/Jiggle"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Jiggle</string>
	<key>CFBundleDisplayName</key>
	<string>Jiggle</string>
	<key>CFBundleExecutable</key>
	<string>Jiggle</string>
	<key>CFBundleIdentifier</key>
	<string>com.gorokhovdenis.jiggle</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>4</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHumanReadableCopyright</key>
	<string>MIT</string>
</dict>
</plist>
PLIST

# --- Иконка -------------------------------------------------------------------
# icns принимает размеры до 1024, поэтому режем iconset из исходного png.
if [ -f "$SRC/jiggle-icon.png" ]; then
    mkdir -p "$TMP/AppIcon.iconset"
    for pair in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
                "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
        px=${pair% *}; name=${pair#* }
        sips -z "$px" "$px" "$SRC/jiggle-icon.png" --out "$TMP/AppIcon.iconset/${name}.png" >/dev/null 2>&1
    done
    iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# --- Подпись ------------------------------------------------------------------
# Локальный самоподписанный сертификат, если он есть, иначе ad-hoc.
#
# Разница принципиальная, а не косметическая. У ad-hoc подписи нет постоянной
# идентичности: macOS опознаёт такой бандл по cdhash — хешу бинаря. Разрешение
# в Accessibility привязано к этому хешу и слетает при каждой пересборке, причём
# молча: галочка в настройках остаётся, приложение считает шевеления,
# курсор стоит. С сертификатом идентичность задаёт сертификат, и разрешение
# выдаётся один раз навсегда.
IDENTITY="Jiggle Local Signing"

# Без -v: самоподписанный сертификат в «valid identities only» не попадает
# никогда (CSSMERR_TP_NOT_TRUSTED), хотя подписывать им можно — codesign
# цепочку доверия не требует, а TCC смотрит на designated requirement.
if security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    codesign --force -s "$IDENTITY" "$APP" >/dev/null
    echo "подписано: $IDENTITY"
else
    codesign --force -s - "$APP" >/dev/null 2>&1
    echo "подписано ad-hoc — постоянной идентичности нет."
    echo "Разрешение в Accessibility будет слетать при каждой пересборке."
    echo "Один раз запустите ./make-cert.sh, и это перестанет повторяться."
fi
touch "$APP"

echo "готово: $APP"
echo ""
echo "Запуск:   open \"$APP\""
echo "Иконка появится и в строке меню, и в доке."
echo ""
echo "При первом запуске macOS попросит Accessibility — без него курсор"
echo "двигаться не будет. Приложение спросит само и откроет нужную панель."
