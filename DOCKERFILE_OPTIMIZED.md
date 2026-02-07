# Dockerfile.optimized

This directory contains an optimized version of the Dockerfile that reduces image size by combining RUN layers.

## Key Optimizations

### Combined Browser Installation Layer

The main optimization consolidates all browser installations (Signal Desktop, Delta Chat, and Vivaldi) into a **single RUN layer** with unified cleanup:

| Before (Dockerfile) | After (Dockerfile.optimized) |
|---------------------|------------------------------|
| 3 separate RUN layers for each browser install | 1 combined RUN layer for all browsers |
| Multiple `apt-get update` calls (3x) | Single `apt-get update` call |
| Separate cleanup steps per package | Unified cleanup in same layer |

### How It Works

The optimized Dockerfile performs the following operations in one atomic layer:

1. **Download keys and add repos** - GPG keys and apt sources for all browsers
2. **Single apt-get update** - One cache refresh for all package installations
3. **Install all packages** - Signal Desktop, Vivaldi, and Delta Chat in sequence
4. **Update desktop entries** - Add `--no-sandbox` flags for container compatibility
5. **Cleanup everything** - Remove apt sources, temp .deb files, and apt lists

### Benefits

- **Reduced layer count**: Fewer layers = smaller final image
- **Single apt cache**: Avoids multiple package list downloads
- **Internal cleanup**: Files removed in the same layer where they're created, preventing persistence in image history
- **Faster builds**: Reduced I/O from consolidated operations

## Usage

### Build with the optimized Dockerfile

```bash
docker build -f Dockerfile.optimized -t personaldesktop:optimized .
```

### Using with docker-compose

Modify your `docker-compose.yml` to use the optimized file:

```yaml
services:
  personaldesktop:
    build:
      context: .
      dockerfile: Dockerfile.optimized
```

## Differences from Main Dockerfile

| Aspect | Dockerfile | Dockerfile.optimized |
|--------|------------|---------------------|
| Browser install layers | 3 | 1 |
| apt-get update calls | 3 | 1 |
| Signal Desktop | Yes | Yes |
| Delta Chat | Yes | Yes |
| Vivaldi | Yes | Yes |
| Image size | Larger | Smaller |

## When to Use

Use `Dockerfile.optimized` when:

- You want a smaller final image
- Build time optimization is desired
- You're deploying in environments where image size matters (bandwidth, storage)

Use the main `Dockerfile` when:

- You prefer explicit, separate layers for each component
- Debugging layer-specific issues

## Notes

- Both Dockerfiles produce functionally identical containers
- The optimizations focus on build-time efficiency and image size, not runtime behavior
- All security considerations (like `--no-sandbox`) apply to both versions
