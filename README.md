# Personal Desktop Project

A Dockerized personal workspace environment for secure communication and productivity. This project provides a preconfigured Kasm Workspaces-compatible image with XFCE, Signal, Delta Chat, and Vivaldi.

## Features

- **XFCE desktop environment**: Lightweight and customizable desktop experience.
- **Signal Desktop messenger**: End-to-end encrypted messaging.
- **Delta Chat Desktop messenger**: Secure alternative for private communication.
- **Vivaldi web browser**: Privacy-focused browsing with built-in ad-blocking.
- **Security updates applied at build time**: Regular security patches included.
- **Kasm Workspaces integration**: Designed to work seamlessly in Kasm environments.

## Dockerfile Options

This project includes two Dockerfiles with different optimization strategies:

### Standard Dockerfile (Dockerfile)

The default Dockerfile uses separate RUN layers for each browser installation, making it easier to debug but resulting in a larger image.

### Optimized Dockerfile (Dockerfile.optimized)

The optimized version consolidates all browser installations into a **single RUN layer** with unified cleanup:

| Aspect | Dockerfile | Dockerfile.optimized |
|--------|------------|---------------------|
| Browser install layers | 3 separate layers | 1 combined layer |
| apt-get update calls | 3 calls | 1 call |
| Image size | Larger | Smaller |

#### How It Works

The optimized Dockerfile performs all operations in one atomic layer:
1. Downloads GPG keys and adds apt sources for all browsers
2. Runs a single `apt-get update` for all package installations
3. Installs Signal Desktop, Vivaldi, and Delta Chat together
4. Updates desktop entries with `--no-sandbox` flags
5. Cleans up apt sources, temp files, and apt lists in the same layer

#### Usage

```bash
# Build with optimized Dockerfile
docker build -f Dockerfile.optimized -t personaldesktop:optimized .

# Using docker-compose, specify the dockerfile:
services:
  personaldesktop:
    build:
      context: .
      dockerfile: Dockerfile.optimized
```

Both Dockerfiles produce functionally identical containers. Choose the optimized version when image size matters or for faster builds.

## Security Notes

- **Default credentials**: The default VNC password is `password`. Change this in production environments by setting the `VNC_PW` environment variable to a strong password.
- **Sandboxing disabled**: Signal, Delta Chat, and Vivaldi are run with `--no-sandbox` to work within the container. This reduces isolation between applications and the system. For production deployments, consider implementing additional security controls.

## Quick Start

### Testing using Docker Compose

```bash
docker compose up --build
```

Access the desktop at: `http://localhost:6901`
Default password: `password`

### Using Docker directly

Build the image:
```bash
docker build -t personaldesktop .
```

Run the container:
```bash
docker run -d \
  --name personaldesktop \
  -p 6901:6901 \
  -e VNC_PW=password \
  --shm-size=512m \
  personaldesktop
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VNC_PW` | password | VNC/web access password |

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `BASE_TAG` | 1.18.0 | Kasm base image tag |
| `BASE_IMAGE` | core-debian-trixie | Kasm base image name |
| `DELTACHAT_VERSION` | 2.35.0 | Delta Chat version to install |

### Startup Script

The project includes a custom startup script ([custom_startup.sh](custom_startup.sh)) that handles desktop initialization for Kasm Workspaces. It signals when the desktop environment is ready and can be customized for additional launch tasks.

## Usage

1. Open `https://localhost:6901` in your browser
2. Enter the password (default: `password`)
3. Use the desktop shortcuts or application menu to launch Signal or Delta Chat

## Updating Applications

### Manual Update

To update Delta Chat, change the `DELTACHAT_VERSION` build argument and rebuild:

```bash
docker compose build --build-arg DELTACHAT_VERSION=2.36.0
```

Signal and Vivaldi update automatically from their apt repositories on rebuild.

### Automated Update Script

This project includes an automated script ([check-update.sh](check-update.sh)) that checks for updates to all applications and rebuilds the image when newer versions are available:

```bash
./check-update.sh
```

**What it does:**
- Checks Signal Desktop, DeltaChat, Vivaldi, and base image for newer versions
- Updates `Dockerfile` ARG values automatically if updates are found
- Builds the updated image and runs tests to verify functionality
- Deletes the backup file after a successful build

**Build Arguments Managed by Script:**

| Argument | Description |
|----------|-------------|
| `BASE_TAG` | Kasm base image tag (e.g., 1.18.0) |
| `DELTACHAT_VERSION` | Delta Chat version to install |

**Usage Examples:**

```bash
# Check for updates and rebuild if needed
./check-update.sh

# Run with verbose output for troubleshooting
bash -x ./check-update.sh
```

The script creates a `Dockerfile.original` backup before making changes. This backup is automatically deleted after a successful build or when no updates are needed.

## Adding to Kasm Workspaces

To add this image as a workspace in your Kasm deployment:

### Add the workspace in Kasm Admin

1. Log into Kasm as an administrator
2. Navigate to **Workspaces** → **Workspaces**
3. Click **Add Workspace**
4. Fill in the fields below

#### General Settings

| Field | Value |
|-------|-------|
| Friendly Name | `Personal Desktop` |
| Description | `Secure desktop with Signal, Delta Chat, and Vivaldi browser for private communication` |
| Thumbnail URL | `https://upload.wikimedia.org/wikipedia/commons/5/5b/Xfce_logo.svg` |

#### Docker Settings

| Field | Value |
|-------|-------|
| Docker Image | `leberschnitzel/personaldesktop:latest` |
| Docker Registry | `https://index.docker.io/v1/` |
| Cores | `2` |
| Memory (MB) | `4096` |
| GPU Count | `0` |
| CPU Allocation Method | `Inherit` |

5. Click **Save**
