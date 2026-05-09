# jetls-sysimage

Pre-built [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl) sysimages of [aviatesk/JETLS.jl](https://github.com/aviatesk/JETLS.jl) for [mason.nvim](https://github.com/mason-org/mason.nvim) consumption via [ultimatile/mason-jetls-registry](https://github.com/ultimatile/mason-jetls-registry).

## What's published

Each release tag mirrors a JETLS.jl release tag (e.g. `2026-05-06`) and ships one zip per platform:

| Platform | Asset |
|---|---|
| Linux x86_64 | `jetls-sysimage-<tag>-linux-x64.zip` |
| macOS arm64 | `jetls-sysimage-<tag>-macos-arm64.zip` |
| Windows x86_64 | `jetls-sysimage-<tag>-win-x64.zip` |

Each zip contains:

```
bin/jetls{,.cmd}        # shim that launches julia with the sysimage
lib/jetls.{so,dll}      # PackageCompiler-built sysimage
share/jetls/{Project,Manifest}.toml
```

## Requirements at runtime

- Julia 1.12.x in `PATH` (override with `JULIA_BIN`). Sysimages are built on 1.12.6; loading on a different patch may fail.

## How releases happen

1. Renovate watches `aviatesk/JETLS.jl` and bumps `UPSTREAM_VERSION` in this repo when a new tag appears.
2. Merging the bump PR pushes to `main`, triggering [`.github/workflows/release.yaml`](./.github/workflows/release.yaml) on the matching path filter.
3. The workflow runs [`scripts/release.sh`](./scripts/release.sh) on each platform: clones JETLS.jl at the pinned tag, builds a `cpu_target="generic"` sysimage, packages and uploads it under the same tag.
4. Manual builds are also available via `gh workflow run release.yaml -f version=<tag> -f force=true`.
