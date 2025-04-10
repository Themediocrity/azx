#!/bin/bash

# Обработка флагов
list_contents=0
args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l) list_contents=1; shift ;;
        *)  args+=("$1"); shift ;;
    esac
done
set -- "${args[@]}"

if [ $# -eq 0 ]; then
    echo "Usage: $0 [-l] file [file2 ...]"
    exit 1
fi

# Функция определения расширения
get_extension() {
    local filename=$(basename "$1")
    case "$filename" in
        *.tar.gz)    echo "tar.gz" ;;
        *.tar.bz2)   echo "tar.bz2" ;;
        *.tar.xz)    echo "tar.xz" ;;
        *.tar.zst)   echo "tar.zst" ;;
        *.tgz)       echo "tgz" ;;
        *.tbz2)      echo "tbz2" ;;
        *.txz)       echo "txz" ;;
        *.tar)       echo "tar" ;;
        *)           echo "${filename##*.}" ;;
    esac
}

# Функция получения содержимого архива
get_contents() {
    local file="$1"
    case $(get_extension "$file") in
        7z)      7z l -slt "$file" | grep 'Path = ' | sed 's/^Path = //' ;;
        zip)     unzip -l "$file" | tail -n +4 | head -n -2 | awk '{print $4}' ;;
        rar)     unrar l "$file" | sed '1,/--------/d; /--------/,$d' | awk '{print $1}' ;;
        tar*)    tar tf "$file" ;;
        *)       echo "Unknown format: $(get_extension "$file")"; return 1 ;;
    esac
}

# Функция создания списка файлов
generate_list() {
    local file="$1"
    local list_file="${file%.*.*}_contents.txt"
    if contents=$(get_contents "$file"); then
        echo "$contents" > "$list_file"
        micro "$list_file"
    else
        echo -e "\e[31mFailed to generate list for $file\e[0m"
    fi
}

# Функция распаковки
process_file() {
    local file="$1"
    local filename=$(basename "$file")
    local extension=$(get_extension "$file")
    local base="${file%.*}"
    
    # Получаем количество элементов верхнего уровня
    local count=$(get_contents "$file" | cut -d '/' -f 1 | sort -u | wc -l)
    
    # Создаем папку при необходимости
    if [ "$count" -gt 1 ]; then
        mkdir -p "$base" || { echo -e "\e[31mFailed to create directory $base\e[0m"; return 1; }
        local target_dir="$base"
    else
        local target_dir="."
    fi

    # Распаковка
    case "$extension" in
        7z)      7z x -o"$target_dir" "$file" ;;
        zip)     unzip "$file" -d "$target_dir" ;;
        rar)     unrar x "$file" "$target_dir/" ;;
        tar)     tar xf "$file" -C "$target_dir" ;;
        tar.gz|tgz)   tar xzf "$file" -C "$target_dir" ;;
        tar.bz2|tbz2) tar xjf "$file" -C "$target_dir" ;;
        tar.xz|txz)   tar xJf "$file" -C "$target_dir" ;;
        tar.zst)      tar --zstd -xf "$file" -C "$target_dir" ;;
        *)        echo -e "\e[31mUnknown format: $extension\e[0m"; return 1 ;;
    esac
}

# Основной цикл
for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo -e "\e[31mFile not found: $file\e[0m"
        continue
    fi
    
    # Генерация списка
    if [ $list_contents -eq 1 ]; then
        generate_list "$file"
    fi
    
    # Распаковка
    echo -e "\e[32mExtracting $file...\e[0m"
    if process_file "$file"; then
        echo -e "\e[32mSuccessfully extracted $file\e[0m"
    else
        echo -e "\e[31mFailed to extract $file\e[0m"
    fi
done
