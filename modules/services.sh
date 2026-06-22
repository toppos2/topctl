#!/bin/bash
# ============================================================================
#  Module: Unnecessary Services
#  Identifies and disables services that increase attack surface
# ============================================================================

# Services that are generally unnecessary on a server
UNNECESSARY_SERVICES=(
    "avahi-daemon"      # mDNS/DNS-SD - not needed on servers
    "cups"              # Printing - not needed on most servers
    "cups-browsed"      # Print browsing
    "isc-dhcp-server"   # DHCP server - only if you're running one
    "rpcbind"           # RPC portmapper - NFS related
    "nfs-server"        # NFS file sharing
    "vsftpd"            # FTP server - use SFTP instead
    "telnet"            # Telnet - never use this
    "rsh-server"        # Remote shell - insecure
    "xinetd"            # Internet super-server
    "tftp"              # Trivial FTP
    "autofs"            # Auto-mount filesystems
    "bluetooth"         # Bluetooth - not needed on servers
)

run_services() {
    section "Unnecessary Services Check"

    log "INFO" "Checking for services that increase attack surface..."
    echo ""

    local found_unnecessary=0

    for service in "${UNNECESSARY_SERVICES[@]}"; do
        # Check if service exists on the system
        if systemctl list-unit-files "${service}.service" &>/dev/null 2>&1; then
            local status
            status=$(systemctl is-active "${service}" 2>/dev/null)
            local enabled
            enabled=$(systemctl is-enabled "${service}" 2>/dev/null)

            if [[ "${status}" == "active" ]]; then
                log "FAIL" "${service} is running (active)"
                ((found_unnecessary++))

                if [[ "${MODE}" == "fix" ]]; then
                    systemctl stop "${service}" &>/dev/null
                    systemctl disable "${service}" &>/dev/null
                    log "FIX" "Stopped and disabled ${service}"
                fi
            elif [[ "${enabled}" == "enabled" ]]; then
                log "WARN" "${service} is enabled but not running"
                ((found_unnecessary++))

                if [[ "${MODE}" == "fix" ]]; then
                    systemctl disable "${service}" &>/dev/null
                    log "FIX" "Disabled ${service}"
                fi
            fi
        fi
    done

    if [[ ${found_unnecessary} -eq 0 ]]; then
        log "PASS" "No unnecessary services found running"
    fi

    # --- Check for listening ports -------------------------------------------
    echo ""
    log "INFO" "Checking for open listening ports..."

    if command -v ss &>/dev/null; then
        local listen_count
        listen_count=$(ss -tlnp 2>/dev/null | tail -n +2 | wc -l)
        log "INFO" "Found ${listen_count} listening TCP ports"

        # List them for awareness
        while IFS= read -r line; do
            local port prog
            port=$(echo "${line}" | awk '{print $4}' | rev | cut -d: -f1 | rev)
            prog=$(echo "${line}" | grep -oP 'users:\(\("\K[^"]+' || echo "unknown")
            log "INFO" "  Port ${port} - ${prog}"
        done < <(ss -tlnp 2>/dev/null | tail -n +2)
    fi

    # --- Check for world-writable scripts in init ----------------------------
    echo ""
    log "INFO" "Checking for world-writable init scripts..."

    local ww_scripts
    ww_scripts=$(find /etc/init.d/ -perm -o+w -type f 2>/dev/null)
    if [[ -n "${ww_scripts}" ]]; then
        while IFS= read -r script; do
            log "FAIL" "World-writable init script: ${script}"
            if [[ "${MODE}" == "fix" ]]; then
                chmod o-w "${script}"
                log "FIX" "Removed world-writable permission from ${script}"
            fi
        done <<< "${ww_scripts}"
    else
        log "PASS" "No world-writable init scripts found"
    fi
}
