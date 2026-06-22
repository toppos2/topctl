#!/bin/bash
# ============================================================================
#  Module: User Account Security
#  Checks password policies, root access, and account hygiene
# ============================================================================

run_users() {
    section "User Account Security"

    # --- Check 1: Accounts with UID 0 (root-level) ---------------------------
    log "INFO" "Checking for accounts with UID 0..."
    local root_accounts
    root_accounts=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
    local root_count
    root_count=$(echo "${root_accounts}" | wc -w)

    if [[ ${root_count} -eq 1 && "${root_accounts}" == "root" ]]; then
        log "PASS" "Only 'root' has UID 0"
    else
        log "FAIL" "Multiple accounts with UID 0: ${root_accounts}"
    fi

    # --- Check 2: Accounts with empty passwords ------------------------------
    echo ""
    log "INFO" "Checking for accounts with empty passwords..."
    local empty_pw
    empty_pw=$(awk -F: '($2 == "" || $2 == "!") && $1 != "root" {print $1}' /etc/shadow 2>/dev/null)

    if [[ -z "${empty_pw}" ]]; then
        log "PASS" "No accounts with empty passwords"
    else
        for user in ${empty_pw}; do
            log "FAIL" "Account '${user}' has no password set"
            if [[ "${MODE}" == "fix" ]]; then
                passwd -l "${user}" &>/dev/null
                log "FIX" "Locked account '${user}'"
            fi
        done
    fi

    # --- Check 3: Password aging policy ---------------------------------------
    echo ""
    log "INFO" "Checking password aging policies..."

    if [[ -f "/etc/login.defs" ]]; then
        local pass_max
        pass_max=$(grep "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
        if [[ -n "${pass_max}" && "${pass_max}" -le 365 ]]; then
            log "PASS" "Max password age: ${pass_max} days"
        else
            log "FAIL" "Max password age is ${pass_max:-not set}, should be ≤ 365"
            if [[ "${MODE}" == "fix" ]]; then
                sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   365/' /etc/login.defs
                log "FIX" "Set PASS_MAX_DAYS to 365"
            fi
        fi

        local pass_min
        pass_min=$(grep "^PASS_MIN_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
        if [[ -n "${pass_min}" && "${pass_min}" -ge 1 ]]; then
            log "PASS" "Min days between password changes: ${pass_min}"
        else
            log "FAIL" "Min password age is ${pass_min:-0}, should be ≥ 1"
            if [[ "${MODE}" == "fix" ]]; then
                sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
                log "FIX" "Set PASS_MIN_DAYS to 1"
            fi
        fi

        local pass_warn
        pass_warn=$(grep "^PASS_WARN_AGE" /etc/login.defs 2>/dev/null | awk '{print $2}')
        if [[ -n "${pass_warn}" && "${pass_warn}" -ge 7 ]]; then
            log "PASS" "Password expiry warning: ${pass_warn} days"
        else
            log "WARN" "Password warning age is ${pass_warn:-not set}, recommend ≥ 7"
        fi
    else
        log "WARN" "/etc/login.defs not found"
    fi

    # --- Check 4: Users with login shells who shouldn't have them -------------
    echo ""
    log "INFO" "Checking system accounts with login shells..."

    while IFS=: read -r username _ uid _ _ _ shell; do
        # System accounts (UID < 1000, except root) should not have login shells
        if [[ ${uid} -lt 1000 && "${username}" != "root" ]]; then
            if [[ "${shell}" != "/usr/sbin/nologin" && "${shell}" != "/bin/false" && "${shell}" != "/sbin/nologin" ]]; then
                log "WARN" "System account '${username}' (UID ${uid}) has shell: ${shell}"
            fi
        fi
    done < /etc/passwd

    log "PASS" "System account shell check complete"

    # --- Check 5: Sudo configuration ------------------------------------------
    echo ""
    log "INFO" "Checking sudo configuration..."

    # Check if NOPASSWD is used
    if grep -rq "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
        log "WARN" "NOPASSWD entries found in sudoers - review recommended"
        grep -r "NOPASSWD" /etc/sudoers /etc/sudoers.d/ 2>/dev/null | while IFS= read -r line; do
            log "INFO" "  ${line}"
        done
    else
        log "PASS" "No NOPASSWD entries in sudoers"
    fi

    # Check sudoers file permissions
    if [[ -f "/etc/sudoers" ]]; then
        local sudoers_perms
        sudoers_perms=$(stat -c "%a" /etc/sudoers 2>/dev/null)
        if [[ "${sudoers_perms}" == "440" || "${sudoers_perms}" == "400" ]]; then
            log "PASS" "/etc/sudoers permissions correct (${sudoers_perms})"
        else
            log "FAIL" "/etc/sudoers permissions are ${sudoers_perms}, should be 440"
        fi
    fi

    # --- Check 6: Login banner ------------------------------------------------
    echo ""
    if [[ -f "/etc/issue.net" ]] && [[ -s "/etc/issue.net" ]]; then
        log "PASS" "Login banner exists (/etc/issue.net)"
    else
        log "WARN" "No login banner configured (/etc/issue.net)"
        if [[ "${MODE}" == "fix" ]]; then
            echo "Authorized access only. All activity is monitored and logged." > /etc/issue.net
            log "FIX" "Created login banner in /etc/issue.net"
        fi
    fi
}
