#!/bin/sh

# 任务层只登记、执行和保留结果；业务日志由对应模块记录。
. /usr/lib/hijpass/common.sh
root=$HIJPASS_JOB_ROOT
action=${1:-}
id=${2:-}
umask 077
mkdir -p "$root" && chmod 700 "$root" || exit 1

valid_id() {
    case "$1" in ''|*[!A-Za-z0-9]*) return 1 ;; esac
    [ "${#1}" -eq 8 ]
}

recover_job() {
    local directory="$1" pid
    [ ! -f "$directory/exit" ] || return 0
    pid=$(cat "$directory/pid" 2>/dev/null)
    case "$pid" in ''|*[!0-9]*) pid=0 ;; esac
    if [ "$pid" -eq 0 ] || ! kill -0 "$pid" 2>/dev/null ||
        ! tr '\000' '\n' 2>/dev/null <"/proc/$pid/cmdline" | grep -Fqx -- "$HIJPASS_LIB/rpc/jobs.sh"; then
        # 存活检查期间 worker 可能刚写入结果并退出，不能覆盖它的真实结果。
        [ ! -f "$directory/exit" ] || return 0
        hijpass_log ERROR "$(cat "$directory/kind" 2>/dev/null): worker exited without a result"
        printf 'job exited without a result\n' >>"$directory/stderr"
        printf '1\n' >"$directory/exit.tmp"
        mv "$directory/exit.tmp" "$directory/exit"
    fi
}

active_job() {
    local kind="$1" active directory
    active=$(cat "$root/$kind.active" 2>/dev/null) || return 1
    valid_id "$active" || return 1
    directory="$root/$active"
    [ -d "$directory" ] && [ ! -L "$directory" ] || return 1
    [ "$(cat "$directory/kind" 2>/dev/null)" = "$kind" ] || return 1
    recover_job "$directory"
    [ ! -f "$directory/exit" ] || return 1
    printf '%s\n' "$active"
}

execute_job() {
    local kind="$1" directory="$2" code started
    shift 2
    started=$(date +%s)
    hijpass_log DEBUG "$kind task started"
    case "$kind" in
        rules) HIJPASS_JOB_DIRECTORY="$directory" "$HIJPASS_LIB/rules/update-files.sh" "$@" ;;
        restart) /etc/init.d/hijpass restart ;;
        xray|sing-box) HIJPASS_JOB_DIRECTORY="$directory" "$HIJPASS_LIB/core/update.sh" update "$kind" ;;
        *) return 1 ;;
    esac >"$directory/stdout" 2>"$directory/stderr"
    code=$?
    if [ "$code" -ne 0 ] && [ ! -s "$directory/stdout" ] && [ "$kind" != restart ]; then
        hijpass_log ERROR "$kind task exited without a business result; exit=$code"
    fi
    hijpass_log DEBUG "$kind task finished: exit=$code, elapsed=$(($(date +%s) - started))s"
    printf '%s\n' "$code" >"$directory/exit.tmp"
    mv "$directory/exit.tmp" "$directory/exit"
    return "$code"
}

