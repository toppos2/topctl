#!/bin/bash
# ============================================================================
#  TopCTL - Automated Linux Security Hardening Tool
#  Author: Tops Leander 
#  Version: 0.1.0
#  License: MIT
#
#  A modular Linux hardening tool that audits and secures your system
#  based on CIS Benchmark recommendations.
# ============================================================================

set +e

# --- Colors & Formatting ---------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Global Variables -------------------------------------------------------
VERSION="0.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
REPORT_DIR="${SCRIPT_DIR}/reports"
CONFIG_FILE="${SCRIPT_DIR}/configs/topctl.conf"
REPORT_FILE="${REPORT_DIR}/topctl-report-$(date +%Y%m%d-%H%M%S).txt"
LOG_FILE="${REPORT_DIR}/topctl.log"

# Counters for summary
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
FIX_COUNT=0

# --- Mode: audit (default) or fix ------------------------------------------
MODE="audit"
MODULES_TO_RUN=()

# ============================================================================
#  Helper Functions
# ============================================================================

banner() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'

    ████████╗ ██████╗ ██████╗  ██████╗████████╗██╗
    ╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝╚══██╔══╝██║
       ██║   ██║   ██║██████╔╝██║        ██║   ██║
       ██║   ██║   ██║██╔═══╝ ██║        ██║   ██║
       ██║   ╚██████╔╝██║     ╚██████╗   ██║   ███████╗
       ╚═╝    ╚═════╝ ╚═╝      ╚═════╝   ╚═╝   ╚══════╝
       Linux Security Hardening Tool

EOF
    echo -e "    Version ${VERSION}${NC}"
    echo ""
}

usage() {
    echo -e "${BOLD}Usage:${NC} sudo ./topctl.sh [OPTIONS]"
    echo ""
    echo -e "${BOLD}Modes:${NC}"
    echo "  --audit          Scan only, report findings (default)"
    echo "  --fix            Apply hardening fixes (requires confirmation)"
    echo ""
    echo -e "${BOLD}Modules:${NC}"
    echo "  --ssh            SSH configuration hardening"
    echo "  --firewall       Firewall rules setup"
    echo "  --services       Disable unnecessary services"
    echo "  --filesystem     File permission & integrity checks"
    echo "  --users          User account security"
    echo "  --updates        System update configuration"
    echo "  --all            Run all modules (default)"
    echo ""
    echo -e "${BOLD}Other:${NC}"
    echo "  --report         Show last report"
    echo "  --help           Show this help message"
    echo ""
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Write to log file
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"

    # Write to report
    echo "[${level}] ${message}" >> "${REPORT_FILE}"

    # Print to terminal with colors
    case "${level}" in
        PASS)
            echo -e "  ${GREEN}[✓ PASS]${NC} ${message}"
            PASS_COUNT=$((PASS_COUNT + 1))
            ;;
        FAIL)
            echo -e "  ${RED}[✗ FAIL]${NC} ${message}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;
        WARN)
            echo -e "  ${YELLOW}[! WARN]${NC} ${message}"
            WARN_COUNT=$((WARN_COUNT + 1))
            ;;
        FIX)
            echo -e "  ${BLUE}[⚙ FIX]${NC}  ${message}"
            FIX_COUNT=$((FIX_COUNT + 1))
            ;;
        INFO)
            echo -e "  ${CYAN}[i INFO]${NC} ${message}"
            ;;
    esac
}

section() {
    local title="$1"
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  ${title}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo "" >> "${REPORT_FILE}"
    echo "=== ${title} ===" >> "${REPORT_FILE}"
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo -e "${RED}${BOLD}[ERROR]${NC} TopCTL must be run as root."
        echo -e "        Run: ${BOLD}sudo ./topctl.sh${NC}"
        exit 1
    fi
}

