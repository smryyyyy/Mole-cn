#!/bin/bash
# Optimization Tasks

set -euo pipefail

# Config constants (override via env).
readonly MOLE_TM_THIN_TIMEOUT=180
readonly MOLE_TM_THIN_VALUE=9999999999
readonly MOLE_SQLITE_MAX_SIZE=104857600 # 100MB

# 预览模式 aware output.
opt_msg() {
    local message="$1"
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $message"
    else
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $message"
    fi
}

opt_numeric_kb() {
    local size_kb="${1:-0}"
    [[ "$size_kb" =~ ^[0-9]+$ ]] && echo "$size_kb" || echo "0"
}

opt_existing_path_size_kb() {
    local path="$1"
    [[ -e "$path" ]] || {
        echo "0"
        return 0
    }

    opt_numeric_kb "$(get_path_size_kb "$path" 2> /dev/null || echo "0")"
}

run_launchctl_unload() {
    local plist_file="$1"
    local need_sudo="${2:-false}"

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        return 0
    fi

    if [[ "$need_sudo" == "true" ]]; then
        sudo launchctl unload "$plist_file" 2> /dev/null || true
    else
        launchctl unload "$plist_file" 2> /dev/null || true
    fi
}

needs_permissions_repair() {
    local owner
    owner=$(stat -f %Su "$HOME" 2> /dev/null || echo "")
    if [[ -n "$owner" && "$owner" != "$USER" ]]; then
        return 0
    fi

    local -a paths=(
        "$HOME"
        "$HOME/Library"
        "$HOME/Library/Preferences"
    )
    local path
    for path in "${paths[@]}"; do
        if [[ -e "$path" && ! -w "$path" ]]; then
            return 0
        fi
    done

    return 1
}

has_bluetooth_hid_connected() {
    local bt_report
    bt_report=$(system_profiler SPBluetoothDataType 2> /dev/null || echo "")
    if ! echo "$bt_report" | grep -q "已连接"; then
        return 1
    fi

    if echo "$bt_report" | grep -Eiq "Keyboard|Trackpad|Mouse|HID"; then
        return 0
    fi

    return 1
}

is_ac_power() {
    pmset -g batt 2> /dev/null | grep -q "AC Power"
}

is_memory_pressure_high() {
    if ! command -v memory_pressure > /dev/null 2>&1; then
        return 1
    fi

    local mp_output
    mp_output=$(memory_pressure -Q 2> /dev/null || echo "")
    if echo "$mp_output" | grep -Eiq "warning|critical"; then
        return 0
    fi

    return 1
}

has_active_vpn_interface() {
    case "${MOLE_ASSUME_VPN_ACTIVE:-}" in
        1 | true | TRUE | yes | YES)
            return 0
            ;;
        0 | false | FALSE | no | NO)
            return 1
            ;;
    esac

    if command -v netstat > /dev/null 2>&1; then
        if netstat -rn -f inet 2> /dev/null | grep -Eq '[[:space:]]utun[0-9]+($|[[:space:]])'; then
            return 0
        fi
    fi

    if command -v ifconfig > /dev/null 2>&1; then
        if ifconfig 2> /dev/null | grep -Eq '^utun[0-9]+:.*<[^>]*(UP|RUNNING)'; then
            return 0
        fi
    fi

    return 1
}

flush_dns_cache() {
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        MOLE_DNS_FLUSHED=1
        return 0
    fi

    if sudo dscacheutil -flushcache 2> /dev/null && sudo killall -HUP mDNSResponder 2> /dev/null; then
        MOLE_DNS_FLUSHED=1
        return 0
    fi
    return 1
}

# Basic system maintenance.
opt_system_maintenance() {
    if flush_dns_cache; then
        opt_msg "DNS 缓存已刷新"
    fi

    local spotlight_status
    spotlight_status=$(mdutil -s / 2> /dev/null || echo "")
    if echo "$spotlight_status" | grep -qi "索引已禁用"; then
        echo -e "  ${GRAY}${ICON_EMPTY}${NC} Spotlight indexing disabled"
    else
        opt_msg "Spotlight 索引已验证"
    fi
}

