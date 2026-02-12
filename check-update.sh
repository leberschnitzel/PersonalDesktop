#!/bin/bash

set -e

DOCKERFILE="Dockerfile"
BACKUP_FILE="${DOCKERFILE}.bak"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse Dockerfile ARGs (strip ANSI codes)
parse_arg() {
    local arg_name="$1"
    grep "^ARG ${arg_name}" "$DOCKERFILE" | sed "s/.*=.*\"\([^\"]*\)\".*/\1/" | head -1 | sed 's/\x1b\[[0-9;]*m//g'
}

# Check Signal Desktop version
check_signal_version() {
    log_info "Checking Signal Desktop latest version..."
    local json_url="https://updates.signal.org/desktop/apt/dists/xenial/main/binary-amd64/Packages.gz"
    if command -v curl &> /dev/null; then
        local result=$(curl -sSL "$json_url" 2>/dev/null | zcat 2>/dev/null | grep -A5 "Package: signal-desktop" | head -10 | grep Version | awk '{print $2}' | sed 's/\x1b\[[0-9;]*m//g')
        echo "$result"
    else
        log_warning "curl not available, skipping Signal version check"
        return 1
    fi
}

# Check Vivaldi version
check_vivaldi_version() {
    log_info "Checking Vivaldi latest version..."
    local repo_url="https://repo.vivaldi.com/archive/deb/dists/stable/main/binary-amd64/Packages.gz"
    if command -v curl &> /dev/null; then
        local result=$(curl -sSL "$repo_url" 2>/dev/null | zcat 2>/dev/null | grep "^Package: vivaldi-stable" -A10 | head -15 | grep Version | awk '{print $2}' | sed 's/\x1b\[[0-9;]*m//g')
        echo "$result"
    else
        log_warning "curl not available, skipping Vivaldi version check"
        return 1
    fi
}

# Check DeltaChat version - parses the HTML index page to find latest version directory
check_deltachat_version() {
    local base_url="https://download.delta.chat/desktop/"
    if command -v curl &> /dev/null; then
        # Get the directory listing and find the latest v*.*.* directory
        local result=$(curl -sSL "$base_url" 2>/dev/null | grep -oP 'href="v[0-9]+\.[0-9]+\.[0-9]+/"' | sed 's/href="v//;s/\/".*//' | sort -V | tail -1)
        # Add the "v" prefix back
        if [ -n "$result" ]; then
            echo "v$result"
        fi
    else
        log_warning "curl not available, skipping DeltaChat version check"
        return 1
    fi
}

# Check base image for newer tags
check_base_image() {
    local base_image="kasmweb/core-debian-trixie"
    local current_tag=$(parse_arg "BASE_TAG")

    log_info "Checking base image: ${base_image}:${current_tag}"

    if command -v curl &> /dev/null; then
        # Try Docker Hub API to list tags
        local tags=$(curl -sSL "https://hub.docker.com/v2/repositories/kasmweb/core-debian-trixie/tags?page_size=100" 2>/dev/null | grep -oP '"name"\s*:\s*"\K[^"]+' || true)

        if [ -n "$tags" ]; then
            # Filter for trixie tags and sort by version
            local latest_tag=$(echo "$tags" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)

            if [ -n "$latest_tag" ] && [ "$latest_tag" != "$current_tag" ]; then
                echo "$latest_tag"
            fi
        else
            log_warning "Could not fetch latest tag, using current: ${current_tag}"
        fi
    else
        log_warning "curl not available, skipping base image version check"
    fi
}

# Update a single ARG in the Dockerfile
update_dockerfile_arg() {
    local param_name="$1"
    local new_value="$2"

    if [ -z "$new_value" ]; then
        log_error "No value provided for $param_name"
        return 1
    fi

    # Restore from original backup first if it exists
    if [ -f "${DOCKERFILE}.original" ]; then
        cp "${DOCKERFILE}.original" "$DOCKERFILE"
    else
        cp "$DOCKERFILE" "${DOCKERFILE}.bak"
    fi

    local current_value=$(parse_arg "$param_name")

    if [ "$current_value" == "$new_value" ]; then
        log_info "No update needed for $param_name (already at $new_value)"
        return 0
    fi

    log_info "Updating $param_name: $current_value -> $new_value"

    # Escape special characters for sed
    local escaped_old=$(printf '%s\n' "$current_value" | sed 's/[&/\]/\\&/g')
    local escaped_new=$(printf '%s\n' "$new_value" | sed 's/[&/\]/\\&/g')

    # Replace the value in the ARG line
    sed -i "s/^ARG ${param_name}=.*/ARG ${param_name}=\"${escaped_new}\"/" "$DOCKERFILE"
}

