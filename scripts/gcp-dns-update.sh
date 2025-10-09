#!/bin/bash
# ==============================================================================
# GCP Gitea DNS Update Script
# CMMC Level 2 / NIST SP 800-171 Compliant
# ==============================================================================
#
# Description:
#   Safe DNS record updater for Namecheap with GCP Secret Manager integration.
#   Uses read-modify-write workflow to preserve existing records.
#
# Usage: ./gcp-dns-update.sh [options]
#   -p PROJECT_ID     GCP Project ID (required)
#   -s SUBDOMAIN      Subdomain to update (e.g., "gitea", "@" for apex)
#   -d DOMAIN         Base domain (default: cui-secure.us)
#   -i IP_ADDRESS     Target IP address (required for A records)
#   -t RECORD_TYPE    Record type: A|CNAME|TXT|MX (default: A)
#   -l TTL            Time to live in seconds (default: 300)
#   -m MODE           update-single | replace-all (default: update-single)
#   -n                Dry-run mode (no actual API calls)
#   -v                Verbose output
#   -h                Show this help message
#
# Advanced Options:
#   --api-user USER   Override API user (instead of Secret Manager)
#   --api-key KEY     Override API key
#   --api-ip IP       Override whitelisted IP
#
# Examples:
#   # Update gitea A record (fetches creds from Secret Manager)
#   ./gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142
#
#   # Dry-run to preview changes
#   ./gcp-dns-update.sh -p cui-gitea-prod -s gitea -i 34.63.227.142 -n
#
#   # Update CNAME record
#   ./gcp-dns-update.sh -p cui-gitea-prod -s dashboard -t CNAME -i lb.example.com
#
#   # Use manual credentials
#   ./gcp-dns-update.sh -s gitea -i 34.63.227.142 --api-user myuser --api-key mykey --api-ip 203.0.113.10
#
# Exit Codes:
#   0 - Success
#   1 - Error
#   2 - Warning/Partial failure
#
# CMMC Controls Addressed:
#   - CM.L2-3.4.2: System Baseline Configuration
#   - AU.L2-3.3.1: Event Logging
#   - IA.L2-3.5.7: Credential Management
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly EVIDENCE_DIR="${PROJECT_ROOT}/terraform/gcp-gitea/evidence"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly EVIDENCE_FILE="${EVIDENCE_DIR}/dns-update-${TIMESTAMP}.json"
readonly NAMECHEAP_API_URL="https://api.namecheap.com/xml.response"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default values
PROJECT_ID=""
SUBDOMAIN=""
DOMAIN="cui-secure.us"
IP_ADDRESS=""
RECORD_TYPE="A"
TTL="300"
MODE="update-single"
DRY_RUN=false
VERBOSE=false

# API credentials (from Secret Manager or command line)
API_USER=""
API_KEY=""
API_IP=""

# State tracking
CURRENT_RECORDS=()
UPDATED_RECORDS=()

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*"
    fi
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Required:
  -p PROJECT_ID     GCP Project ID
  -s SUBDOMAIN      Subdomain to update (e.g., "gitea", "@" for apex)
  -i IP_ADDRESS     Target IP address (for A records) or hostname (for CNAME)

Optional:
  -d DOMAIN         Base domain (default: cui-secure.us)
  -t RECORD_TYPE    Record type: A|CNAME|TXT|MX (default: A)
  -l TTL            Time to live in seconds (default: 300)
  -m MODE           update-single | replace-all (default: update-single)
  -n                Dry-run mode (no actual API calls)
  -v                Verbose output
  -h                Show this help message

Advanced:
  --api-user USER   Override API user (instead of Secret Manager)
  --api-key KEY     Override API key
  --api-ip IP       Override whitelisted IP

Examples:
  # Update gitea A record
  $(basename "$0") -p cui-gitea-prod -s gitea -i 34.63.227.142

  # Dry-run to preview changes
  $(basename "$0") -p cui-gitea-prod -s gitea -i 34.63.227.142 -n

  # Update CNAME record
  $(basename "$0") -p cui-gitea-prod -s dashboard -t CNAME -i lb.example.com

Exit Codes:
  0 - Success
  1 - Error
  2 - Warning/Partial failure
EOF
}

# ==============================================================================
# PARAMETER PARSING
# ==============================================================================

