#!/usr/bin/env bash

set -euo pipefail

FILE="./nginx/api_keys.map"
DELETED_FILE="./nginx/api_keys.deleted"

mkdir -p "$(dirname "$FILE")"

# Ensure files exist
touch "$FILE"
touch "$DELETED_FILE"

usage() {
    echo "Usage:"
    echo "  $0 add <name> <hex> <comment>"
    echo "  $0 del <line_number>"
    echo "  $0 list"
    exit 1
}

validate_name() {
    [[ "$1" =~ ^[a-zA-Z0-9-]{1,9}$ ]]
}

add_key() {
    local name="$1"
    local comment="${2:-}"

    if ! validate_name "$name"; then
        echo "❌ Invalid name. Must be <=9 chars, only letters/numbers/dash."
        exit 1
    fi

    local key="${name}-$(openssl rand 22 -hex)"

    # prevent duplicates
    if grep -q "^${key} " "$FILE"; then
        echo "❌ Key already exists"
        exit 1
    fi

    echo "${key} 1; # ${comment}" >> "$FILE"

    echo "✅ Added key:"
    echo "${key}"
}

delete_key() {
    local line="$1"

    if ! [[ "$line" =~ ^[0-9]+$ ]]; then
        echo "❌ Line number must be numeric"
        exit 1
    fi

    if [[ ! -s "$FILE" ]]; then
        echo "❌ File is empty"
        exit 1
    fi

    local total
    total=$(wc -l < "$FILE")

    if (( line < 1 || line > total )); then
        echo "❌ Invalid line number (1-$total)"
        exit 1
    fi

    local entry
    entry=$(sed -n "${line}p" "$FILE")

    # append to deleted file with timestamp
    # echo "# deleted $(date -Is)" >> "$DELETED_FILE"
    echo "$entry" >> "$DELETED_FILE"

    # remove line
    # sed -i "${line}d" "$FILE"
    sed -i '' "${line}d" "$FILE"

    echo "🗑️ Deleted line $line"
    echo "$entry"
}

list_keys() {
    if [[ ! -s "$FILE" ]]; then
        echo "⚠️ No keys found"
        exit 0
    fi

    echo "📋 API Keys:"
    echo "----------------------------------------"

    # custom numbered clean output
    local i=1
    while IFS= read -r line; do
        echo "$i) $line"
        ((i++))
    done < "$FILE"

    echo "----------------------------------------"
    echo "Total: $(wc -l < "$FILE")"
}

case "${1:-}" in
    add)
        [[ $# -lt 3 ]] && usage
        add_key "$2" "$3"
        ;;
    del)
        [[ $# -lt 2 ]] && usage
        delete_key "$2"
        ;;
    list)
        list_keys
        ;;
    *)
        usage
        ;;
esac