build_and_test() {
    local test_image="kasm-test:updated-$(date +%Y%m%d-%H%M%S)"

    log_info "Building Docker image: $test_image"

    if ! docker build -f "$DOCKERFILE" -t "$test_image" . 2>&1 | tee /tmp/docker-build.log; then
        log_error "Build failed!"
        # Restore from original if backup exists
        if [ -f "${DOCKERFILE}.original" ]; then
            cp "${DOCKERFILE}.original" "$DOCKERFILE"
        fi
        return 1
    fi

    log_success "Build successful!"

    local container_name="kasm-test-$(date +%s)"

    log_info "Testing container..."

    if docker run -d --name "$container_name" --rm "$test_image" 2>/dev/null; then
        sleep 3

        # Check if desktop files exist
        if docker exec "$container_name" test -f /home/kasm-user/Desktop/signal-desktop.desktop && \
           docker exec "$container_name" test -f /home/kasm-user/Desktop/deltachat-desktop.desktop && \
           docker exec "$container_name" test -f /home/kasm-user/Desktop/vivaldi-stable.desktop; then
            log_success "All desktop files present!"
        else
            log_warning "Some desktop files may be missing"
        fi

        # Check if apps are installed
        local apps_ok=true
        for app in signal-desktop deltachat-desktop vivaldi-stable; do
            if ! docker exec "$container_name" which "$app" &>/dev/null 2>&1; then
                apps_ok=false
                log_warning "App $app not found in PATH"
            fi
        done

        if [ "$apps_ok" = true ]; then
            log_success "All applications installed successfully!"
        fi
    else
        # Try again with different entrypoint for debugging
        docker run -d --name "$container_name" "$test_image" /bin/bash &
        sleep 5

        if docker ps | grep -q "$container_name"; then
            log_info "Container started, checking installed packages..."

            docker exec "$container_name" which signal-desktop deltachat-desktop vivaldi-stable || true
        fi
    fi

    # Cleanup
    docker rm -f "$container_name" 2>/dev/null || true
    docker rmi -f "$test_image" 2>/dev/null || true

    log_success "Test completed!"
}

# Main logic
main() {
    echo "========================================"
    echo "Dockerfile Update & Build Script"
    echo "========================================"

    # Create initial backup if it doesn't exist
    if [ ! -f "${DOCKERFILE}.original" ]; then
        cp "$DOCKERFILE" "${DOCKERFILE}.original"
        log_info "Created original backup: ${DOCKERFILE}.original"
    fi

    local updated=false

    # Check Signal Desktop version
    echo ""
    signal_latest=$(check_signal_version)
    signal_current=$(parse_arg "SIGNAL_VERSION")

    if [ -n "$signal_latest" ] && [ "$signal_latest" != "$signal_current" ]; then
        log_warning "New Signal version available: $signal_latest (current: $signal_current)"
        update_dockerfile_arg "SIGNAL_VERSION" "$signal_latest"
        updated=true
    else
        log_success "Signal Desktop is up to date ($signal_current)"
    fi

    # Check DeltaChat version - normalize by stripping 'v' prefix for comparison
    echo ""
    delta_latest_raw=$(check_deltachat_version)
    # Strip 'v' prefix if present (Dockerfile uses 2.35.0, not v2.35.0)
    delta_latest=$(echo "$delta_latest_raw" | sed 's/^v//')
    delta_current=$(parse_arg "DELTACHAT_VERSION")

    if [ -n "$delta_latest" ] && [ "$delta_latest" != "$delta_current" ]; then
        log_warning "New DeltaChat version available: $delta_latest (current: $delta_current)"
        update_dockerfile_arg "DELTACHAT_VERSION" "$delta_latest"
        updated=true
    else
        log_success "DeltaChat is up to date ($delta_current)"
    fi

    # Check Vivaldi version
    echo ""
    vivaldi_latest=$(check_vivaldi_version)

    if [ -n "$vivaldi_latest" ]; then
        log_info "Latest Vivaldi: $vivaldi_latest"
    fi

    # Check base image tag
    echo ""
    base_tag=$(parse_arg "BASE_TAG")
    base_image_name="kasmweb/core-debian-trixie"

    latest_base_tag=$(check_base_image)

    if [ -n "$latest_base_tag" ] && [ "$latest_base_tag" != "$base_tag" ]; then
        log_warning "New base image tag available: $latest_base_tag (current: $base_tag)"
        update_dockerfile_arg "BASE_TAG" "$latest_base_tag"
        updated=true
    else
        if [ -n "$latest_base_tag" ] && [ "$latest_base_tag" == "$base_tag" ]; then
            log_success "Base image is up to date (${base_image_name}:${base_tag})"
        fi
    fi

    echo ""
    echo "========================================"

    if [ "$updated" = true ]; then
        log_info "Dockerfile was modified. Starting build and test..."

        # Verify the Dockerfile is valid before building
        if grep -q "^FROM kasmweb/" "$DOCKERFILE"; then
            build_and_test

            echo ""
            log_success "Update process completed!"

            # Show summary of changes
            if [ -f "${DOCKERFILE}.original" ]; then
                echo ""
                echo "Changes made (diff):"
                diff -u "${DOCKERFILE}.original" "$DOCKERFILE" || true

                # Delete the original backup after successful build
                rm -f "${DOCKERFILE}.original"
                log_info "Deleted ${DOCKERFILE}.original (build successful)"
            fi
        else
            log_error "Dockerfile appears to be corrupted!"
            if [ -f "${DOCKERFILE}.original" ]; then
                cp "${DOCKERFILE}.original" "$DOCKERFILE"
            fi
            exit 1
        fi
    else
        echo ""
        log_success "All components are already up to date!"

        # Delete the original backup when no update is needed
        if [ -f "${DOCKERFILE}.original" ]; then
            rm -f "${DOCKERFILE}.original"
            log_info "Deleted ${DOCKERFILE}.original (no update needed)"
        fi
    fi

    echo "========================================"
}

# Run main function
main "$@"
