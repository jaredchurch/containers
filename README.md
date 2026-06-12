# containers

Dev Container configuration and Docker base-image factory for Python 3.10 + Node.js development environments with [OpenCode AI](https://opencode.ai).

## Repository Structure

```
.
├── .devcontainer/
│   ├── devcontainer.json          # Dev Container definition (Ubuntu 24.04)
│   └── features/opencode/
│       ├── devcontainer-feature.json  # OpenCode feature metadata
│       └── install.sh                 # Installs opencode-ai via npm
├── .github/workflows/
│   └── build-base.yml             # CI: builds & pushes base image to GHCR
├── base-image/
│   └── Dockerfile.base            # Custom base image (Python 3.10 + Node.js)
├── scripts/
│   └── build.sh                   # Helper to build any Dockerfile in the repo
├── AGENTS.md                      # Instructions for AI coding agents
└── README.md
```

## Getting Started

Open this repository in VS Code with the Dev Containers extension (or in GitHub Codespaces). The dev container will:

- Start from `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`
- Install the `opencode-ai` CLI tool globally
- Add the Docker VS Code extension

## Base Image

[`base-image/Dockerfile.base`](base-image/Dockerfile.base) defines a reusable image based on `python:3.10-slim-trixie` with Node.js and npm installed. Use it as a base for downstream Dockerfiles:

```dockerfile
FROM ghcr.io/<owner>/base:latest
```

## CI/CD

The [`build-base.yml`](.github/workflows/build-base.yml) workflow automatically builds and pushes the base image to the GitHub Container Registry on every push to `main` that touches `base-image/` or the workflow itself. Published as `ghcr.io/<owner>/base:latest`.

## Local Build

Use the build helper to build any Dockerfile in the repo:

```sh
./scripts/build.sh base-image/Dockerfile.base
./scripts/build.sh -t my-tag base-image/Dockerfile.base
```

See `./scripts/build.sh --help` for details.

## AI Agent Instructions

See [`AGENTS.md`](AGENTS.md) for instructions used by AI coding assistants working in this repository.
