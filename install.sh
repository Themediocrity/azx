#!/usr/bin/env bash
set -euo pipefail

##################################
#         НАСТРОЙКИ
##################################

APP_NAME="azx"
INSTALL_PATH="/bin"
USER_CONFIG_DIR="$HOME/.config/Themediocrity"
USER_CONFIG_FILE="$USER_CONFIG_DIR/${APP_NAME}.conf"
REQUIREMENTS_FILE="$(cd "$(dirname "$0")" && pwd)/requirements.txt"

##################################
#     АВТО-ОПРЕДЕЛЕНИЕ ПУТЕЙ
##################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_SRC="$SCRIPT_DIR/main.sh"
VERSION_FILE="$SCRIPT_DIR/version"

##################################
#          ФУНКЦИИ
##################################

generate_hash() {
    sha256sum "$1" | cut -d ' ' -f1
}

read_config() {
    [[ -s "$USER_CONFIG_FILE" ]] || return
    while IFS== read -r key val; do
        case "$key" in
            name) INSTALLED_NAME="$val" ;;
            path) INSTALLED_PATH="$val" ;;
            version) INSTALLED_VERSION="$val" ;;
            hash) INSTALLED_HASH="$val" ;;
        esac
    done < "$USER_CONFIG_FILE"
}

write_config() {
    cat > "$USER_CONFIG_FILE" <<EOF
name=$APP_NAME
path=$INSTALL_PATH
version=$CURRENT_VERSION
hash=$CURRENT_HASH
EOF
}

find_package_manager() {
    for pm in pacman apt dnf zypper xbps-install emerge; do
        if command -v $pm &>/dev/null; then
            echo "$pm"
            return
        fi
    done
    echo ""
}

install_dependency() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        pacman) sudo pacman -Sy --noconfirm "$pkg" ;;
        apt) sudo apt-get install -y "$pkg" ;;
        dnf) sudo dnf install -y "$pkg" ;;
        zypper) sudo zypper install -y "$pkg" ;;
        xbps-install) sudo xbps-install -Sy "$pkg" ;;
        emerge) sudo emerge "$pkg" ;;
        *) return 1 ;;
    esac
}

check_dependencies() {
    local missing=()
    while read -r entry; do
        for dep in $entry; do
            local cmd="${dep%%:*}"
            local pkg="${dep##*:}"
            if ! command -v "$cmd" &>/dev/null; then
                if ! install_dependency "$pkg"; then
                    missing+=("$pkg")
                fi
            fi
        done
    done < "$REQUIREMENTS_FILE"

    if [[ ${#missing[@]} -ne 0 ]]; then
        echo "⛔ Не удалось установить следующие зависимости:"
        printf ' - %s\n' "${missing[@]}"
        echo "Установите их вручную и повторите установку."
        exit 1
    fi
}

##################################
#         УСТАНОВКА
##################################

PKG_MANAGER="$(find_package_manager)"
if [[ -z "$PKG_MANAGER" ]]; then
    echo "⛔ Не удалось определить пакетный менеджер. Установите зависимости вручную."
    exit 1
fi

check_dependencies

mkdir -p "$USER_CONFIG_DIR"
touch "$USER_CONFIG_FILE"

CURRENT_VERSION="$(< "$VERSION_FILE" tr -d '\n')"
CURRENT_HASH="$(generate_hash "$SCRIPT_SRC")"

INSTALLED_NAME=""
INSTALLED_PATH=""
INSTALLED_VERSION=""
INSTALLED_HASH=""
read_config

if [[ "$CURRENT_VERSION" == "$INSTALLED_VERSION" && "$CURRENT_HASH" == "$INSTALLED_HASH" ]]; then
    echo "Идентичная версия уже установлена: $APP_NAME v$INSTALLED_VERSION"
    exit 0
fi

if [[ -n "$INSTALLED_VERSION" ]]; then
    if [[ "$CURRENT_VERSION" > "$INSTALLED_VERSION" ]]; then
        echo "Обновление: $INSTALLED_VERSION → $CURRENT_VERSION"
    elif [[ "$CURRENT_VERSION" < "$INSTALLED_VERSION" ]]; then
        echo "Откат версии: $INSTALLED_VERSION → $CURRENT_VERSION"
        read -rp "Вы уверены? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    else
        echo "Изменённый скрипт той же версии будет обновлён"
    fi
else
    echo "Установка новой версии: $CURRENT_VERSION"
fi

# Установка
sudo cp "$SCRIPT_SRC" "$INSTALL_PATH/$APP_NAME"
sudo chmod +x "$INSTALL_PATH/$APP_NAME"
write_config

echo "✅ Установлено: $APP_NAME v$CURRENT_VERSION → $INSTALL_PATH/$APP_NAME"
