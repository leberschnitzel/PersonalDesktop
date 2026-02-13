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

# Get version of installed package from a container (not running, just instantiated)
get_container_version() {
    local app_name="$1"
    local container_id

    # Create the container with a sleep command to keep it alive for exec
    container_id=$(docker create leberschnitzel/personaldesktop:latest "/bin/sleep infinity" 2>/dev/null)

    if [ -n "$container_id" ]; then
        # Start the container in background
        docker start "$container_id" >/dev/null 2>&1 || true

        # Give it a moment to fully start
        sleep 2

        # Use dpkg-query from within the container to get version info reliably
        local version=""
        version=$(docker exec "$container_id" dpkg-query --showformat='${Version}' --show "$app_name" 2>/dev/null) || true

        # Stop and remove the container
        docker stop "$container_id" >/dev/null 2>&1 || true
        docker rm "$container_id" >/dev/null 2>&1 || true

        if [ -n "$version" ]; then
            echo "$version"
        fi
    fi
}

# Parse Dockerfile ARGs (strip ANSI codes)
parse_arg() {
    local arg_name="$1"
    grep "^ARG ${arg_name}" "$DOCKERFILE" | sed "s/.*=.*\"\([^\"]*\)\".*/\1/" | head -1 | sed 's/\x1b\[[0-9;]*m//g'
}

# Check Signal Desktop version from apt repo
check_signal_version() {
    local json_url="https://updates.signal.org/desktop/apt/dists/xenial/main/binary-amd64/Packages.gz"
    if command -v curl &> /dev/null; then
        local result=$(curl -sSL "$json_url" 2>/dev/null | zcat 2>/dev/null | grep -A10 "^Package: signal-desktop$" | head -15 | grep "^Version:" | awk '{print $2}' | sed 's/\x1b\[[0-9;]*m//g' | head -1)
        echo "$result"
    else
        log_warning "curl not available, skipping Signal version check"
        return 1
    fi
}

