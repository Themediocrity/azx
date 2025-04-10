#!/usr/bin/env bash

# По умолчанию
list_contents=0
depth=1
output_dir=""
args=()

# Обработка флагов: -l [depth], -p [output_dir]
while [[ $# -gt 0 ]]; do
    case "$1" in
        -l)
            list_contents=1
            shift
            # если следующий аргумент — число, это глубина
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                depth=$1
                shift
            fi
            ;;
        -p)
            shift
            output_dir="$1"
            shift
            ;;
        *)  args+=("$1"); shift ;;
    esac
done
set -- "${args[@]}"

if [ ${#args[@]} -eq 0 ]; then
    echo "Usage: $0 [-l [depth]] [-p output_dir] file1 [file2 ...]"
    exit 1
fi

# Проверка наличия каталога для распаковки
if [ -n "$output_dir" ] && [ ! -d "$output_dir" ]; then
    echo -e "\e[31mDirectory $output_dir does not exist.\e[0m"
    exit 1
fi

# Определяем расширение
get_extension() {
    local fn=$(basename "$1")
    case "$fn" in
        *.tar.gz)  echo "tar.gz" ;;
        *.tar.bz2) echo "tar.bz2" ;;
        *.tar.xz)  echo "tar.xz" ;;
        *.tar.zst) echo "tar.zst" ;;
        *.tgz)     echo "tgz" ;;
        *.tbz2)    echo "tbz2" ;;
        *.txz)     echo "txz" ;;
        *.tar)     echo "tar" ;;
        *)         echo "${fn##*.}" ;;
    esac
}

# Список всех путей внутри архива
get_contents() {
    local file="$1"; local ext; ext=$(get_extension "$file")
    case "$ext" in
        7z)
            7z l -slt "$file" \
              | grep '^Path = ' \
              | sed 's|^Path = ||'
            ;;
        zip)
            unzip -l "$file" \
              | tail -n +4 | head -n -2 \
              | awk '{print $4}'
            ;;
        rar)
            unrar l "$file" \
              | sed '1,/--------/d; /--------/,$d' \
              | awk '{print $NF}'
            ;;
        tar*|tgz|tbz2|txz)
            tar tf "$file"
            ;;
        *)
            echo "Unknown format: $ext" >&2
            return 1
            ;;
    esac
}

# Функция создания списка файлов
generate_list() {
    local file="$1"; local d="$2"
    local fname=$(basename "$file")
    local raw entries list

    # Получаем содержимое и обрезаем по нужной глубине
    raw=$(get_contents "$file" | cut -d/ -f1-"$d")
    
    # Получаем уникальные элементы
    entries=$(printf "%s\n" "$raw" \
              | sort -u \
              | grep -v -x '\.' \
              | grep -v -x "$fname" \
              | grep -v -x '' )

    if [ -z "$entries" ]; then
        echo -e "\e[33m$fname:\e[0m (no entries)"
    else
        # Формируем вывод с отступами
        list=$(printf "%s\n" "$entries" | sed 's|^\./||' | sed 's|^|│   ├──|')

        # Выводим только имя архива
        echo -e "\e[33m$fname:\e[0m"
        
        # Папки и файлы с вложенностью
        echo -e "$list"
    fi
}

# Распаковка (без учёта depth)
process_file() {
    local file="$1"
    local ext; ext=$(get_extension "$file")
    local fname=$(basename "$file")
    local base="${file%.*}"
    local raw filtered count target_dir

    # Если путь для распаковки не указан, используем текущий каталог
    if [ -n "$output_dir" ]; then
        target_dir="$output_dir"
    else
        target_dir="."
    fi

    raw=$(get_contents "$file" | cut -d/ -f1)
    filtered=$(printf "%s\n" "$raw" \
               | sort -u \
               | grep -v -x '\.' \
               | grep -v -x "$fname")
    count=$(printf "%s\n" "$filtered" | wc -l)

    if [ "$count" -gt 1 ]; then
        mkdir -p "$target_dir" || { echo -e "\e[31mFailed to create directory $target_dir\e[0m"; return 1; }
    fi

    case "$ext" in
        7z)      7z x -o"$target_dir" "$file" ;;
        zip)     unzip "$file" -d "$target_dir" ;;
        rar)     unrar x "$file" "$target_dir/" ;;
        tar)     tar xf "$file" -C "$target_dir" ;;
        tar.gz|tgz)   tar xzf "$file" -C "$target_dir" ;;
        tar.bz2|tbz2) tar xjf "$file" -C "$target_dir" ;;
        tar.xz|txz)   tar xJf "$file" -C "$target_dir" ;;
        tar.zst)      tar --zstd -xf "$file" -C "$target_dir" ;;
        *)
            echo -e "\e[31mUnknown format: $ext\e[0m"
            return 1
            ;;
    esac
}

# Основной цикл
exit_code=0
for file in "$@"; do
    [ ! -f "$file" ] && continue
    ext=$(get_extension "$file")
    case "$ext" in
        7z|zip|rar|tar|tar.gz|tgz|tar.bz2|tbz2|tar.xz|txz|tar.zst) ;;
        *)  continue ;;
    esac

    if [ "$list_contents" -eq 1 ]; then
        generate_list "$file" "$depth"
    else
        echo -e "\e[32mExtracting $(basename "$file")...\e[0m"
        if process_file "$file"; then
            echo -e "\e[32mSuccessfully extracted $(basename "$file")\e[0m"
        else
            echo -e "\e[31mFailed to extract $(basename "$file")\e[0m"
            exit_code=1
        fi
    fi
done

# Завершаем скрипт с соответствующим кодом выхода
if [ "$exit_code" -eq 0 ]; then
    echo -e "\e[32mAll operations completed successfully.\e[0m"
else
    echo -e "\e[31mSome operations failed.\e[0m"
fi

exit $exit_code
