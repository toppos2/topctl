#!/bin/bash
# ============================================================================
#  Module: System Updates
#  Checks update configuration and pending security patches
# ============================================================================

run_updates() {
    section "System Update Configuration"

    # Detect package manager
    local pkg_manager=""
    if command -v apt-get &>/dev/null; then
        pkg_manager="apt"
    elif command -v yum &>/dev/null; then
        pkg_manager="yum"
    elif command -v dnf &>/dev/null; then
        pkg_manager="dnf"
    fi

    if [[ -z "${pkg_manager}" ]]; then
        log "WARN" "Could not detect package manager"
        return
    fi

    log "INFO" "Package manager: ${pkg_manager}"

    # --- Check 1: Pending security updates ------------------------------------
    echo ""
    log "INFO" "Checking for pending security updates..."

    case "${pkg_manager}" in
        apt)
            # Update package lists (quiet)
            apt-get update -qq &>/dev/null 2>&1

            local upgradable
            upgradable=$(apt list --upgradable 2>/dev/null | grep -c "security" || true)
            local total_upgradable
            total_upgradable=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l || true)

            if [[ ${total_upgradable} -eq 0 ]]; then
                log "PASS" "System is fully up to date"
            else
                log "FAIL" "${total_upgradable} packages need updating (${upgradable} security)"
                if [[ "${MODE}" == "fix" ]]; then
                    log "INFO" "Installing security updates..."
                    apt-get upgrade -y -o Dpkg::Options::="--force-confold" &>/dev/null
                    log "FIX" "Security updates installed"
                fi
            fi
            ;;
        yum|dnf)
            local updates
            updates=$("${pkg_manager}" check-update --security 2>/dev/null | grep -c ".*\." || true)
            if [[ ${updates} -eq 0 ]]; then
                log "PASS" "No pending security updates"
            else
                log "FAIL" "${updates} security updates pending"
            fi
            ;;
    esac

    # --- Check 2: Automatic security updates ----------------------------------
    echo ""
    log "INFO" "Checking automatic update configuration..."

    case "${pkg_manager}" in
        apt)
            if dpkg -l | grep -q "unattended-upgrades" 2>/dev/null; then
                log "PASS" "unattended-upgrades package is installed"

                # Check if actually enabled
                if [[ -f "/etc/apt/apt.conf.d/20auto-upgrades" ]]; then
                    if grep -q 'APT::Periodic::Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
                        log "PASS" "Automatic security updates are enabled"
                    else
                        log "FAIL" "unattended-upgrades is installed but not enabled"
                    fi
                else
                    log "FAIL" "Auto-upgrades config file missing"
                fi
            else
                log "FAIL" "unattended-upgrades is not installed"
                if [[ "${MODE}" == "fix" ]]; then
                    apt-get install -y unattended-upgrades &>/dev/null
                    # Enable it
                    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF
                    log "FIX" "Installed and enabled unattended-upgrades"
                fi
            fi
            ;;
        yum|dnf)
            if rpm -q yum-cron &>/dev/null 2>&1 || rpm -q dnf-automatic &>/dev/null 2>&1; then
                log "PASS" "Automatic updates package installed"
            else
                log "FAIL" "No automatic update mechanism configured"
            fi
            ;;
    esac

    # --- Check 3: Kernel version info -----------------------------------------
    echo ""
    log "INFO" "Kernel information:"
    log "INFO" "  Running: $(uname -r)"

    # Check if reboot is needed (Debian/Ubuntu)
    if [[ -f "/var/run/reboot-required" ]]; then
        log "WARN" "System reboot required to apply updates"
    else
        log "PASS" "No reboot pending"
    fi

    # --- Check 4: GPG key verification ----------------------------------------
    echo ""
    case "${pkg_manager}" in
        apt)
            if apt-key list 2>/dev/null | grep -q "pub"; then
                log "PASS" "APT GPG keys are configured"
            else
                log "WARN" "No APT GPG keys found - package verification may fail"
            fi
            ;;
    esac
}
