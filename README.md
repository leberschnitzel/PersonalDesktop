# PersonalDesktop

A Kasm Workspaces desktop image based on Debian Trixie with Signal and Delta Chat pre-installed.

## Features

- XFCE desktop environment
- Signal Desktop messenger
- Delta Chat Desktop messenger
- Optimized for small image size

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
docker build -t personal-desktop .
```

Run the container:
```bash
docker run -d \
  --name personal-desktop \
  -p 6901:6901 \
  -e VNC_PW=password \
  --shm-size=512m \
  personal-desktop
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

Signal updates automatically from its apt repository on rebuild.
