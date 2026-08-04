# containers

Docker images published to the GitHub Container Registry (GHCR), built and versioned by GitHub Actions.

## How this repo works

Every image lives in its own directory and follows the same pattern:

- A `Dockerfile.<name>` (e.g. `Dockerfile.base`, `Dockerfile.airflow`) defines the image.
- A thin workflow `build-<name>.yml` calls the shared reusable workflow `_build-container-dev.yml`, passing the image name, build context, and Dockerfile path.

The reusable workflow handles login, tag generation, and the build/push for every image, so the per-image workflows stay tiny.

## Build & publish model

Each image is built and pushed on every push that touches its directory or its workflow, and can also be triggered manually.

| Trigger | Branch | Tags pushed |
| --- | --- | --- |
| Push | any branch except `main` | `dev` |
| Push | `main` | `latest` + `vN` (next version) |
| Manual dispatch | any | `dev` by default; check **`dev_mode`** to force dev-only even on `main` |

Version tags are auto-incremented from the highest existing `vN` tag on the package.

## Adding a new image

1. Create a directory with a `Dockerfile.<name>`.
2. Add a `build-<name>.yml` workflow that calls the reusable workflow:

   ```yaml
   jobs:
     build:
       permissions:
         contents: read
         packages: write
       uses: ./.github/workflows/_build-container-dev.yml
       with:
         image_name: <name>
         context: ./<name>
         dockerfile: ./<name>/Dockerfile.<name>
         dev_mode: ${{ github.event_name == 'workflow_dispatch' && inputs.dev_mode }}
       secrets: inherit
   ```

3. Push the branch; the `dev` tag is published automatically. Merging to `main` publishes `latest` + the next `vN`.

For first-time publishing, grant the repository write access on the package: **Package settings → Manage Actions access → add this repository with the Write role.**

## Building locally

Use the build helper to build any Dockerfile in the repo:

```sh
./scripts/build.sh base-image/Dockerfile.base
./scripts/build.sh -t my-tag base-image/Dockerfile.base
```

See `./scripts/build.sh --help` for details.

## Dev container

Open this repository in VS Code with the Dev Containers extension or in GitHub Codespaces. The dev container installs the `opencode-ai` CLI and the Docker VS Code extension.

## AI agent instructions

See [`AGENTS.md`](AGENTS.md) for instructions used by AI coding assistants working in this repository.