confirm_fix() {
    if [[ "${MODE}" == "fix" ]]; then
        echo ""
        echo -e "${YELLOW}${BOLD}⚠  WARNING: Fix mode will modify system configuration.${NC}"
        echo -e "${YELLOW}   A backup will be created before changes are made.${NC}"
        echo ""
        read -rp "   Continue? (y/N): " confirm
        if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
            echo -e "${RED}   Aborted.${NC}"
            exit 0
        fi
    fi
}

summary() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  SUMMARY${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}Passed:  ${PASS_COUNT}${NC}"
    echo -e "  ${RED}Failed:  ${FAIL_COUNT}${NC}"
    echo -e "  ${YELLOW}Warnings: ${WARN_COUNT}${NC}"
    if [[ "${MODE}" == "fix" ]]; then
        echo -e "  ${BLUE}Fixed:   ${FIX_COUNT}${NC}"
    fi
    echo ""

    # Security score
    local total=$((PASS_COUNT + FAIL_COUNT))
    if [[ ${total} -gt 0 ]]; then
        local score=$(( (PASS_COUNT * 100) / total ))
        echo -e "  ${BOLD}Security Score: ${score}/100${NC}"
        if [[ ${score} -ge 80 ]]; then
            echo -e "  ${GREEN}Rating: GOOD${NC}"
        elif [[ ${score} -ge 50 ]]; then
            echo -e "  ${YELLOW}Rating: NEEDS IMPROVEMENT${NC}"
        else
            echo -e "  ${RED}Rating: CRITICAL${NC}"
        fi
    fi

    echo ""
    echo -e "  Full report: ${REPORT_FILE}"
    echo ""
}

# ============================================================================
#  Parse Arguments
# ============================================================================

parse_args() {
    # Default: run all modules
    local specific_modules=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --audit)    MODE="audit"; shift ;;
            --fix)      MODE="fix"; shift ;;
            --ssh)      MODULES_TO_RUN+=("ssh"); specific_modules=true; shift ;;
            --firewall) MODULES_TO_RUN+=("firewall"); specific_modules=true; shift ;;
            --services) MODULES_TO_RUN+=("services"); specific_modules=true; shift ;;
            --filesystem) MODULES_TO_RUN+=("filesystem"); specific_modules=true; shift ;;
            --users)    MODULES_TO_RUN+=("users"); specific_modules=true; shift ;;
            --updates)  MODULES_TO_RUN+=("updates"); specific_modules=true; shift ;;
            --all)      specific_modules=false; shift ;;
            --report)
                if ls "${REPORT_DIR}"/topctl-report-*.txt 1>/dev/null 2>&1; then
                    latest=$(ls -t "${REPORT_DIR}"/topctl-report-*.txt | head -1)
                    cat "${latest}"
                else
                    echo "No reports found."
                fi
                exit 0
                ;;
            --help|-h)  usage; exit 0 ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done

    # If no specific modules selected, run all
    if [[ "${specific_modules}" == false ]]; then
        MODULES_TO_RUN=("ssh" "firewall" "services" "filesystem" "users" "updates")
    fi
}

# ============================================================================
#  Main
# ============================================================================

main() {
    parse_args "$@"
    banner
    check_root

    # Create report directory
    mkdir -p "${REPORT_DIR}"

    # Report header
    {
        echo "TopCTL Security Report"
        echo "Generated: $(date)"
        echo "Hostname:  $(hostname)"
        echo "OS:        $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
        echo "Kernel:    $(uname -r)"
        echo "Mode:      ${MODE}"
        echo "========================================"
    } > "${REPORT_FILE}"

    echo -e "  ${CYAN}Hostname:${NC} $(hostname)"
    echo -e "  ${CYAN}OS:${NC}       $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo -e "  ${CYAN}Mode:${NC}     ${MODE}"

    # Confirm if fix mode
    confirm_fix

    # Run selected modules
    for module in "${MODULES_TO_RUN[@]}"; do
        local module_file="${MODULES_DIR}/${module}.sh"
        if [[ -f "${module_file}" ]]; then
            source "${module_file}"
            "run_${module}"
        else
            log "WARN" "Module not found: ${module}"
        fi
    done

    # Print summary
    summary
}

main "$@"