# Refresh Finder caches (QuickLook/icon services).
opt_cache_refresh() {
    local total_cache_size=0

    local -a cache_targets=(
        "$HOME/Library/Caches/com.apple.QuickLook.thumbnailcache"
        "$HOME/Library/Caches/com.apple.iconservices.store"
        "$HOME/Library/Caches/com.apple.iconservices"
    )
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "Finder 缓存刷新" "Refresh QuickLook thumbnails and icon services"
        debug_operation_detail "Method" "Remove cache files and rebuild via qlmanage"
        debug_operation_detail "Expected outcome" "Faster Finder 预览 generation, fixed icon display issues"
        debug_risk_level "LOW" "Caches are automatically rebuilt"
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        qlmanage -r cache > /dev/null 2>&1 || true
        qlmanage -r > /dev/null 2>&1 || true
    fi

    local -a removable_targets=()
    local -a removable_sizes=()

    local target_path=""
    for target_path in "${cache_targets[@]}"; do
        [[ -e "$target_path" ]] || continue
        should_protect_path "$target_path" && continue

        local size_kb
        size_kb=$(opt_existing_path_size_kb "$target_path")
        removable_targets+=("$target_path")
        removable_sizes+=("$size_kb")
        total_cache_size=$((total_cache_size + size_kb))
    done

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        if [[ ${#removable_targets[@]} -eq 0 ]]; then
            debug_operation_detail "Files to be removed" "none"
        else
            debug_operation_detail "Files to be removed" ""
            local index
            for index in "${!removable_targets[@]}"; do
                local size_human="unknown"
                if [[ "${removable_sizes[$index]}" -gt 0 ]]; then
                    size_human=$(bytes_to_human "$((removable_sizes[index] * 1024))")
                fi
                debug_file_action "  Will remove" "${removable_targets[$index]}" "$size_human" ""
            done
        fi
    fi

    local index
    for index in "${!removable_targets[@]}"; do
        safe_remove "${removable_targets[$index]}" true "${removable_sizes[$index]}" > /dev/null 2>&1 || true
    done

    export OPTIMIZE_CACHE_CLEANED_KB="${total_cache_size}"
    opt_msg "QuickLook 缩略图已刷新"
    opt_msg "图标服务缓存已重建"
}

# Removed: opt_maintenance_scripts - macOS handles log rotation automatically via launchd

# Removed: opt_radio_refresh - Interrupts active user connections (WiFi, Bluetooth), degrading UX

# Old saved states cleanup.
opt_saved_state_cleanup() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "App Saved State Cleanup" "Remove old application saved states"
        debug_operation_detail "Method" "Find and remove .savedState folders older than $MOLE_SAVED_STATE_AGE_DAYS days"
        debug_operation_detail "Location" "$HOME/Library/Saved Application State"
        debug_operation_detail "Expected outcome" "Reduced disk usage, 个应用 start with clean state"
        debug_risk_level "LOW" "Old saved states, 个应用 will create new ones"
    fi

    local state_dir="$HOME/Library/Saved Application State"

    if [[ -d "$state_dir" ]]; then
        while IFS= read -r -d '' state_path; do
            if should_protect_path "$state_path"; then
                continue
            fi
            safe_remove "$state_path" true > /dev/null 2>&1 || true
        done < <(command find "$state_dir" -type d -name "*.savedState" -mtime "+$MOLE_SAVED_STATE_AGE_DAYS" -print0 2> /dev/null)
    fi

    opt_msg "应用保存状态已优化"
}

# Removed: opt_swap_cleanup - Direct virtual memory operations pose system crash risk

# Removed: opt_startup_cache - Modern macOS has no such mechanism

# Removed: opt_local_snapshots - Deletes user Time Machine recovery points, breaks backup continuity

opt_fix_broken_configs() {
    local spinner_started="false"
    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "正在检查 preferences..."
        spinner_started="true"
    fi

    local broken_prefs=$(fix_broken_preferences)

    if [[ "$spinner_started" == "true" ]]; then
        stop_inline_spinner
    fi

    export OPTIMIZE_CONFIGS_REPAIRED="${broken_prefs}"
    if [[ $broken_prefs -gt 0 ]]; then
        opt_msg "已修复 $broken_prefs 个损坏的偏好文件"
    else
        opt_msg "所有偏好文件有效"
    fi
}

# DNS cache refresh.
opt_network_optimization() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "Network Optimization" "Refresh DNS cache and restart mDNSResponder"
        debug_operation_detail "Method" "Flush DNS cache via dscacheutil and killall mDNSResponder"
        debug_operation_detail "Expected outcome" "Faster DNS resolution, fixed network connectivity issues"
        debug_risk_level "LOW" "DNS cache is automatically rebuilt"
    fi

    if [[ "${MOLE_DNS_FLUSHED:-0}" == "1" ]]; then
        opt_msg "DNS 缓存已刷新"
        opt_msg "mDNSResponder 已重启"
        return 0
    fi

    if flush_dns_cache; then
        opt_msg "DNS cache refreshed"
        opt_msg "mDNSResponder 已重启"
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to refresh DNS cache"
    fi
}

# Quarantine database cleanup (Gatekeeper download history).
opt_quarantine_cleanup() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "隔离数据库清理" "Clear Gatekeeper download tracking history"
        debug_operation_detail "Method" "DELETE + VACUUM on QuarantineEventsV2 SQLite database"
        debug_operation_detail "Safety" "Only clears download tracking metadata, does not affect file quarantine flags"
        debug_operation_detail "Expected outcome" "Reduced database size, cleared download tracking history"
        debug_risk_level "LOW" "Database is automatically recreated by macOS"
    fi

    if ! command -v sqlite3 > /dev/null 2>&1; then
        echo -e "  ${GRAY}-${NC} Quarantine cleanup skipped, sqlite3 unavailable"
        return 0
    fi

    local quarantine_db="$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"

    if [[ ! -f "$quarantine_db" ]]; then
        opt_msg "隔离数据库已清理"
        return 0
    fi

    if should_protect_path "$quarantine_db"; then
        opt_msg "隔离数据库已清理"
        return 0
    fi

    # Check if database has any entries worth cleaning.
    local row_count
    row_count=$(run_with_timeout 5 sqlite3 "$quarantine_db" "SELECT COUNT(*) FROM LSQuarantineEvent;" 2> /dev/null || echo "0")

    if [[ ! "$row_count" =~ ^[0-9]+$ ]] || [[ "$row_count" -eq 0 ]]; then
        opt_msg "隔离数据库已清理"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        local exit_code=0
        set +e
        run_with_timeout 10 sqlite3 "$quarantine_db" "DELETE FROM LSQuarantineEvent; VACUUM;" 2> /dev/null
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 ]]; then
            opt_msg "隔离区历史已清除（$row_count 条记录）"
        else
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to clean quarantine database"
        fi
    else
        opt_msg "隔离区历史已清除（$row_count 条记录）"
    fi
}

