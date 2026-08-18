#!/bin/bash
# Создаёт локальную подпись для Jiggle.app — самоподписанный сертификат в
# связке ключей. Один раз на машину, повторный запуск ничего не делает.
#
# Зачем это нужно
# ---------------
# Без сертификата build-app.sh подписывает бандл ad-hoc (codesign -s -), и
# designated requirement получается такой:
#
#     designated => cdhash H"fe68ba64..."
#
# То есть привязка к хешу конкретного бинаря. Разрешение в Accessibility
# привязывается к этому же требованию, поэтому любая пересборка делает его
# недействительным — и молча: галочка в System Settings остаётся, приложение
# считает шевеления, курсор стоит. Ошибки нигде нет, CGEvent.post просто
# ничего не делает. У Homebrew из-за этой же механики есть отдельный caveat
# для unsigned-формул, которым нужен Accessibility (yabai, skhd).
#
# С сертификатом требование становится другим:
#
#     designated => identifier com.gorokhovdenis.jiggle
#                   and certificate root = H"ae47fa81..."
#
# Привязка к идентификатору и сертификату, а не к содержимому бинаря.
# Разрешение выдаётся один раз и переживает любое число пересборок.
#
# Чего этот сертификат НЕ делает
# ------------------------------
# Он не помогает раздавать приложение. Самоподписанный сертификат доверен
# только на той машине, где создан; на чужом маке подпись от недоверенного
# корня не лучше ad-hoc, а формально хуже — Gatekeeper считает её невалидной,
# тогда как ad-hoc просто пропускает. Поэтому на второй машине сертификат
# создаётся свой, локально, этим же скриптом. Раздача приложения — отдельная
# тема, см. README.
#
# Доверие сертификату сознательно не выставляется: codesign подписывает и
# недоверенным (CSSMERR_TP_NOT_TRUSTED ему не мешает), а TCC смотрит на
# designated requirement, а не на цепочку доверия. Локально собранный бандл
# карантина не получает, так что Gatekeeper в эту историю не вмешивается.
# Без add-trusted-cert скрипт обходится без диалога авторизации.
#
# Приватный ключ остаётся в связке ключей, на диск не выкладывается, доступ к
# нему разрешён только codesign. Потерялся — запустите скрипт заново и
# переоформите разрешение в Accessibility.

set -eu

CN="Jiggle Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# LibreSSL из системы, а не Homebrew: на чужой машине openssl из brew может и
# не оказаться, а /usr/bin/openssl есть везде и -addext умеет с 3.3.
OPENSSL=/usr/bin/openssl

[ "$(uname -s)" = "Darwin" ] || { echo "Это только для macOS." >&2; exit 1; }

# Без -v: сертификат самоподписанный и в «valid identities only» не попадает
# никогда, хотя подписывать им можно.
have_identity() {
    security find-identity -p codesigning 2>/dev/null | grep -qF "$CN"
}

if have_identity; then
    echo "Подпись «$CN» уже есть — делать нечего."
    echo "Собрать приложение: ./build-app.sh"
    exit 0
fi

TMP="$(mktemp -d)"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

# --- Ключ и сертификат --------------------------------------------------------
# extendedKeyUsage=codeSigning обязателен: без него codesign сертификат не
# признаёт вообще.
echo "[1/3] генерирую ключ и сертификат..."
"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$CN/O=Jiggle" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Пароль случайный и одноразовый: контейнер живёт секунду в mktemp -d 700 и
# удаляется по trap. Пустой пароль не годится — security import отвечает на него
# «The user name or passphrase you entered is not correct».
PW="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 24)"

"$OPENSSL" pkcs12 -export -out "$TMP/id.p12" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$CN" -passout "pass:$PW" 2>/dev/null

# --- В связку ключей ----------------------------------------------------------
# -T /usr/bin/codesign — доступ к ключу только у codesign, не у всего подряд.
echo "[2/3] кладу в связку ключей..."
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PW" -T /usr/bin/codesign \
    -f pkcs12 >/dev/null

# --- Проверка -----------------------------------------------------------------
# Не «сертификат появился в списке», а «им действительно можно подписать»:
# заодно проверяется, что codesign достаёт приватный ключ без диалога.
echo "[3/3] проверяю подписью..."
cp /usr/bin/true "$TMP/probe"

if ! codesign --force -s "$CN" "$TMP/probe" >/dev/null 2>&1; then
    echo "" >&2
    echo "Сертификат создан, но подписать им не получилось." >&2
    echo "Посмотрите вручную: codesign --force -s \"$CN\" /tmp/что-нибудь" >&2
    exit 1
fi

REQ="$(codesign -d -r- "$TMP/probe" 2>&1 | grep '^designated' || true)"
case "$REQ" in
    *"certificate root"*)
        echo ""
        echo "Готово. Требование к подписи теперь такое:"
        echo "  $REQ"
        echo ""
        echo "Дальше: ./build-app.sh — подпись подхватится сама."
        ;;
    *)
        echo "" >&2
        echo "Подписалось, но требование вышло не то, что нужно:" >&2
        echo "  ${REQ:-(пусто)}" >&2
        echo "Ожидалось «certificate root». Разрешение Accessibility будет" >&2
        echo "слетать при пересборке." >&2
        exit 1
        ;;
esac
