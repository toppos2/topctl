#!/bin/bash
# ============================================================================
#  Module: Firewall Hardening
#  Checks and configures UFW/iptables firewall rules
# ============================================================================

run_firewall() {
    section "Firewall Configuration"

    # --- Check 1: Is a firewall installed? -----------------------------------
    local fw_tool=""
    if command -v ufw &>/dev/null; then
        fw_tool="ufw"
    elif command -v firewalld &>/dev/null; then
        fw_tool="firewalld"
    elif command -v iptables &>/dev/null; then
        fw_tool="iptables"
    fi

    if [[ -z "${fw_tool}" ]]; then
        log "FAIL" "No firewall tool found (ufw/firewalld/iptables)"
        if [[ "${MODE}" == "fix" ]]; then
            log "INFO" "Installing UFW..."
            apt-get install -y ufw &>/dev/null && log "FIX" "UFW installed" || log "WARN" "Could not install UFW"
            fw_tool="ufw"
        fi
        [[ -z "${fw_tool}" ]] && return
    else
        log "PASS" "Firewall tool found: ${fw_tool}"
    fi

    # --- Check 2: Is the firewall active? ------------------------------------
    case "${fw_tool}" in
        ufw)
            local ufw_status
            ufw_status=$(ufw status 2>/dev/null | head -1)
            if echo "${ufw_status}" | grep -q "active"; then
                log "PASS" "UFW is active"
            else
                log "FAIL" "UFW is not active"
                if [[ "${MODE}" == "fix" ]]; then
                    # Set defaults before enabling
                    ufw default deny incoming &>/dev/null
                    ufw default allow outgoing &>/dev/null
                    ufw --force enable &>/dev/null
                    log "FIX" "UFW enabled with deny incoming / allow outgoing defaults"
                fi
            fi

            # Check default policies
            local default_in
            default_in=$(ufw status verbose 2>/dev/null | grep "Default:" | grep "incoming" | awk '{print $2}')
            if [[ "${default_in}" == "deny" || "${default_in}" == "reject" ]]; then
                log "PASS" "Default incoming policy: ${default_in}"
            else
                log "FAIL" "Default incoming policy should be deny/reject (currently: ${default_in:-unknown})"
            fi
            ;;
        iptables)
            local input_policy
            input_policy=$(iptables -L INPUT 2>/dev/null | head -1 | awk '{print $4}' | tr -d ')')
            if [[ "${input_policy}" == "DROP" || "${input_policy}" == "REJECT" ]]; then
                log "PASS" "iptables INPUT policy: ${input_policy}"
            else
                log "FAIL" "iptables INPUT default is ${input_policy:-unknown}, should be DROP"
            fi

            # Check if rules exist
            local rule_count
            rule_count=$(iptables -L INPUT 2>/dev/null | tail -n +3 | wc -l)
            if [[ "${rule_count}" -gt 0 ]]; then
                log "PASS" "iptables has ${rule_count} INPUT rules defined"
            else
                log "WARN" "No iptables INPUT rules configured"
            fi
            ;;
    esac

    # --- Check 3: SSH port is allowed (don't lock yourself out!) -------------
    if [[ "${fw_tool}" == "ufw" ]]; then
        if ufw status 2>/dev/null | grep -q "22/tcp\|22 "; then
            log "PASS" "SSH (port 22) is allowed through firewall"
        else
            log "WARN" "SSH (port 22) may not be allowed - verify before enabling firewall!"
            if [[ "${MODE}" == "fix" ]]; then
                ufw allow ssh &>/dev/null
                log "FIX" "Added SSH (22/tcp) allow rule"
            fi
        fi
    fi

    # --- Check 4: IPv6 configuration -----------------------------------------
    if [[ -f "/etc/default/ufw" ]]; then
        local ipv6_enabled
        ipv6_enabled=$(grep "^IPV6=" /etc/default/ufw | cut -d= -f2)
        if [[ "${ipv6_enabled}" == "yes" ]]; then
            log "PASS" "IPv6 firewall rules enabled"
        else
            log "WARN" "IPv6 firewall rules disabled - consider enabling"
        fi
    fi

    # --- Check 5: Loopback traffic -------------------------------------------
    if [[ "${fw_tool}" == "iptables" ]]; then
        if iptables -L INPUT 2>/dev/null | grep -q "lo.*ACCEPT"; then
            log "PASS" "Loopback traffic allowed"
        else
            log "WARN" "Loopback traffic rule not found"
        fi
    fi

    # --- Check 6: Log dropped packets ----------------------------------------
    if [[ "${fw_tool}" == "ufw" ]]; then
        local logging
        logging=$(ufw status verbose 2>/dev/null | grep "Logging:")
        if echo "${logging}" | grep -qiE "(on|medium|high|full)"; then
            log "PASS" "Firewall logging is enabled"
        else
            log "FAIL" "Firewall logging is disabled"
            if [[ "${MODE}" == "fix" ]]; then
                ufw logging on &>/dev/null
                log "FIX" "Enabled firewall logging"
            fi
        fi
    fi
}