# SQLite vacuum for Mail/Messages/Safari (safety checks applied).
opt_sqlite_vacuum() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "数据库优化" "Vacuum SQLite databases for Mail, Safari, and Messages"
        debug_operation_detail "Method" "Run VACUUM command on databases after integrity check"
        debug_operation_detail "Safety checks" "Skip if 个应用 are running, verify integrity first, 20s timeout"
        debug_operation_detail "Expected outcome" "Reduced database size, faster app performance"
        debug_risk_level "LOW" "Only optimizes databases, does not delete data"
    fi

    if ! command -v sqlite3 > /dev/null 2>&1; then
        echo -e "  ${GRAY}-${NC} Database optimization already optimal, sqlite3 unavailable"
        return 0
    fi

    local -a busy_apps=()
    local -a check_apps=("Mail" "Safari" "Messages")
    local app
    for app in "${check_apps[@]}"; do
        if pgrep -x "$app" > /dev/null 2>&1; then
            busy_apps+=("$app")
        fi
    done

    if [[ ${#busy_apps[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Close these 个应用 before database optimization: ${busy_apps[*]}"
        return 0
    fi

    local spinner_started="false"
    if [[ "${MOLE_DRY_RUN:-0}" != "1" && -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "正在优化 databases..."
        spinner_started="true"
    fi

    local -a db_paths=(
        "$HOME/Library/Mail/V*/MailData/Envelope Index*"
        "$HOME/Library/Messages/chat.db"
        "$HOME/Library/Safari/History.db"
        "$HOME/Library/Safari/TopSites.db"
    )

    local vacuumed=0
    local timed_out=0
    local failed=0
    local skipped=0

    for pattern in "${db_paths[@]}"; do
        while IFS= read -r db_file; do
            [[ ! -f "$db_file" ]] && continue
            [[ "$db_file" == *"-wal" || "$db_file" == *"-shm" ]] && continue

            should_protect_path "$db_file" && continue

            case "$(file -b "$db_file" 2> /dev/null || true)" in
                *SQLite*) ;;
                *) continue ;;
            esac

            # Skip large DBs (>100MB).
            local file_size
            file_size=$(get_file_size "$db_file")
            if [[ "$file_size" -gt "$MOLE_SQLITE_MAX_SIZE" ]]; then
                skipped=$((skipped + 1))
                continue
            fi

            # Skip if 可用list is tiny (already compact).
            local page_info=""
            page_info=$(run_with_timeout 5 sqlite3 "$db_file" "PRAGMA page_count; PRAGMA 可用list_count;" 2> /dev/null || echo "")
            local page_count=""
            local 可用list_count=""
            page_count="${page_info%%$'\n'*}"
            if [[ "$page_info" == *$'\n'* ]]; then
                可用list_count="${page_info#*$'\n'}"
                可用list_count="${可用list_count%%$'\n'*}"
            fi
            if [[ "$page_count" =~ ^[0-9]+$ && "$可用list_count" =~ ^[0-9]+$ && "$page_count" -gt 0 ]]; then
                if ((可用list_count * 100 < page_count * 5)); then
                    skipped=$((skipped + 1))
                    continue
                fi
            fi

            # Verify integrity before VACUUM.
            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                local integrity_check=""
                set +e
                integrity_check=$(run_with_timeout 10 sqlite3 "$db_file" "PRAGMA integrity_check;" 2> /dev/null)
                local integrity_status=$?
                set -e

                if [[ $integrity_status -ne 0 || "$integrity_check" != "ok" ]]; then
                    skipped=$((skipped + 1))
                    continue
                fi
            fi

            local exit_code=0
            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                set +e
                run_with_timeout 20 sqlite3 "$db_file" "VACUUM;" 2> /dev/null
                exit_code=$?
                set -e

                if [[ $exit_code -eq 0 ]]; then
                    vacuumed=$((vacuumed + 1))
                elif [[ $exit_code -eq 124 ]]; then
                    timed_out=$((timed_out + 1))
                else
                    failed=$((failed + 1))
                fi
            else
                vacuumed=$((vacuumed + 1))
            fi
        done < <(compgen -G "$pattern" || true)
    done

    if [[ "$spinner_started" == "true" ]]; then
        stop_inline_spinner
    fi

    export OPTIMIZE_DATABASES_COUNT="${vacuumed}"
    if [[ $vacuumed -gt 0 ]]; then
        opt_msg "已优化 Mail、Safari、Messages 的 $vacuumed 个数据库"
    elif [[ $timed_out -eq 0 && $failed -eq 0 ]]; then
        opt_msg "所有数据库已优化"
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Database optimization incomplete"
    fi

    if [[ $skipped -gt 0 ]]; then
        opt_msg "$skipped 个数据库已处于最佳状态"
    fi

    if [[ $timed_out -gt 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Timed out on $timed_out databases"
    fi

    if [[ $failed -gt 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 on $failed databases"
    fi
}

# LaunchServices rebuild ("Open with" issues).
opt_launch_services_rebuild() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "LaunchServices Rebuild" "Rebuild LaunchServices database"
        debug_operation_detail "Method" "Run lsregister -gc then force rescan with -r -f on local, user, and system domains"
        debug_operation_detail "Purpose" "Fix \"Open with\" menu issues, file associations, and stale app metadata"
        debug_operation_detail "Expected outcome" "Correct app associations, fixed duplicate entries, fewer stale app listings"
        debug_risk_level "LOW" "Database is automatically rebuilt"
    fi

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "正在修复 LaunchServices..."
    fi

    local lsregister
    lsregister=$(get_lsregister_path)

    if [[ -n "$lsregister" ]]; then
        local success=0

        if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
            set +e
            "$lsregister" -gc > /dev/null 2>&1 || true
            "$lsregister" -r -f -domain local -domain user -domain system > /dev/null 2>&1
            success=$?
            if [[ $success -ne 0 ]]; then
                "$lsregister" -r -f -domain local -domain user > /dev/null 2>&1
                success=$?
            fi
            set -e
        else
            success=0
        fi

        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi

        if [[ $success -eq 0 ]]; then
            opt_msg "LaunchServices 已修复"
            opt_msg "文件关联已刷新"
        else
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} 重建 LaunchServices 失败"
        fi
    else
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} lsregister not found"
    fi
}

# Font cache rebuild.
browser_family_is_running() {
    local browser_name="$1"

    case "$browser_name" in
        "Firefox")
            pgrep -if "Firefox|org\\.mozilla\\.firefox|firefox .*contentproc|firefox .*plugin-container|firefox .*crashreporter" > /dev/null 2>&1
            ;;
        "Zen Browser")
            pgrep -if "Zen Browser|org\\.mozilla\\.zen|Zen Browser Helper|zen .*contentproc" > /dev/null 2>&1
            ;;
        *)
            pgrep -ix "$browser_name" > /dev/null 2>&1
            ;;
    esac
}