case "$action" in
    start|run)
        case "$id" in rules|restart|xray|sing-box) ;; *) hijpass_json_error 'unknown job'; exit 1 ;; esac
        if [ "$action" = start ]; then exec "$0" claim "$id" async 0; fi
        [ "$id" = rules ] || { hijpass_json_error 'unsupported inline job'; exit 1; }
        shift 2
        if registration=$("$0" claim rules inline "$$" "${1:-update}"); then
            json_load "$registration" || exit 1
            json_get_var task_id id
        else
            printf '%s\n' "$registration"
            exit 75
        fi
        execute_job rules "$root/$task_id" "$@"
        code=$?
        cat "$root/$task_id/stdout"
        cat "$root/$task_id/stderr" >&2
        exit "$code" ;;
    claim)
        mode=${3:-} owner=${4:-} scope=${5:-update}
        case "$id:$mode" in rules:inline|rules:async|restart:async|xray:async|sing-box:async) ;;
            *) hijpass_json_error 'invalid job registration'; exit 1 ;;
        esac
        # 检查活动任务与发布新 ID 在同一短临界区内，避免检查后再创建的竞态。
        exec 8>"$root/registry.lock"
        flock -x 8 || exit 1
        if [ "$id" != restart ] && active=$(active_job "$id"); then
            if [ "$mode" = inline ] || { [ "$id" = rules ] && [ "$(cat "$root/$active/scope" 2>/dev/null)" != "$scope" ]; }; then
                # 部分资源更新不能冒充“更新全部”的成功结果；只报告忙，不排队。
                if [ "$mode" = async ]; then
                    json_init; json_add_string id "$active"; json_add_boolean success 0
                    json_add_string code UPDATE_BUSY; json_dump
                    exit 0
                fi
                hijpass_run_ucode "$HIJPASS_LIB/rules/rulescli.uc" busy
                exit 75
            fi
            json_init; json_add_string id "$active"; json_dump
            exit 0
        fi
        for expired in "$root"/*; do
            [ -d "$expired" ] && valid_id "${expired##*/}" || continue
            recover_job "$expired"
            [ -f "$expired/exit" ] || continue
            find "$expired" -maxdepth 0 -mmin +60 -exec rm -rf -- '{}' ';'
        done
        directory=$(mktemp -d "$root/XXXXXXXX") || exit 1
        : >"$directory/stdout"
        : >"$directory/stderr"
        printf '%s\n' "$id" >"$directory/kind"
        printf '%s\n' "$scope" >"$directory/scope"
        if [ "$id" != restart ]; then
            printf '%s\n' "${directory##*/}" >"$root/$id.active.new.$$"
            mv "$root/$id.active.new.$$" "$root/$id.active" || exit 1
        fi
        if [ "$mode" = inline ]; then
            printf '%s\n' "$owner" >"$directory/pid"
        elif ! (
            for descriptor in /proc/self/fd/*; do
                descriptor=${descriptor##*/}
                case "$descriptor" in 0|1|2|*[!0-9]*) continue ;; esac
                eval "exec $descriptor>&-"
            done
            exec start-stop-daemon -S -b -m -p "$directory/pid" -x "$HIJPASS_LIB/rpc/jobs.sh" -- worker "$id" "$directory"
        ); then
            rm -rf -- "$directory"
            [ "$id" = restart ] || rm -f "$root/$id.active"
            hijpass_json_error 'cannot start job'
            exit 1
        fi
        json_init; json_add_string id "${directory##*/}"; json_dump ;;
    worker)
        directory=$3
        trap '' HUP
        if [ "$id" = rules ]; then execute_job "$id" "$directory" update
        else execute_job "$id" "$directory"; fi
        exit $? ;;
    current)
        case "$id" in rules|xray|sing-box) ;; *) hijpass_json_error 'unknown job'; exit 1 ;; esac
        exec 8>"$root/registry.lock"
        flock -x 8 || exit 1
        json_init
        if active=$(active_job "$id"); then json_add_string id "$active"; else json_add_null id; fi
        json_dump ;;
    clear)
        # init 持有更新锁。只清理已结束任务，保留触发重启的调用者收尾所需目录。
        exec 8>"$root/registry.lock"
        flock -x 8 || exit 1
        for directory in "$root"/*; do
            [ -d "$directory" ] && valid_id "${directory##*/}" || continue
            recover_job "$directory"
            [ ! -f "$directory/exit" ] || rm -rf -- "$directory"
        done
        for kind in rules xray sing-box; do
            active_job "$kind" >/dev/null || rm -f "$root/$kind.active"
        done
        rm -rf "$root/work" ;;
    status)
        valid_id "$id" || { hijpass_json_error 'invalid job ID'; exit 1; }
        directory="$root/$id"
        [ -d "$directory" ] && [ ! -L "$directory" ] || { hijpass_json_error 'job not found'; exit 1; }
        exec 8>"$root/registry.lock"
        flock -x 8 || exit 1
        recover_job "$directory"
        flock -u 8
        exec 8>&-
        hijpass_run_ucode "$HIJPASS_LIB/result.uc" job "$directory" ;;
    *) hijpass_json_error 'unknown job action'; exit 1 ;;
esac