parse_arguments() {
    local OPTIND
    while getopts "p:s:d:i:t:l:m:nvh-:" opt; do
        case "$opt" in
            p) PROJECT_ID="$OPTARG" ;;
            s) SUBDOMAIN="$OPTARG" ;;
            d) DOMAIN="$OPTARG" ;;
            i) IP_ADDRESS="$OPTARG" ;;
            t) RECORD_TYPE="$OPTARG" ;;
            l) TTL="$OPTARG" ;;
            m) MODE="$OPTARG" ;;
            n) DRY_RUN=true ;;
            v) VERBOSE=true ;;
            h) usage; exit 0 ;;
            -)
                case "$OPTARG" in
                    api-user)
                        API_USER="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                    api-key)
                        API_KEY="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                    api-ip)
                        API_IP="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                    *)
                        log_error "Unknown option --${OPTARG}"
                        usage
                        exit 1
                        ;;
                esac
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done
}

validate_parameters() {
    log_debug "Validating parameters..."

    # Check required parameters
    if [[ -z "${SUBDOMAIN}" ]]; then
        log_error "Subdomain (-s) is required"
        usage
        exit 1
    fi

    if [[ -z "${IP_ADDRESS}" ]]; then
        log_error "IP address/hostname (-i) is required"
        usage
        exit 1
    fi

    # Validate record type
    case "${RECORD_TYPE}" in
        A|CNAME|TXT|MX|AAAA) ;;
        *)
            log_error "Invalid record type: ${RECORD_TYPE} (must be A, CNAME, TXT, MX, or AAAA)"
            exit 1
            ;;
    esac

    # Validate mode
    case "${MODE}" in
        update-single|replace-all) ;;
        *)
            log_error "Invalid mode: ${MODE} (must be update-single or replace-all)"
            exit 1
            ;;
    esac

    # Validate TTL
    if ! [[ "${TTL}" =~ ^[0-9]+$ ]] || [[ "${TTL}" -lt 60 ]] || [[ "${TTL}" -gt 86400 ]]; then
        log_error "Invalid TTL: ${TTL} (must be between 60 and 86400 seconds)"
        exit 1
    fi

    # Validate domain format
    if ! [[ "${DOMAIN}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Invalid domain format: ${DOMAIN}"
        exit 1
    fi

    log_debug "Parameters validated successfully"
}

# ==============================================================================
# GCP SECRET MANAGER INTEGRATION
# ==============================================================================

fetch_secrets_from_gcp() {
    log_info "Fetching Namecheap API credentials from GCP Secret Manager..."

    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID (-p) is required to fetch secrets from Secret Manager"
        log_info "Alternatively, provide credentials via --api-user, --api-key, --api-ip"
        exit 1
    fi

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Install it or provide credentials manually."
        exit 1
    fi

    # Check if secrets exist and fetch them
    local secrets=("namecheap-api-user" "namecheap-api-key" "namecheap-api-ip")
    local failed=false

    for secret in "${secrets[@]}"; do
        log_debug "Fetching secret: ${secret}"
        if ! gcloud secrets versions access latest --secret="${secret}" --project="${PROJECT_ID}" &> /dev/null; then
            log_warn "Secret ${secret} not found in project ${PROJECT_ID}"
            failed=true
        fi
    done

    if [[ "${failed}" == "true" ]]; then
        log_error "One or more secrets not found. Create them using scripts/create-secrets.sh"
        log_info "Or provide credentials manually via --api-user, --api-key, --api-ip"
        exit 1
    fi

    # Fetch secrets
    API_USER=$(gcloud secrets versions access latest --secret="namecheap-api-user" --project="${PROJECT_ID}" 2>/dev/null || echo "")
    API_KEY=$(gcloud secrets versions access latest --secret="namecheap-api-key" --project="${PROJECT_ID}" 2>/dev/null || echo "")
    API_IP=$(gcloud secrets versions access latest --secret="namecheap-api-ip" --project="${PROJECT_ID}" 2>/dev/null || echo "")

    if [[ -z "${API_USER}" ]] || [[ -z "${API_KEY}" ]] || [[ -z "${API_IP}" ]]; then
        log_error "Failed to retrieve credentials from Secret Manager"
        exit 1
    fi

    log_success "Credentials retrieved successfully from Secret Manager"
    log_debug "API User: ${API_USER}"
    log_debug "API IP: ${API_IP}"
}

# ==============================================================================
# NAMECHEAP API FUNCTIONS
# ==============================================================================

get_current_records() {
    log_info "Fetching current DNS records for ${DOMAIN}..."

    # Ensure evidence directory exists before saving artifacts
    mkdir -p "${EVIDENCE_DIR}"

    # Split domain into SLD and TLD
    local sld="${DOMAIN%.*}"
    local tld="${DOMAIN##*.}"

    log_debug "SLD: ${sld}, TLD: ${tld}"

    local response_file="/tmp/namecheap-getHosts-${TIMESTAMP}.xml"

    # Call getHosts API
    local curl_cmd=(
        curl -sS "${NAMECHEAP_API_URL}"
        --data-urlencode "ApiUser=${API_USER}"
        --data-urlencode "ApiKey=${API_KEY}"
        --data-urlencode "UserName=${API_USER}"
        --data-urlencode "ClientIp=${API_IP}"
        --data-urlencode "Command=namecheap.domains.dns.getHosts"
        --data-urlencode "SLD=${sld}"
        --data-urlencode "TLD=${tld}"
        -o "${response_file}"
    )

    log_debug "API call: getHosts for ${DOMAIN}"

    if ! "${curl_cmd[@]}"; then
        log_error "Failed to fetch current DNS records"
        exit 1
    fi

    # Check response status
    if ! grep -q 'Status="OK"' "${response_file}"; then
        log_error "Namecheap API returned error response"
        log_error "Response saved to: ${response_file}"
        cat "${response_file}"
        exit 1
    fi

    log_success "Current DNS records retrieved successfully"
    log_debug "Response saved to: ${response_file}"

    # Save to evidence
    mkdir -p "${EVIDENCE_DIR}"
    cp "${response_file}" "${EVIDENCE_DIR}/dns-before-${TIMESTAMP}.xml"

    # Parse records (basic XML parsing)
    parse_dns_records "${response_file}"
}

parse_dns_records() {
    local xml_file="$1"
    log_debug "Parsing DNS records from ${xml_file}..."

    # Extract host records using grep/sed (basic parsing)
    # Format: HostName|RecordType|Address|TTL|MXPref
    CURRENT_RECORDS=()

    while IFS= read -r line; do
        if [[ "${line}" =~ \<host\ .* ]]; then
            local hostname=$(echo "${line}" | sed -n 's/.*Name="\([^"]*\)".*/\1/p')
            local type=$(echo "${line}" | sed -n 's/.*Type="\([^"]*\)".*/\1/p')
            local address=$(echo "${line}" | sed -n 's/.*Address="\([^"]*\)".*/\1/p')
            local ttl=$(echo "${line}" | sed -n 's/.*TTL="\([^"]*\)".*/\1/p')
            local mxpref=$(echo "${line}" | sed -n 's/.*MXPref="\([^"]*\)".*/\1/p')

            if [[ -n "${hostname}" ]]; then
                CURRENT_RECORDS+=("${hostname}|${type}|${address}|${ttl}|${mxpref}")
                log_debug "Found record: ${hostname} ${type} ${address} (TTL: ${ttl})"
            fi
        fi
    done < "${xml_file}"

    log_info "Found ${#CURRENT_RECORDS[@]} existing DNS records"
}

build_updated_records() {
    log_info "Building updated record set..."

    UPDATED_RECORDS=()
    local record_found=false
    local index=1

    if [[ "${MODE}" == "update-single" ]]; then
        # Preserve all existing records except the one we're updating
        for record in "${CURRENT_RECORDS[@]}"; do
            IFS='|' read -r hostname type address ttl mxpref <<< "${record}"

            # Skip the record we're updating
            if [[ "${hostname}" == "${SUBDOMAIN}" || ("${hostname}" == "@" && "${SUBDOMAIN}" == "@") ]]; then
                log_debug "Replacing existing record: ${hostname} ${type} ${address}"
                record_found=true
                continue
            fi

            # Keep other records
            UPDATED_RECORDS+=("HostName${index}=${hostname}")
            UPDATED_RECORDS+=("RecordType${index}=${type}")
            UPDATED_RECORDS+=("Address${index}=${address}")
            UPDATED_RECORDS+=("TTL${index}=${ttl}")
            if [[ -n "${mxpref}" && "${type}" == "MX" ]]; then
                UPDATED_RECORDS+=("MXPref${index}=${mxpref}")
            fi
            ((index++))
        done

        # Add the new/updated record
        UPDATED_RECORDS+=("HostName${index}=${SUBDOMAIN}")
        UPDATED_RECORDS+=("RecordType${index}=${RECORD_TYPE}")
        UPDATED_RECORDS+=("Address${index}=${IP_ADDRESS}")
        UPDATED_RECORDS+=("TTL${index}=${TTL}")

        if [[ "${record_found}" == "true" ]]; then
            log_info "Updating existing record: ${SUBDOMAIN} ${RECORD_TYPE} ${IP_ADDRESS}"
        else
            log_info "Adding new record: ${SUBDOMAIN} ${RECORD_TYPE} ${IP_ADDRESS}"
        fi
    else
        # replace-all mode: only the specified record
        log_warn "Replace-all mode: This will REMOVE all existing records!"
        UPDATED_RECORDS+=("HostName1=${SUBDOMAIN}")
        UPDATED_RECORDS+=("RecordType1=${RECORD_TYPE}")
        UPDATED_RECORDS+=("Address1=${IP_ADDRESS}")
        UPDATED_RECORDS+=("TTL1=${TTL}")
    fi

    log_success "Record set built successfully (${index} total records)"
}

preview_changes() {
    log_info "Preview of DNS changes:"
    echo
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│                  DNS CHANGE PREVIEW                 │${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${BLUE}Domain:${NC} ${DOMAIN}"
    echo -e "${BLUE}Mode:${NC} ${MODE}"
    echo

    if [[ "${MODE}" == "update-single" ]]; then
        echo -e "${GREEN}Records to be updated:${NC}"
        echo "  ${SUBDOMAIN}.${DOMAIN} → ${RECORD_TYPE} → ${IP_ADDRESS} (TTL: ${TTL})"
        echo
        echo -e "${GREEN}Existing records to be preserved:${NC}"
        for record in "${CURRENT_RECORDS[@]}"; do
            IFS='|' read -r hostname type address ttl mxpref <<< "${record}"
            if [[ "${hostname}" != "${SUBDOMAIN}" && ! ("${hostname}" == "@" && "${SUBDOMAIN}" == "@") ]]; then
                echo "  ${hostname}.${DOMAIN} → ${type} → ${address} (TTL: ${ttl})"
            fi
        done
    else
        echo -e "${RED}WARNING: Replace-all mode will DELETE these existing records:${NC}"
        for record in "${CURRENT_RECORDS[@]}"; do
            IFS='|' read -r hostname type address ttl mxpref <<< "${record}"
            echo "  ${hostname}.${DOMAIN} → ${type} → ${address} (TTL: ${ttl})"
        done
        echo
        echo -e "${GREEN}New record set:${NC}"
        echo "  ${SUBDOMAIN}.${DOMAIN} → ${RECORD_TYPE} → ${IP_ADDRESS} (TTL: ${TTL})"
    fi

    echo
    echo -e "${YELLOW}─────────────────────────────────────────────────────${NC}"
    echo
}

apply_dns_changes() {
    log_info "Applying DNS changes to Namecheap..."

    # Ensure evidence directory exists before saving artifacts
    mkdir -p "${EVIDENCE_DIR}"

    # Split domain into SLD and TLD
    local sld="${DOMAIN%.*}"
    local tld="${DOMAIN##*.}"

    local response_file="/tmp/namecheap-setHosts-${TIMESTAMP}.xml"

    # Build curl command
    local -a curl_cmd=(
        curl -sS "${NAMECHEAP_API_URL}"
        --data-urlencode "ApiUser=${API_USER}"
        --data-urlencode "ApiKey=${API_KEY}"
        --data-urlencode "UserName=${API_USER}"
        --data-urlencode "ClientIp=${API_IP}"
        --data-urlencode "Command=namecheap.domains.dns.setHosts"
        --data-urlencode "SLD=${sld}"
        --data-urlencode "TLD=${tld}"
    )

    # Add all record fields
    for field in "${UPDATED_RECORDS[@]}"; do
        curl_cmd+=(--data-urlencode "${field}")
    done

    curl_cmd+=(-o "${response_file}")

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN MODE: Would execute API call but not actually applying changes"
        log_debug "Curl command: ${curl_cmd[*]}"
        return 0
    fi

    # Execute API call
    log_debug "Executing setHosts API call..."

    if ! "${curl_cmd[@]}"; then
        log_error "Failed to apply DNS changes"
        exit 1
    fi

    # Check response status
    if ! grep -q 'Status="OK"' "${response_file}"; then
        log_error "Namecheap API returned error response"
        log_error "Response saved to: ${response_file}"
        cat "${response_file}"
        exit 1
    fi

    log_success "DNS changes applied successfully!"
    log_debug "Response saved to: ${response_file}"

    # Save to evidence
    mkdir -p "${EVIDENCE_DIR}"
    cp "${response_file}" "${EVIDENCE_DIR}/dns-after-${TIMESTAMP}.xml"
}

verify_changes() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY-RUN MODE: Skipping verification"
        return 0
    fi

    log_info "Verifying DNS changes..."
    log_info "Waiting 5 seconds for propagation..."
    sleep 5

    # Fetch records again
    get_current_records

    # Check if our record exists
    local found=false
    for record in "${CURRENT_RECORDS[@]}"; do
        IFS='|' read -r hostname type address ttl mxpref <<< "${record}"
        if [[ "${hostname}" == "${SUBDOMAIN}" && "${type}" == "${RECORD_TYPE}" && "${address}" == "${IP_ADDRESS}" ]]; then
            found=true
            log_success "Verified: ${SUBDOMAIN}.${DOMAIN} → ${RECORD_TYPE} → ${IP_ADDRESS}"
            break
        fi
    done

    if [[ "${found}" == "false" ]]; then
        log_warn "Could not verify record update immediately (may take time to propagate)"
        return 2
    fi
}

# ==============================================================================
# EVIDENCE GENERATION
# ==============================================================================

generate_evidence() {
    log_info "Generating compliance evidence..."

    mkdir -p "${EVIDENCE_DIR}"

    cat > "${EVIDENCE_FILE}" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "operation": "dns-update",
  "domain": "${DOMAIN}",
  "subdomain": "${SUBDOMAIN}",
  "record_type": "${RECORD_TYPE}",
  "target": "${IP_ADDRESS}",
  "ttl": ${TTL},
  "mode": "${MODE}",
  "dry_run": ${DRY_RUN},
  "gcp_project": "${PROJECT_ID}",
  "compliance": {
    "cmmc_controls": ["CM.L2-3.4.2", "AU.L2-3.3.1", "IA.L2-3.5.7"],
    "nist_controls": ["CM-2", "AU-3", "IA-5"]
  },
  "evidence_files": {
    "before": "dns-before-${TIMESTAMP}.xml",
    "after": "dns-after-${TIMESTAMP}.xml",
    "manifest": "dns-update-${TIMESTAMP}.json"
  },
  "status": "success"
}
EOF

    log_success "Evidence saved to: ${EVIDENCE_FILE}"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    log "Starting DNS update process..."
    echo

    # Parse and validate parameters
    parse_arguments "$@"
    validate_parameters

    # Display configuration
    log_info "Configuration:"
    log_info "  Domain: ${DOMAIN}"
    log_info "  Subdomain: ${SUBDOMAIN}"
    log_info "  Record Type: ${RECORD_TYPE}"
    log_info "  Target: ${IP_ADDRESS}"
    log_info "  TTL: ${TTL}"
    log_info "  Mode: ${MODE}"
    log_info "  Dry-run: ${DRY_RUN}"
    echo

    # Fetch credentials if not provided
    if [[ -z "${API_USER}" ]] || [[ -z "${API_KEY}" ]] || [[ -z "${API_IP}" ]]; then
        fetch_secrets_from_gcp
    else
        log_info "Using credentials provided via command line"
    fi
    echo

    # Get current DNS records
    get_current_records
    echo

    # Build updated record set
    build_updated_records
    echo

    # Preview changes
    preview_changes

    # Confirm for replace-all mode
    if [[ "${MODE}" == "replace-all" && "${DRY_RUN}" == "false" ]]; then
        echo -e "${RED}WARNING: This will DELETE all existing DNS records!${NC}"
        read -p "Type 'YES' to confirm: " confirm
        if [[ "${confirm}" != "YES" ]]; then
            log_warn "Operation cancelled by user"
            exit 2
        fi
    fi

    # Apply changes
    apply_dns_changes
    echo

    # Verify changes
    verify_changes
    echo

    # Generate evidence
    generate_evidence
    echo

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_success "Dry-run completed successfully (no changes applied)"
    else
        log_success "DNS update completed successfully!"
        log_info "FQDN: ${SUBDOMAIN}.${DOMAIN}"
        log_info "Type: ${RECORD_TYPE}"
        log_info "Target: ${IP_ADDRESS}"
        log_info "TTL: ${TTL}s"
    fi

    echo
    log_info "Evidence: ${EVIDENCE_FILE}"
}

# Run main function
main "$@"