opt_font_cache_rebuild() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "字体缓存重建" "Clear and rebuild font cache"
        debug_operation_detail "Method" "Run atsutil databases -remove"
        debug_operation_detail "Safety checks" "Skip when browsers or browser helpers are running to avoid cache rebuild conflicts"
        debug_operation_detail "Expected outcome" "Fixed font display issues, removed corrupted font cache"
        debug_risk_level "LOW" "系统 automatically rebuilds font database"
    fi

    local success=false

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        # Some browsers can keep stale GPU/text caches in /var/folders if system font
        # databases are reset while browser/helper processes are still running.
        local -a running_browsers=()

        local browser_name
        local -a browser_checks=(
            "Firefox"
            "Safari"
            "Google Chrome"
            "Chromium"
            "Brave Browser"
            "Microsoft Edge"
            "Arc"
            "Opera"
            "Vivaldi"
            "Zen Browser"
            "Helium"
        )
        for browser_name in "${browser_checks[@]}"; do
            if browser_family_is_running "$browser_name"; then
                running_browsers+=("$browser_name")
            fi
        done

        if [[ ${#running_browsers[@]} -gt 0 ]]; then
            local running_list
            running_list=$(printf "%s, " "${running_browsers[@]}")
            running_list="${running_list%, }"
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} 字体缓存重建已跳过 · ${running_list} 仍在运行"
            return 0
        fi

        if sudo atsutil databases -remove > /dev/null 2>&1; then
            success=true
        fi
    else
        success=true
    fi

    if [[ "$success" == "true" ]]; then
        opt_msg "字体缓存已清除"
        opt_msg "系统将自动重建字体数据库"
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to clear font cache"
    fi
}

# Removed high-risk optimizations:
# - opt_startup_items_cleanup: Risk of deleting legitimate app helpers
# - opt_dyld_cache_update: Low benefit, time-consuming, auto-managed by macOS
# - opt_system_services_refresh: Risk of data loss when killing system services

# Memory pressure relief.
opt_memory_pressure_relief() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "Memory Pressure Relief" "Release inactive memory if pressure is high"
        debug_operation_detail "Method" "Run purge command to clear inactive memory"
        debug_operation_detail "Condition" "Only runs if memory pressure is warning/critical"
        debug_operation_detail "Expected outcome" "More available memory, improved responsiveness"
        debug_risk_level "LOW" "Safe system command, does not affect active processes"
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if ! is_memory_pressure_high; then
            opt_msg "内存压力已处于最佳状态"
            return 0
        fi

        if sudo purge > /dev/null 2>&1; then
            opt_msg "非活跃内存已释放"
            opt_msg "系统响应速度已提升"
        else
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to release memory pressure"
        fi
    else
        opt_msg "非活跃内存已释放"
        opt_msg "系统响应速度已提升"
    fi
}

# Network stack reset (route + ARP).
opt_network_stack_optimize() {
    local route_flushed="false"
    local arp_flushed="false"

    if has_active_vpn_interface; then
        opt_msg "网络堆栈刷新已跳过，检测到活跃 VPN"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        local route_ok=true
        local dns_ok=true

        if ! route -n get default > /dev/null 2>&1; then
            route_ok=false
        fi
        if ! dscacheutil -q host -a name "example.com" > /dev/null 2>&1; then
            dns_ok=false
        fi

        if [[ "$route_ok" == "true" && "$dns_ok" == "true" ]]; then
            opt_msg "网络堆栈已处于最佳状态"
            return 0
        fi

        if sudo route -n flush > /dev/null 2>&1; then
            route_flushed="true"
        fi

        if sudo arp -a -d > /dev/null 2>&1; then
            arp_flushed="true"
        fi
    else
        route_flushed="true"
        arp_flushed="true"
    fi

    if [[ "$route_flushed" == "true" ]]; then
        opt_msg "网络路由表已刷新"
    fi
    if [[ "$arp_flushed" == "true" ]]; then
        opt_msg "ARP cache cleared"
    else
        if [[ "$route_flushed" == "true" ]]; then
            return 0
        fi
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to optimize network stack"
    fi
}

# User directory permissions repair.
opt_disk_permissions_repair() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "磁盘 Permissions Repair" "Reset user directory permissions"
        debug_operation_detail "Method" "Run diskutil resetUserPermissions on user home directory"
        debug_operation_detail "Condition" "Only runs if permissions issues are detected"
        debug_operation_detail "Expected outcome" "Fixed file access issues, correct ownership"
        debug_risk_level "MEDIUM" "Requires sudo, modifies permissions"
    fi

    local user_id
    user_id=$(id -u)

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if ! needs_permissions_repair; then
            opt_msg "用户目录权限已处于最佳状态"
            return 0
        fi

        if [[ -t 1 ]]; then
            start_inline_spinner "Repairing disk permissions..."
        fi

        local success=false
        if sudo diskutil resetUserPermissions / "$user_id" > /dev/null 2>&1; then
            success=true
        fi

        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi

        if [[ "$success" == "true" ]]; then
            opt_msg "用户目录权限已修复"
            opt_msg "文件访问问题已解决"
        else
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to repair permissions, may not be needed"
        fi
    else
        opt_msg "用户目录权限已修复"
        opt_msg "文件访问问题已解决"
    fi
}

