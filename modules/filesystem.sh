#!/bin/bash
# ============================================================================
#  Module: Filesystem Security
#  Checks file permissions, SUID/SGID binaries, and sensitive file access
# ============================================================================

run_filesystem() {
    section "Filesystem Security"

    # --- Check 1: Sensitive file permissions ----------------------------------
    log "INFO" "Checking critical file permissions..."

    declare -A FILE_PERMS=(
        ["/etc/passwd"]="644"
        ["/etc/shadow"]="640"
        ["/etc/group"]="644"
        ["/etc/gshadow"]="640"
        ["/etc/ssh/sshd_config"]="600"
        ["/boot/grub/grub.cfg"]="600"
    )

    for filepath in "${!FILE_PERMS[@]}"; do
        if [[ -f "${filepath}" ]]; then
            local expected="${FILE_PERMS[${filepath}]}"
            local actual
            actual=$(stat -c "%a" "${filepath}" 2>/dev/null)

            if [[ "${actual}" == "${expected}" ]]; then
                log "PASS" "${filepath} permissions correct (${actual})"
            else
                log "FAIL" "${filepath} permissions are ${actual}, should be ${expected}"
                if [[ "${MODE}" == "fix" ]]; then
                    chmod "${expected}" "${filepath}"
                    log "FIX" "Set ${filepath} to ${expected}"
                fi
            fi
        fi
    done

    # --- Check 2: Ownership of critical files ---------------------------------
    echo ""
    log "INFO" "Checking critical file ownership..."

    for filepath in /etc/passwd /etc/shadow /etc/group; do
        if [[ -f "${filepath}" ]]; then
            local owner group
            owner=$(stat -c "%U" "${filepath}" 2>/dev/null)
            group=$(stat -c "%G" "${filepath}" 2>/dev/null)
            if [[ "${owner}" == "root" ]]; then
                log "PASS" "${filepath} owned by root"
            else
                log "FAIL" "${filepath} owned by ${owner}, should be root"
                if [[ "${MODE}" == "fix" ]]; then
                    chown root "${filepath}"
                    log "FIX" "Changed ${filepath} owner to root"
                fi
            fi
        fi
    done

    # --- Check 3: World-writable files ----------------------------------------
    echo ""
    log "INFO" "Scanning for world-writable files (this may take a moment)..."

    local ww_count=0
    while IFS= read -r file; do
        ((ww_count++))
        if [[ ${ww_count} -le 10 ]]; then
            log "FAIL" "World-writable: ${file}"
        fi
    done < <(find / -xdev -type f -perm -0002 ! -path "/proc/*" ! -path "/sys/*" 2>/dev/null)

    if [[ ${ww_count} -eq 0 ]]; then
        log "PASS" "No world-writable files found"
    elif [[ ${ww_count} -gt 10 ]]; then
        log "WARN" "... and $((ww_count - 10)) more world-writable files"
    fi

    # --- Check 4: SUID/SGID binaries -----------------------------------------
    echo ""
    log "INFO" "Scanning for SUID/SGID binaries..."

    # Known safe SUID binaries
    local -a KNOWN_SUID=(
        "/usr/bin/passwd" "/usr/bin/sudo" "/usr/bin/su"
        "/usr/bin/newgrp" "/usr/bin/chsh" "/usr/bin/chfn"
        "/usr/bin/gpasswd" "/usr/bin/mount" "/usr/bin/umount"
        "/usr/lib/openssh/ssh-keysign"
    )

    local suid_count=0
    local unknown_suid=0
    while IFS= read -r binary; do
        ((suid_count++))
        local known=false
        for safe in "${KNOWN_SUID[@]}"; do
            if [[ "${binary}" == "${safe}" ]]; then
                known=true
                break
            fi
        done
        if [[ "${known}" == false ]]; then
            ((unknown_suid++))
            log "WARN" "Unexpected SUID binary: ${binary}"
        fi
    done < <(find / -xdev -type f \( -perm -4000 -o -perm -2000 \) ! -path "/proc/*" 2>/dev/null)

    log "INFO" "Found ${suid_count} SUID/SGID binaries total"
    if [[ ${unknown_suid} -eq 0 ]]; then
        log "PASS" "All SUID/SGID binaries are known/expected"
    else
        log "WARN" "${unknown_suid} unexpected SUID/SGID binaries found - review recommended"
    fi

    # --- Check 5: /tmp has noexec mount option --------------------------------
    echo ""
    if mount | grep -q " /tmp "; then
        if mount | grep " /tmp " | grep -q "noexec"; then
            log "PASS" "/tmp mounted with noexec"
        else
            log "FAIL" "/tmp is not mounted with noexec option"
        fi
    else
        log "WARN" "/tmp is not a separate mount point (recommended for security)"
    fi

    # --- Check 6: No unowned files --------------------------------------------
    echo ""
    log "INFO" "Checking for unowned files..."
    local unowned_count
    unowned_count=$(find / -xdev -nouser -o -nogroup 2>/dev/null | wc -l)
    if [[ ${unowned_count} -eq 0 ]]; then
        log "PASS" "No unowned files found"
    else
        log "WARN" "Found ${unowned_count} files with no valid owner/group"
    fi
}