# Check Vivaldi version from apt repo
check_vivaldi_version() {
    local repo_url="https://repo.vivaldi.com/archive/deb/dists/stable/main/binary-amd64/Packages.gz"
    if command -v curl &> /dev/null; then
        local result=$(curl -sSL "$repo_url" 2>/dev/null | zcat 2>/dev/null | grep "^Package: vivaldi-stable" -A10 | head -15 | grep "Version:" | awk '{print $2}' | sed 's/\x1b\[[0-9;]*m//g' | head -1)
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

# Extract installed versions from a container after a build
extract_versions_from_build() {
    local image_name="$1"

    # Create and start container temporarily to extract versions
    local container_id=$(docker create "$image_name" "/bin/sleep infinity" 2>/dev/null)
    if [ -n "$container_id" ]; then
        docker start "$container_id" >/dev/null 2>&1 || true
        sleep 2

        # Extract versions using dpkg-query
        local signal_ver=$(docker exec "$container_id" dpkg-query --showformat='${Version}' --show signal-desktop 2>/dev/null || echo "")
        local vivaldi_ver=$(docker exec "$container_id" dpkg-query --showformat='${Version}' --show vivaldi-stable 2>/dev/null || echo "")

        # Stop and remove the container
        docker stop "$container_id" >/dev/null 2>&1 || true
        docker rm "$container_id" >/dev/null 2>&1 || true

        if [ -n "$signal_ver" ]; then
            echo "SIGNAL_VERSION=$signal_ver"
        fi
        if [ -n "$vivaldi_ver" ]; then
            echo "VIVALDI_VERSION=$vivaldi_ver"
        fi
    fi
}

# Build and update Dockerfile with detected versions
build_and_update_versions() {
    local temp_image="kasm-temp-$(date +%Y%m%d-%H%M%S)"

    log_info "Building temporary image to detect installed versions..."

    if ! docker build -f "$DOCKERFILE" -t "$temp_image" . 2>&1 | tee /tmp/docker-build.log; then
        log_error "Build failed!"
        return 1
    fi

    log_success "Build successful! Extracting versions from running container..."

    # Extract versions and update Dockerfile
    local versions=$(extract_versions_from_build "$temp_image")

    if [ -n "$versions" ]; then
        log_info "Detected versions from build:"
        echo "$versions" | while read line; do
            local key=$(echo "$line" | cut -d= -f1)
            local value=$(echo "$line" | cut -d= -f2-)
            log_success "  $key: $value"

            # Update Dockerfile with detected version
            if grep -q "^ARG ${key}=" "$DOCKERFILE"; then
                update_dockerfile_arg "$key" "$value"
            fi
        done
    else
        log_warning "Could not extract versions from build, using Dockerfile values"
    fi

    # Cleanup temp image
    docker rmi -f "$temp_image" 2>/dev/null || true
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

            # Get versions and update Dockerfile for future builds
            local signal_ver=$(docker exec "$container_name" dpkg-query --showformat='${Version}' --show signal-desktop 2>/dev/null || echo "")
            local vivaldi_ver=$(docker exec "$container_name" dpkg-query --showformat='${Version}' --show vivaldi-stable 2>/dev/null || echo "")

            if [ -n "$signal_ver" ]; then
                log_info "Detected Signal version in running container: $signal_ver"
                # Don't update SIGNAL_VERSION here since it's fetched during build from apt repo
            fi
            if [ -n "$vivaldi_ver" ]; then
                log_info "Detected Vivaldi version in running container: $vivaldi_ver"
                # Vivaldi doesn't have an ARG yet, so we just report it
            fi
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

# Clean up temporary files and resources
cleanup() {
    log_info "Cleaning up temporary files..."

    # Remove backup files created during updates
    rm -f "${DOCKERFILE}.bak" 2>/dev/null || true

    # Remove original backup if it exists (from a previous run)
    if [ -f "${DOCKERFILE}.original" ]; then
        rm -f "${DOCKERFILE}.original"
        log_info "Removed ${DOCKERFILE}.original"
    fi

    # Clean up any stopped containers from testing
    docker container prune -f 2>/dev/null || true

    # Clean up dangling images (but not our test image which we want to inspect)
    docker image prune -f 2>/dev/null || true

    log_success "Cleanup completed!"
}

# Get installed versions from a running container
get_installed_versions() {
    local container_name="$1"

    local signal_ver=$(docker exec "$container_name" dpkg-query --showformat='${Version}' --show signal-desktop 2>/dev/null || echo "")
    local vivaldi_ver=$(docker exec "$container_name" dpkg-query --showformat='${Version}' --show vivaldi-stable 2>/dev/null || echo "")
    local deltachat_ver=$(docker exec "$container_name" dpkg-query --showformat='${Version}' --show deltachat-desktop 2>/dev/null || echo "")

    echo "SIGNAL_VER=$signal_ver"
    echo "VIVALDI_VER=$vivaldi_ver"
    echo "DELTACHAT_VER=$deltachat_ver"
}

# Parse version string to remove any distro suffix (e.g., 1.2.3-1mmj1 -> 1.2.3)
normalize_version() {
    echo "$1" | sed 's/-[0-9]*$//'
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

    # Step 1: Check online for latest versions
    echo ""
    log_info "Step 1: Checking online for newer versions..."

    local delta_latest_raw=$(check_deltachat_version)
    local delta_latest=$(echo "$delta_latest_raw" | sed 's/^v//')
    local signal_latest=$(check_signal_version)
    local vivaldi_latest=$(check_vivaldi_version)

    # Normalize versions for comparison
    local delta_latest_norm=$(normalize_version "$delta_latest")
    local signal_latest_norm=$(normalize_version "$signal_latest")
    local vivaldi_latest_norm=$(normalize_version "$vivaldi_latest")

    echo ""
    log_success "Latest online - DeltaChat: $delta_latest, Signal: $signal_latest, Vivaldi: $vivaldi_latest"

    # Step 2: Pull the current image from Docker Hub and check versions
    echo ""
    log_info "Step 2: Pulling leberschnitzel/personaldesktop:latest from Docker Hub..."

    local needs_update=false

    if docker pull leberschnitzel/personaldesktop:latest 2>/dev/null; then
        log_success "Successfully pulled latest image"

        # Create container from pulled image to check installed versions
        echo ""
        log_info "Checking currently installed versions in pulled image..."
        local pull_container_id=$(docker create leberschnitzel/personaldesktop:latest "/bin/sleep infinity" 2>/dev/null)

        if [ -n "$pull_container_id" ]; then
            docker start "$pull_container_id" >/dev/null 2>&1 || true
            sleep 3

            local installed_versions=$(get_installed_versions "$pull_container_id")

            # Parse installed versions
            local delta_current=$(echo "$installed_versions" | grep "DELTACHAT_VER=" | cut -d= -f2)
            local signal_current=$(echo "$installed_versions" | grep "SIGNAL_VER=" | cut -d= -f2)
            local vivaldi_current=$(echo "$installed_versions" | grep "VIVALDI_VER=" | cut -d= -f2)

            # Normalize current versions for comparison
            local delta_current_norm=$(normalize_version "$delta_current")
            local signal_current_norm=$(normalize_version "$signal_current")
            local vivaldi_current_norm=$(normalize_version "$vivaldi_current")

            log_success "Currently installed in Docker Hub image: DeltaChat: $delta_current, Signal: $signal_current, Vivaldi: $vivaldi_current"

            # Stop and remove the test container
            docker stop "$pull_container_id" >/dev/null 2>&1 || true
            docker rm "$pull_container_id" >/dev/null 2>&1 || true

            echo ""
            log_info "Step 3: Comparing versions..."

            # Compare DeltaChat
            if [ -n "$delta_latest_norm" ] && [ -n "$delta_current_norm" ] && [ "$delta_latest_norm" != "$delta_current_norm" ]; then
                log_warning "DeltaChat needs update: online=$delta_latest, installed=$delta_current"
                needs_update=true
            else
                log_success "DeltaChat is up to date ($delta_current)"
            fi

            # Compare Signal
            if [ -n "$signal_latest_norm" ] && [ -n "$signal_current_norm" ] && [ "$signal_latest_norm" != "$signal_current_norm" ]; then
                log_warning "Signal needs update: online=$signal_latest, installed=$signal_current"
                needs_update=true
            else
                log_success "Signal is up to date ($signal_current)"
            fi

            # Compare Vivaldi
            if [ -n "$vivaldi_latest_norm" ] && [ -n "$vivaldi_current_norm" ] && [ "$vivaldi_latest_norm" != "$vivaldi_current_norm" ]; then
                log_warning "Vivaldi needs update: online=$vivaldi_latest, installed=$vivaldi_current"
                needs_update=true
            else
                log_success "Vivaldi is up to date ($vivaldi_current)"
            fi

        else
            log_error "Failed to create container from pulled image"
            exit 1
        fi

    else
        log_info "No existing image on Docker Hub - will build fresh"
        needs_update=true
    fi

    echo ""
    echo "========================================"

    # Step 4: Update Dockerfile and rebuild if needed
    if [ "$needs_update" = true ]; then
        log_info "Step 4: Updates detected. Updating Dockerfile..."

        # Get current versions from Dockerfile for comparison
        local deltafile_current=$(parse_arg "DELTACHAT_VERSION")

        # Update DeltaChat version in Dockerfile if different from what will be installed
        if [ -n "$delta_latest" ] && [ -n "$deltafile_current" ] && [ "$delta_latest" != "$deltafile_current" ]; then
            log_info "Updating DELTACHAT_VERSION: $deltafile_current -> $delta_latest"
            update_dockerfile_arg "DELTACHAT_VERSION" "$delta_latest"
        else
            log_success "DeltaChat version in Dockerfile is current ($deltafile_current)"
        fi

        # Build the new image as leberschnitzel/personaldesktop:latest
        local build_image="leberschnitzel/personaldesktop:latest"
        echo ""
        log_info "Step 5: Building Docker image $build_image..."

        if docker build -f "$DOCKERFILE" -t "$build_image" . 2>&1 | tee /tmp/docker-build.log; then
            log_success "Build successful!"

            # Quick test to verify the image works
            local test_container="test-$(date +%s)"
            if docker create --name "$test_container" --rm "$build_image" /bin/sleep 3 >/dev/null 2>&1; then
                sleep 2
                log_success "Container test passed!"
            fi
            docker rm -f "$test_container" 2>/dev/null || true

            echo ""
            log_success "Image ready for deployment!"
            echo ""
            echo "To push the updated image, run:"
            echo "  docker push $build_image"
            echo ""

        else
            log_error "Build failed!"
            if [ -f "${DOCKERFILE}.original" ]; then
                cp "${DOCKERFILE}.original" "$DOCKERFILE"
            fi
            exit 1
        fi

    else
        # No updates available
        echo ""
        log_success "All components are already up to date!"
        echo ""
        log_info "No rebuild needed. Image is ready to use."
    fi

    # Cleanup temp files but keep the latest image
    echo ""
    cleanup

    echo "========================================"
}

# Run main function
main "$@"