# Bluetooth reset (skip if HID/audio active).
opt_bluetooth_reset() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        debug_operation_start "Bluetooth Reset" "Restart Bluetooth daemon"
        debug_operation_detail "Method" "Kill bluetoothd daemon (auto-restarts)"
        debug_operation_detail "Safety" "Skips if active Bluetooth keyboard/mouse/audio detected"
        debug_operation_detail "Expected outcome" "Fixed Bluetooth connectivity issues"
        debug_risk_level "LOW" "Daemon auto-restarts, connections auto-reconnect"
    fi

    local spinner_started="false"
    local disconnect_notice="蓝牙设备可能在刷新期间短暂断开"
    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "正在检查 Bluetooth..."
        spinner_started="true"
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if has_bluetooth_hid_connected; then
            if [[ "$spinner_started" == "true" ]]; then
                stop_inline_spinner
            fi
            opt_msg "蓝牙已处于最佳状态"
            return 0
        fi

        local bt_audio_active=false

        local audio_info
        audio_info=$(system_profiler SPAudioDataType 2> /dev/null || echo "")

        local default_output
        default_output=$(echo "$audio_info" | awk '/Default Output Device: Yes/,/^$/' 2> /dev/null || echo "")

        if echo "$default_output" | grep -qi "Transport:.*Bluetooth"; then
            bt_audio_active=true
        fi

        if [[ "$bt_audio_active" == "false" ]]; then
            if system_profiler SPBluetoothDataType 2> /dev/null | grep -q "已连接"; then
                local -a media_apps=("Music" "Spotify" "VLC" "QuickTime Player" "TV" "Podcasts" "Safari" "Google Chrome" "Chrome" "Firefox" "Arc" "IINA" "mpv")
                for app in "${media_apps[@]}"; do
                    if pgrep -x "$app" > /dev/null 2>&1; then
                        bt_audio_active=true
                        break
                    fi
                done
            fi
        fi

        if [[ "$bt_audio_active" == "true" ]]; then
            if [[ "$spinner_started" == "true" ]]; then
                stop_inline_spinner
            fi
            opt_msg "蓝牙已处于最佳状态"
            return 0
        fi

        if sudo pkill -TERM bluetoothd > /dev/null 2>&1; then
            if [[ "$spinner_started" == "true" ]]; then
                stop_inline_spinner
            fi
            echo -e "  ${GRAY}${ICON_WARNING}${NC} ${GRAY}${disconnect_notice}${NC}"
            sleep 1
            if pgrep -x bluetoothd > /dev/null 2>&1; then
                sudo pkill -KILL bluetoothd > /dev/null 2>&1 || true
            fi
            opt_msg "蓝牙模块已重启"
            opt_msg "连接问题已解决"
        else
            if [[ "$spinner_started" == "true" ]]; then
                stop_inline_spinner
            fi
            opt_msg "蓝牙已处于最佳状态"
        fi
    else
        if [[ "$spinner_started" == "true" ]]; then
            stop_inline_spinner
        fi
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} ${disconnect_notice}"
        opt_msg "蓝牙模块已重启"
        opt_msg "连接问题已解决"
    fi
}

# Spotlight index check/rebuild (only if slow).
opt_spotlight_index_optimize() {
    local spotlight_status
    spotlight_status=$(mdutil -s / 2> /dev/null || echo "")

    if echo "$spotlight_status" | grep -qi "索引已禁用"; then
        echo -e "  ${GRAY}${ICON_EMPTY}${NC} Spotlight indexing is disabled"
        return 0
    fi

    if echo "$spotlight_status" | grep -qi "索引已启用" && ! echo "$spotlight_status" | grep -qi "索引和搜索已禁用"; then
        local slow_count=0
        local test_start test_end test_duration
        for _ in 1 2; do
            test_start=$(get_epoch_seconds)
            mdfind "kMDItemFSName == 'Applications'" > /dev/null 2>&1 || true
            test_end=$(get_epoch_seconds)
            test_duration=$((test_end - test_start))
            if [[ $test_duration -gt 3 ]]; then
                slow_count=$((slow_count + 1))
            fi
            sleep 1
        done

        if [[ $slow_count -ge 2 ]]; then
            if ! is_ac_power; then
                opt_msg "Spotlight 索引已处于最佳状态"
                return 0
            fi

            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                echo -e "  ${BLUE}${ICON_INFO}${NC} Spotlight search is slow, rebuilding index, may take 1-2 hours"
                if sudo mdutil -E / > /dev/null 2>&1; then
                    opt_msg "Spotlight 索引重建已启动"
                    echo -e "  ${GRAY}Indexing will continue in background${NC}"
                else
                    echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to rebuild Spotlight index"
                fi
            else
                opt_msg "Spotlight 索引重建已启动"
            fi
        else
            opt_msg "Spotlight 索引已处于最佳状态"
        fi
    else
        opt_msg "Spotlight 索引已验证"
    fi
}

