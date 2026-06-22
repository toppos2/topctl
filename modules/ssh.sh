#!/bin/bash
# ============================================================================
#  Module: SSH Hardening
#  Checks and fixes SSH configuration based on CIS Benchmarks
# ============================================================================

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_BACKUP="/etc/ssh/sshd_config.topctl.bak"

# Helper: check an sshd_config setting
check_ssh_setting() {
    local setting="$1"
    local expected="$2"
    local description="$3"

    # Get the effective value (last uncommented occurrence wins)
    local current
    current=$(grep -i "^${setting}" "${SSHD_CONFIG}" 2>/dev/null | tail -1 | awk '{print $2}' || true)

    if [[ "${current,,}" == "${expected,,}" ]]; then
        log "PASS" "${description} (${setting} = ${current})"
        return 0
    else
        if [[ -z "${current}" ]]; then
            log "FAIL" "${description} (${setting} is not set, should be ${expected})"
        else
            log "FAIL" "${description} (${setting} = ${current}, should be ${expected})"
        fi
        return 1
    fi
}

# Helper: fix an sshd_config setting
fix_ssh_setting() {
    local setting="$1"
    local value="$2"

    if [[ "${MODE}" != "fix" ]]; then
        return
    fi

    # Create backup on first fix
    if [[ ! -f "${SSHD_BACKUP}" ]]; then
        cp "${SSHD_CONFIG}" "${SSHD_BACKUP}"
        log "INFO" "Backup created: ${SSHD_BACKUP}"
    fi

    # Remove existing lines for this setting
    sed -i "/^#\?${setting}\s/d" "${SSHD_CONFIG}"

    # Append the correct setting
    echo "${setting} ${value}" >> "${SSHD_CONFIG}"
    log "FIX" "Set ${setting} = ${value}"
}

run_ssh() {
    section "SSH Configuration Hardening"

    # Check if sshd_config exists
    if [[ ! -f "${SSHD_CONFIG}" ]]; then
        log "WARN" "SSH config not found at ${SSHD_CONFIG} - skipping"
        return
    fi

    # --- Check 1: Disable root login ----------------------------------------
    if ! check_ssh_setting "PermitRootLogin" "no" "Root login disabled"; then
        fix_ssh_setting "PermitRootLogin" "no"
    fi

    # --- Check 2: Disable password authentication ----------------------------
    if ! check_ssh_setting "PasswordAuthentication" "no" "Password authentication disabled"; then
        fix_ssh_setting "PasswordAuthentication" "no"
    fi

    # --- Check 3: Use SSH Protocol 2 only -----------------------------------
    if ! check_ssh_setting "Protocol" "2" "SSH Protocol 2 enforced"; then
        fix_ssh_setting "Protocol" "2"
    fi

    # --- Check 4: Disable empty passwords ------------------------------------
    if ! check_ssh_setting "PermitEmptyPasswords" "no" "Empty passwords disabled"; then
        fix_ssh_setting "PermitEmptyPasswords" "no"
    fi

    # --- Check 5: Set MaxAuthTries -------------------------------------------
    local max_auth
    max_auth=$(grep -i "^MaxAuthTries" "${SSHD_CONFIG}" 2>/dev/null | tail -1 | awk '{print $2}' || true)
    if [[ -n "${max_auth}" && "${max_auth}" -le 4 ]]; then
        log "PASS" "MaxAuthTries is limited (${max_auth})"
    else
        log "FAIL" "MaxAuthTries too high or not set (${max_auth:-default}), should be ≤ 4"
        fix_ssh_setting "MaxAuthTries" "3"
    fi

    # --- Check 6: Disable X11 Forwarding ------------------------------------
    if ! check_ssh_setting "X11Forwarding" "no" "X11 Forwarding disabled"; then
        fix_ssh_setting "X11Forwarding" "no"
    fi

    # --- Check 7: Set login grace time ---------------------------------------
    local grace
    grace=$(grep -i "^LoginGraceTime" "${SSHD_CONFIG}" 2>/dev/null | tail -1 | awk '{print $2}' || true)
    if [[ -n "${grace}" && "${grace}" -le 60 ]]; then
        log "PASS" "LoginGraceTime is limited (${grace}s)"
    else
        log "FAIL" "LoginGraceTime too high or not set (${grace:-default}), should be ≤ 60s"
        fix_ssh_setting "LoginGraceTime" "60"
    fi

    # --- Check 8: Idle timeout -----------------------------------------------
    if ! check_ssh_setting "ClientAliveInterval" "300" "Client alive interval set (5 min)"; then
        fix_ssh_setting "ClientAliveInterval" "300"
    fi

    if ! check_ssh_setting "ClientAliveCountMax" "2" "Client alive max count set"; then
        fix_ssh_setting "ClientAliveCountMax" "2"
    fi

    # --- Check 9: Strong ciphers only ----------------------------------------
    local ciphers
    ciphers=$(grep -i "^Ciphers" "${SSHD_CONFIG}" 2>/dev/null | tail -1)
    if [[ -n "${ciphers}" ]]; then
        # Check for weak ciphers
        if echo "${ciphers}" | grep -qiE "(3des|arcfour|blowfish)"; then
            log "FAIL" "Weak ciphers detected in SSH config"
        else
            log "PASS" "Strong ciphers configured"
        fi
    else
        log "WARN" "No explicit cipher list set (using defaults)"
        if [[ "${MODE}" == "fix" ]]; then
            fix_ssh_setting "Ciphers" "aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
        fi
    fi

    # --- Check 10: SSH key permissions ----------------------------------------
    if [[ -d "/root/.ssh" ]]; then
        local ssh_perms
        ssh_perms=$(stat -c "%a" /root/.ssh 2>/dev/null)
        if [[ "${ssh_perms}" == "700" ]]; then
            log "PASS" "/root/.ssh permissions correct (700)"
        else
            log "FAIL" "/root/.ssh permissions are ${ssh_perms}, should be 700"
            if [[ "${MODE}" == "fix" ]]; then
                chmod 700 /root/.ssh
                log "FIX" "Set /root/.ssh permissions to 700"
            fi
        fi
    fi
}
