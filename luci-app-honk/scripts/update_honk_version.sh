#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAKEFILE="$REPO_DIR/honk/Makefile"
UPSTREAM_REPO="daeuniverse/honk"

git_ls_remote() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if git ls-remote --tags "https://github.com/${UPSTREAM_REPO}.git" 2>/dev/null; then
            return 0
        fi
        sleep 3
    done
    return 1
}

calc_sha256() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        echo "error: neither sha256sum nor shasum is installed" >&2
        return 1
    fi
}

derive_version() {
    local tag="$1"
    local v="${tag#[vV]}"
    local prefix rest stage stage_num patch_num
    stage=""
    stage_num=""
    patch_num=""

    # 1. 提取主版本号
    prefix="$(printf '%s' "$v" | sed -E 's/^([0-9]+(\.[0-9]+)*).*/\1/')"
    [ -n "$prefix" ] || prefix="0.0.0"

    # 2. 剥离已提取部分及连接符
    rest="${v#"$prefix"}"
    rest="$(printf '%s' "$rest" | sed -E 's/^[-_.]+//')"

    if [ -n "$rest" ]; then
        # 统一小写
        rest="$(printf '%s' "$rest" | tr '[:upper:]' '[:lower:]')"

        # 3. 提取阶段性标签 (alpha/beta/rc 等)
        if printf '%s' "$rest" | grep -qE '^(alpha|beta|pre|rc|cvs|git|hg|svn)'; then
            stage="$(printf '%s' "$rest" | sed -E -n 's/^(alpha|beta|pre|rc|cvs|git|hg|svn).*/\1/p')"
            rest="$(printf '%s' "$rest" | sed -E 's/^(alpha|beta|pre|rc|cvs|git|hg|svn)//' | sed -E 's/^[-_.]+//')"

            stage_num="$(printf '%s' "$rest" | sed -E -n 's/^([0-9]+).*/\1/p')"
            if [ -n "$stage_num" ]; then
                rest="${rest#"$stage_num"}"
                rest="$(printf '%s' "$rest" | sed -E 's/^[-_.]+//')"
            fi
        fi

        # 4. 提取补丁标签 (抹除所有分隔符，将 fix.fix 压扁为 fixfix)
        if [ -n "$rest" ]; then
            rest="$(printf '%s' "$rest" | sed -E 's/[-_.]//g')"
            if printf '%s' "$rest" | grep -qE '^(fix)+$'; then
                local orig_len="${#rest}"
                local stripped_rest="${rest//fix/}"
                patch_num=$(( (orig_len - ${#stripped_rest}) / 3 ))
            elif printf '%s' "$rest" | grep -qE '^(fix|patch|hotfix|p)[0-9]+'; then
                patch_num="$(printf '%s' "$rest" | sed -E -n 's/^(fix|patch|hotfix|p)([0-9]+).*/\2/p')"
            elif printf '%s' "$rest" | grep -qE '^(fix|patch|hotfix|p)$'; then
                patch_num="1"
            fi
        fi
    fi

    # 5. 组装合规版本号
    local result="$prefix"
    [ -z "$stage" ] || result="${result}_${stage}${stage_num}"
    [ -z "$patch_num" ] || result="${result}_p${patch_num}"
    
    printf '%s\n' "$result"
}

assert_apk_version() {
    local v="$1"

    if command -v apk >/dev/null 2>&1; then
        apk version -c "$v" >/dev/null 2>&1 && return 0 || return 1
    fi

    local apk_regex="^[0-9]+(\.[0-9]+)*[a-z]?(_(alpha|beta|pre|rc|cvs|svn|git|hg|p)[0-9]*)*$"
    printf '%s' "$v" | grep -qE "$apk_regex"
}

resolve_tag() {
    if [ -n "${HONK_RELEASE_TAG:-}" ]; then
        printf '%s\n' "$HONK_RELEASE_TAG"
        return 0
    fi

    local json="${HONK_RELEASE_JSON:-}"
    if [ -z "$json" ]; then
        json="$(curl -fsSL --retry 3 --connect-timeout 15 \
            "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" 2>/dev/null || true)"
    fi

    if [ -n "$json" ]; then
        local tag
        tag="$(printf '%s' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
        if [ -n "$tag" ]; then
            printf '%s\n' "$tag"
            return 0
        fi
    fi

    git_ls_remote | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}' | sort -V | tail -n 1
}

resolve_hash() {
    local var_name="$1"
    local target="$2"
    local suffix="$3"
    local tag="$4"
    local asset="honk-core-${tag}-${target}${suffix}.tar.gz"

    if [ -n "${!var_name:-}" ]; then
        printf '%s\n' "${!var_name}"
        return 0
    fi

    local tmp hash
    tmp="$(mktemp)"
    if ! curl -fsSL --retry 3 --connect-timeout 20 \
        "https://github.com/daeuniverse/honk/releases/download/${tag}/${asset}" -o "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "error: unable to download ${asset}" >&2
        return 1
    fi

    if ! hash="$(calc_sha256 "$tmp")"; then
        rm -f "$tmp"
        echo "error: unable to hash ${asset}" >&2
        return 1
    fi
    rm -f "$tmp"

    printf '%s\n' "$hash"
}

main() {
    local tag version suffix hash_x86_64 hash_aarch64
    tag="$(resolve_tag)"
    [ -n "$tag" ] || { echo "error: unable to resolve honk release tag" >&2; exit 1; }
    
    version="$(derive_version "$tag")"

    if ! assert_apk_version "$version"; then
        echo "WARNING: Parsed version '${version}' is invalid for apk-tools!" >&2
        # Fallback：仅提取纯数字基准版本号 (剥离不可靠后缀)
        version="$(printf '%s' "${tag#[vV]}" | sed -E 's/^([0-9]+(\.[0-9]+)*).*/\1/')"
        [ -n "$version" ] || version="0.0.0"
        echo "INFO: Falling back to strict safe PKG_VERSION='${version}'" >&2
    else
        echo "INFO: Validated PKG_VERSION='${version}'" >&2
    fi

    suffix="$(grep '^HONK_SUFFIX:=' "$MAKEFILE" | head -n 1 | cut -d= -f2- || true)"

    hash_x86_64="$(resolve_hash HONK_HASH_X86_64 "x86_64-unknown-linux-musl" "$suffix" "$tag")"
    hash_aarch64="$(resolve_hash HONK_HASH_AARCH64 "aarch64-unknown-linux-musl" "$suffix" "$tag")"

    # Stream substitution compatible across Linux and macOS/BSD
    sed -E \
        -e "s/^PKG_VERSION:=.*/PKG_VERSION:=${version}/" \
        -e "s/^HONK_RELEASE_TAG:=.*/HONK_RELEASE_TAG:=${tag}/" \
        -e "s/^HONK_HASH_X86_64:=.*/HONK_HASH_X86_64:=${hash_x86_64}/" \
        -e "s/^HONK_HASH_AARCH64:=.*/HONK_HASH_AARCH64:=${hash_aarch64}/" \
        "$MAKEFILE" > "${MAKEFILE}.tmp"
    
    mv "${MAKEFILE}.tmp" "$MAKEFILE"

    echo "==================================="
    echo "honk updated to ${tag} (PKG_VERSION=${version})"
    echo "HONK_HASH_X86_64=${hash_x86_64}"
    echo "HONK_HASH_AARCH64=${hash_aarch64}"
}

main "$@"