# Dock cache refresh.
opt_dock_refresh() {
    local dock_support="$HOME/Library/Application Support/Dock"
    local refreshed=false

    if [[ -d "$dock_support" ]]; then
        while IFS= read -r db_file; do
            if [[ -f "$db_file" ]]; then
                safe_remove "$db_file" true > /dev/null 2>&1 && refreshed=true
            fi
        done < <(command find "$dock_support" -name "*.db" -type f 2> /dev/null || true)
    fi

    local dock_plist="$HOME/Library/Preferences/com.apple.dock.plist"
    if [[ -f "$dock_plist" ]]; then
        touch "$dock_plist" 2> /dev/null || true
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        killall Dock 2> /dev/null || true
    fi

    if [[ "$refreshed" == "true" ]]; then
        opt_msg "Dock 缓存已清除"
    fi
    opt_msg "Dock 已刷新"
}

# Prevent .DS_Store on network and USB volumes.
# Idempotent: writes two user defaults that stop Finder from creating
# .DS_Store files on SMB/AFP/NFS shares and removable USB volumes.
# Reversible with: defaults delete com.apple.desktopservices DSDontWrite{Network,USB}Stores
opt_prevent_network_dsstore() {
    local domain="com.apple.desktopservices"
    local -a keys=("DSDontWriteNetworkStores" "DSDontWriteUSBStores")
    local changed=0
    local already=0

    for key in "${keys[@]}"; do
        local current
        current=$(defaults read "$domain" "$key" 2> /dev/null || echo "")
        if [[ "$current" == "1" ]]; then
            already=$((already + 1))
            continue
        fi

        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            changed=$((changed + 1))
            continue
        fi

        if defaults write "$domain" "$key" -bool true 2> /dev/null; then
            changed=$((changed + 1))
        fi
    done

    if [[ $changed -eq 0 && $already -gt 0 ]]; then
        opt_msg ".DS_Store 防护已在网络和 USB 卷上启用"
        return 0
    fi

    if [[ $changed -gt 0 ]]; then
        opt_msg ".DS_Store 防护已在网络和 USB 卷上启用"
    fi
}

