# PersonalDesktop

A Kasm Workspaces desktop image based on Debian Trixie with secure messaging apps and a web browser pre-installed.

## Features

- XFCE desktop environment
- Signal Desktop messenger
- Delta Chat Desktop messenger
- Vivaldi web browser
- Security updates applied at build time

## Quick Start

### Using Docker Compose (recommended)

```bash
docker compose up --build
```

Access the desktop at: `https://localhost:6901`
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

## Usage

1. Open `https://localhost:6901` in your browser
2. Enter the password (default: `password`)
3. Use the desktop shortcuts or application menu to launch Signal or Delta Chat

## Updating Applications

To update Delta Chat, change the `DELTACHAT_VERSION` build argument and rebuild:

```bash
docker compose build --build-arg DELTACHAT_VERSION=2.36.0
```

Signal and Vivaldi update automatically from their apt repositories on rebuild.

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
| Memory (MB) | `2768` |
| GPU Count | `0` |
| CPU Allocation Method | `Inherit` |

#### Optional Settings

| Field | Value |
|-------|-------|
| Persistent Profile Path | `/mnt/kasm_profiles/PersonalDesktop/{username}` *(if you want to persist user data)* |

5. Click **Save**
