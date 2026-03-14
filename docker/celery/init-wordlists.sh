#!/bin/bash
# =============================================================================
# init-wordlists.sh - Initialize custom wordlists and nuclei templates
# into mounted Docker volumes at container startup.
#
# This script is called by entrypoint.sh to copy custom assets from the
# baked-in Docker image paths to the shared volumes.
# =============================================================================

set -e

USERNAME=${USERNAME:-rengine}
WORDLIST_DEST="/home/${USERNAME}/wordlists"
NUCLEI_DEST="/home/${USERNAME}/nuclei-templates"
CUSTOM_WORDLIST_SRC="/home/${USERNAME}/wordlists/custom"
CUSTOM_NUCLEI_SRC="/home/${USERNAME}/nuclei-templates/custom"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_section() {
    echo -e "${BLUE}[*] $1${NC}"
}

print_ok() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_err() {
    echo -e "${RED}[-] $1${NC}"
}

# =============================================================================
# WORDLISTS INITIALIZATION
# =============================================================================
init_wordlists() {
    print_section "Initializing custom wordlists..."
    
    if [ -d "${CUSTOM_WORDLIST_SRC}" ]; then
        # Count files
        WORDLIST_COUNT=$(find "${CUSTOM_WORDLIST_SRC}" -type f | wc -l)
        
        if [ "${WORDLIST_COUNT}" -gt 0 ]; then
            print_section "Copying ${WORDLIST_COUNT} custom wordlist files to ${WORDLIST_DEST}..."
            
            # Copy maintaining directory structure
            for wordlist_dir in "${CUSTOM_WORDLIST_SRC}"/*/; do
                if [ -d "${wordlist_dir}" ]; then
                    category=$(basename "${wordlist_dir}")
                    dest_dir="${WORDLIST_DEST}/${category}"
                    mkdir -p "${dest_dir}"
                    
                    file_count=$(find "${wordlist_dir}" -type f | wc -l)
                    cp -n "${wordlist_dir}"* "${dest_dir}/" 2>/dev/null || true
                    print_ok "Copied ${file_count} wordlists to ${category}/"
                fi
            done
            
            # Show summary
            TOTAL_WORDLISTS=$(find "${WORDLIST_DEST}" -type f | wc -l)
            print_ok "Total wordlists available: ${TOTAL_WORDLISTS}"
        else
            print_warn "No custom wordlists found in ${CUSTOM_WORDLIST_SRC}"
        fi
    else
        print_warn "Custom wordlists directory not found: ${CUSTOM_WORDLIST_SRC}"
    fi
}

# =============================================================================
# NUCLEI TEMPLATES INITIALIZATION
# =============================================================================
init_nuclei_templates() {
    print_section "Initializing custom Nuclei templates..."
    
    if [ -d "${CUSTOM_NUCLEI_SRC}" ]; then
        TEMPLATE_COUNT=$(find "${CUSTOM_NUCLEI_SRC}" -name "*.yaml" -o -name "*.yml" | wc -l)
        
        if [ "${TEMPLATE_COUNT}" -gt 0 ]; then
            print_section "Copying ${TEMPLATE_COUNT} custom Nuclei templates to ${NUCLEI_DEST}..."
            
            # Copy maintaining directory structure
            for template_dir in "${CUSTOM_NUCLEI_SRC}"/*/; do
                if [ -d "${template_dir}" ]; then
                    category=$(basename "${template_dir}")
                    dest_dir="${NUCLEI_DEST}/custom-${category}"
                    mkdir -p "${dest_dir}"
                    
                    yaml_count=$(find "${template_dir}" -name "*.yaml" -o -name "*.yml" | wc -l)
                    cp -n "${template_dir}"*.yaml "${dest_dir}/" 2>/dev/null || true
                    cp -n "${template_dir}"*.yml "${dest_dir}/" 2>/dev/null || true
                    print_ok "Copied ${yaml_count} templates to custom-${category}/"
                fi
            done
            
            # Show summary
            TOTAL_TEMPLATES=$(find "${NUCLEI_DEST}" -name "*.yaml" -o -name "*.yml" | wc -l)
            print_ok "Total Nuclei templates available: ${TOTAL_TEMPLATES}"
        else
            print_warn "No custom Nuclei templates found in ${CUSTOM_NUCLEI_SRC}"
        fi
    else
        print_warn "Custom Nuclei templates directory not found: ${CUSTOM_NUCLEI_SRC}"
    fi
}

# =============================================================================
# NUCLEI TEMPLATE UPDATE (optional - only if internet available)
# =============================================================================
update_nuclei_templates() {
    if [ "${UPDATE_NUCLEI_TEMPLATES:-0}" = "1" ]; then
        print_section "Updating Nuclei templates from official repository..."
        if command -v nuclei &>/dev/null; then
            nuclei -update-templates -update-template-dir "${NUCLEI_DEST}" 2>&1 | tail -5 || true
            print_ok "Nuclei templates updated"
        else
            print_warn "nuclei binary not found, skipping template update"
        fi
    fi
}

# =============================================================================
# WORDLIST VALIDATION
# =============================================================================
validate_wordlists() {
    print_section "Validating critical wordlists..."
    
    critical_wordlists=(
        "${WORDLIST_DEST}/dicc.txt"
        "${WORDLIST_DEST}/fuzz-Bo0oM.txt"
        "${WORDLIST_DEST}/deepmagic.com-prefixes-top50000.txt"
    )
    
    all_ok=true
    for wl in "${critical_wordlists[@]}"; do
        if [ -f "${wl}" ]; then
            lines=$(wc -l < "${wl}")
            print_ok "$(basename "${wl}") - ${lines} entries"
        else
            print_warn "Missing: $(basename "${wl}")"
            all_ok=false
        fi
    done
    
    if [ "${all_ok}" = false ]; then
        print_warn "Some critical wordlists are missing. Recon may be limited."
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo ""
    echo "======================================"
    echo "  reNgine-ng Asset Initialization"
    echo "======================================"
    echo ""
    
    init_wordlists
    echo ""
    init_nuclei_templates
    echo ""
    update_nuclei_templates
    echo ""
    validate_wordlists
    echo ""
    print_ok "Asset initialization complete!"
    echo ""
}

main "$@"