# Broken LaunchAgent cleanup.
opt_launch_agents_cleanup() {
    local agents_dir="$HOME/Library/LaunchAgents"

    if [[ ! -d "$agents_dir" ]]; then
        opt_msg "启动代理均正常"
        return 0
    fi

    local broken_count=0
    local -a broken_plists=()

    for plist in "$agents_dir"/*.plist; do
        [[ -f "$plist" ]] || continue

        local binary=""
        binary=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2> /dev/null || true)
        if [[ -z "$binary" ]]; then
            binary=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2> /dev/null || true)
        fi

        if [[ -n "$binary" && ! -e "$binary" ]]; then
            broken_count=$((broken_count + 1))
            broken_plists+=("$plist")
        fi
    done

    if [[ $broken_count -eq 0 ]]; then
        opt_msg "启动代理均正常"
        return 0
    fi

    for plist in "${broken_plists[@]}"; do
        run_launchctl_unload "$plist"
        safe_remove "$plist" true > /dev/null 2>&1 || true
    done

    opt_msg "已清理 $broken_count 个损坏的启动代理"
}

# macOS periodic maintenance scripts (daily/weekly/monthly).
# Log path is configurable via MOLE_PERIODIC_LOG for testing; defaults to /var/log/daily.out.
# A missing log file is treated as stale and triggers maintenance.
opt_periodic_maintenance() {
    # Check if periodic command exists (removed in macOS 26+)
    if ! command -v periodic > /dev/null 2>&1; then
        opt_msg "定期维护已跳过（此 macOS 版本不支持）"
        return 0
    fi

    local daily_log="${MOLE_PERIODIC_LOG:-/var/log/daily.out}"
    local stale_days=7

    if [[ -f "$daily_log" ]]; then
        local last_mod now age_days
        last_mod=$(stat -f %m "$daily_log" 2> /dev/null || echo "0")
        now=$(get_epoch_seconds)
        age_days=$(((now - last_mod) / 86400))

        if [[ $age_days -lt $stale_days ]]; then
            opt_msg "Periodic maintenance already current (${age_days}d ago)"
            return 0
        fi
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if ! sudo -n true 2> /dev/null; then
            opt_msg "定期维护已跳过（需要 sudo）"
            return 0
        fi
        # Capture stderr so --debug can surface the real failure reason
        # (missing /etc/periodic scripts, SIP, broken launchd, etc.).
        local periodic_output rc
        if periodic_output=$(sudo periodic daily weekly monthly 2>&1); then
            opt_msg "定期维护已触发"
        else
            rc=$?
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} 失败 to run periodic maintenance (exit=$rc)"
            if [[ -n "$periodic_output" ]]; then
                debug_log "periodic stderr: $periodic_output"
            fi
        fi
    else
        opt_msg "定期维护已触发"
    fi
}

# Repair corrupted shared file list databases (Finder favorites, recent docs).
opt_shared_file_list_repair() {
    local sfl_dir="$HOME/Library/Application Support/com.apple.sharedfilelist"
    if [[ ! -d "$sfl_dir" ]]; then
        opt_msg "共享文件列表目录未找到"
        return 0
    fi

    local repaired=0
    while IFS= read -r sfl_file; do
        [[ -f "$sfl_file" ]] || continue
        # Skip recent-documents list (user data, not a cache)
        [[ "$sfl_file" == *"ApplicationRecentDocuments"* ]] && continue
        if ! plutil -lint "$sfl_file" > /dev/null 2>&1; then
            if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
                safe_remove "$sfl_file" true > /dev/null 2>&1 || true
            fi
            repaired=$((repaired + 1))
        fi
    done < <(command find "$sfl_dir" \( -name "*.sfl2" -o -name "*.sfl3" \) -type f ! -path "*ApplicationRecentDocuments*" 2> /dev/null || true)

    if [[ $repaired -gt 0 ]]; then
        opt_msg "已修复 $repaired 个损坏的共享文件列表"
    else
        opt_msg "共享文件列表均正常"
    fi
}

# Clean old delivered notifications from NotificationCenter database.
opt_notification_cleanup() {
    local nc_db_dir
    nc_db_dir="$(getconf DARWIN_USER_DIR 2> /dev/null || true)/com.apple.notificationcenter/db2"
    local nc_db="$nc_db_dir/db"

    if [[ ! -f "$nc_db" ]]; then
        opt_msg "通知中心数据库未找到"
        return 0
    fi

    local db_size
    db_size=$(opt_existing_path_size_kb "$nc_db")

    # Only clean if database exceeds 50MB (51200 KB)
    if [[ $db_size -lt 51200 ]]; then
        opt_msg "通知中心数据库正常 ($(bytes_to_human $((db_size * 1024))))"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        if command -v sqlite3 > /dev/null 2>&1; then
            local sql_ok=0
            sqlite3 "$nc_db" \
                "DELETE FROM record WHERE delivered_date < strftime('%s','now','-30 days'); VACUUM;" \
                2> /dev/null || sql_ok=$?
            if [[ $sql_ok -eq 0 ]]; then
                killall NotificationCenter 2> /dev/null || true
                opt_msg "通知中心数据库已清理（原大小 $(bytes_to_human $((db_size * 1024))))"
            else
                echo -e "  ${YELLOW}${ICON_WARNING}${NC} Notification Center cleanup skipped (database busy or locked)"
            fi
        else
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} sqlite3 not available"
        fi
    else
        opt_msg "通知中心数据库已清理（原大小 $(bytes_to_human $((db_size * 1024))))"
    fi
}

# Verify filesystem integrity via diskutil.
# Disabled by default: diskutil verifyVolume triggers kernel-level I/O that
# cannot be interrupted by SIGKILL when the volume has APFS inconsistencies,
# causing the system to 可用ze. Set MOLE_ENABLE_DISK_VERIFY=1 to opt in.
opt_disk_verify() {
    if [[ "${MOLE_ENABLE_DISK_VERIFY:-0}" != "1" ]]; then
        opt_msg "磁盘验证已跳过（设置 MOLE_ENABLE_DISK_VERIFY=1 以启用）"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        opt_msg "磁盘验证 · 预览模式下已跳过"
        return 0
    fi

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Verifying disk filesystem..."
    fi
    local output
    output=$(run_with_timeout 30 diskutil verifyVolume / 2>&1 || true)
    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if echo "$output" | grep -qi "appears to be OK\|volume appears to be ok"; then
        opt_msg "磁盘文件系统验证通过"
    elif echo "$output" | grep -qi "error\|corrupt\|invalid"; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} 磁盘 issues detected · run: sudo diskutil repairVolume /"
    else
        opt_msg "磁盘验证完成"
    fi
}

# Clean Knowledge/CoreDuet usage tracking databases.
opt_coreduet_cleanup() {
    local knowledge_dir="$HOME/Library/Application Support/Knowledge"
    local knowledge_db="$knowledge_dir/knowledgeC.db"

    if [[ ! -f "$knowledge_db" ]]; then
        opt_msg "知识数据库未找到"
        return 0
    fi

    # Check combined size of WAL/SHM files + database
    local wal_file="$knowledge_db-wal"
    local shm_file="$knowledge_db-shm"
    local total_size=0
    local -a knowledge_files=()

    for f in "$knowledge_db" "$wal_file" "$shm_file"; do
        [[ -f "$f" ]] && knowledge_files+=("$f")
    done

    if [[ ${#knowledge_files[@]} -gt 0 ]]; then
        total_size=$(command du -skcP "${knowledge_files[@]}" 2> /dev/null | awk 'END {print $1 + 0}' || echo "0")
        total_size=$(opt_numeric_kb "$total_size")
    fi

    # Skip if combined size < 100MB (102400 KB)
    if [[ $total_size -lt 102400 ]]; then
        opt_msg "知识数据库正常 ($(bytes_to_human $((total_size * 1024))))"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        # Remove WAL and SHM files safely (auto-regenerated by SQLite)
        for f in "$wal_file" "$shm_file"; do
            [[ -f "$f" ]] && safe_remove "$f" true > /dev/null 2>&1 || true
        done
        # Remove ZOBJECT entries older than 90 days (CoreTime is Mac epoch: seconds since 2001-01-01)
        if command -v sqlite3 > /dev/null 2>&1; then
            local sql_ok=0
            sqlite3 "$knowledge_db" \
                "DELETE FROM ZOBJECT WHERE ZCREATIONDATE < (strftime('%s','now','-90 days') - strftime('%s','2001-01-01')); VACUUM;" \
                2> /dev/null || sql_ok=$?
            if [[ $sql_ok -eq 0 ]]; then
                opt_msg "知识数据库已清理（原大小 $(bytes_to_human $((total_size * 1024))))"
            else
                echo -e "  ${YELLOW}${ICON_WARNING}${NC} Knowledge database cleanup skipped (database busy or locked)"
            fi
        else
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} sqlite3 not available"
        fi
    else
        opt_msg "知识数据库已清理（原大小 $(bytes_to_human $((total_size * 1024))))"
    fi
}

# Audit login items for broken entries referencing missing 个应用.
# Check if a login item name corresponds to an installed app.
# Login item names often differ from .app bundle names (e.g. "AliLangClient" -> "AliLang.app",
# "Top Calendar" -> "TopCalendar.app"), so we try multiple matching strategies.
_login_item_app_exists() {
    local name="$1"
    # 1. Exact match
    if mdfind "kMDItemFSName == '${name}.app'" 2> /dev/null | grep -q .; then
        return 0
    fi
    # 2. Try without spaces (e.g. "Top Calendar" -> "TopCalendar")
    local nospace="${name// /}"
    if [[ "$nospace" != "$name" ]] && mdfind "kMDItemFSName == '${nospace}.app'" 2> /dev/null | grep -q .; then
        return 0
    fi
    # 3. Strip common helper suffixes (e.g. "AliLangClient" -> "AliLang")
    local stripped
    stripped=$(echo "$nospace" | sed -E 's/(Client|Helper|Agent|Launcher|Service)$//')
    if [[ "$stripped" != "$nospace" ]] && mdfind "kMDItemFSName == '${stripped}.app'" 2> /dev/null | grep -q .; then
        return 0
    fi
    # 4. Recursive filesystem fallback for nested helper 个应用 inside parent
    #    bundles. Spotlight often misses helpers under Contents/.
    local candidate roots app_name
    local -a app_names=("${name}.app")
    [[ "$nospace" != "$name" ]] && app_names+=("${nospace}.app")
    [[ "$stripped" != "$nospace" ]] && app_names+=("${stripped}.app")
    for roots in "/Applications" "$HOME/Applications"; do
        [[ -d "$roots" ]] || continue
        local -a name_expr=()
        for app_name in "${app_names[@]}"; do
            if [[ ${#name_expr[@]} -gt 0 ]]; then
                name_expr+=("-o")
            fi
            name_expr+=("-name" "$app_name")
        done
        candidate=$(command find "$roots" -maxdepth 6 -type d \( "${name_expr[@]}" \) -print -quit 2> /dev/null || true)
        if [[ -n "$candidate" && -d "$candidate" ]]; then
            return 0
        fi
    done
    # 5. Fallback: check sfltool dumpbtm for the actual on-disk path.
    #    Nested helper 个应用 (e.g. DBnginMenuHelper.app inside DBngin.app) are
    #    invisible to mdfind but still have a valid URL in the BTM database.
    local btm_path
    btm_path=$(sfltool dumpbtm 2> /dev/null | awk -v item="$name" '
        BEGIN { IGNORECASE = 1 }
        index($0, item) {
            if (match($0, "/.*\\.app")) {
                print substr($0, RSTART, RLENGTH)
                exit
            }
        }
    ')
    if [[ -n "$btm_path" ]] && [[ -e "$btm_path" ]]; then
        return 0
    fi
    return 1
}

opt_login_items_audit() {
    if [[ "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        opt_msg "登录项审计 · 测试模式下已跳过"
        return 0
    fi

    local items_output
    items_output=$(osascript -e 'tell application "系统 Events" to get the name of every login item' 2> /dev/null || true)

    if [[ -z "$items_output" ]]; then
        opt_msg "未发现登录项"
        return 0
    fi

    local broken=0
    local checked=0
    # Split on ", " (comma-space) to preserve multi-word names like "Top Calendar" and "mihomo-party"
    local old_ifs="$IFS"
    IFS=',' read -ra items_list <<< "$items_output"
    IFS="$old_ifs"
    for item in "${items_list[@]}"; do
        # Strip leading/trailing spaces from each token
        item="${item# }"
        item="${item% }"
        [[ -z "$item" ]] && continue
        # Skip items with single quotes to avoid breaking the mdfind query string
        [[ "$item" == *"'"* ]] && continue
        checked=$((checked + 1))
        if _login_item_app_exists "$item"; then
            continue
        fi
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} 损坏的登录项： $item (应用未找到)"
        broken=$((broken + 1))
    done

    if [[ $broken -eq 0 ]]; then
        opt_msg "登录项全部正常（已检查 $checked 项）"
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} $broken 个损坏的登录项 · remove via 系统 Settings > General > 登录项"
    fi
}

# Dispatch optimization by action name.
execute_optimization() {
    local action="$1"
    local path="${2:-}"

    if command -v is_whitelisted > /dev/null && is_whitelisted "$action"; then
        opt_msg "已跳过 (whitelisted): $action"
        return 0
    fi

    case "$action" in
        system_maintenance) opt_system_maintenance ;;
        cache_refresh) opt_cache_refresh ;;
        saved_state_cleanup) opt_saved_state_cleanup ;;
        fix_broken_configs) opt_fix_broken_configs ;;
        network_optimization) opt_network_optimization ;;
        quarantine_cleanup) opt_quarantine_cleanup ;;
        sqlite_vacuum) opt_sqlite_vacuum ;;
        launch_services_rebuild) opt_launch_services_rebuild ;;
        font_cache_rebuild) opt_font_cache_rebuild ;;
        dock_refresh) opt_dock_refresh ;;
        prevent_network_dsstore) opt_prevent_network_dsstore ;;
        memory_pressure_relief) opt_memory_pressure_relief ;;
        network_stack_optimize) opt_network_stack_optimize ;;
        disk_permissions_repair) opt_disk_permissions_repair ;;
        bluetooth_reset) opt_bluetooth_reset ;;
        spotlight_index_optimize) opt_spotlight_index_optimize ;;
        launch_agents_cleanup) opt_launch_agents_cleanup ;;
        periodic_maintenance) opt_periodic_maintenance ;;
        shared_file_list_repair) opt_shared_file_list_repair ;;
        notification_cleanup) opt_notification_cleanup ;;
        disk_verify) opt_disk_verify ;;
        coreduet_cleanup) opt_coreduet_cleanup ;;
        login_items_audit) opt_login_items_audit ;;
        *)
            echo -e "${YELLOW}${ICON_ERROR}${NC} 未知 action: $action"
            return 1
            ;;
    esac
}
