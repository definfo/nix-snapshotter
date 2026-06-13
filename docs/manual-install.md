# Manual Installation

This guide covers installing and configuring nix-snapshotter on non-NixOS
Linux distros where NixOS or Home Manager modules are not available.

## Prerequisites

- Linux with kernel ≥ 5.11 (overlayfs & bind mount support)
- Nix — [Determinate Nix Installer](https://zero-to-nix.com/start/install)
  or [official multi-user install](https://nixos.org/download)
- containerd ≥ 1.7 (with proxy plugin support)
- runc or another OCI runtime

> Note: nix-snapshotter is Linux-only. macOS users should use a Linux VM.

## 1. Build nix-snapshotter

### Option A: Build with Nix (recommended)

```sh
nix build github:pdtpartners/nix-snapshotter
# The binary is at ./result/bin/nix-snapshotter
```

### Option B: Build from source with Go

```sh
git clone https://github.com/pdtpartners/nix-snapshotter.git
cd nix-snapshotter
go build -o /usr/local/bin/nix-snapshotter .
go build -o /usr/local/bin/nix2container ./cmd/nix2container
```

### Option C: Download a release binary

Check [GitHub Releases](https://github.com/pdtpartners/nix-snapshotter/releases)
for pre-built binaries.

## 2. Configuration

Create a config file at `/etc/nix-snapshotter/config.toml`:

```toml
# Socket path for the gRPC proxy plugin.
address = "/run/nix-snapshotter/nix-snapshotter.sock"

# Directory for persistent data (snapshots, metadata, GC roots).
root = "/var/lib/containerd/io.containerd.snapshotter.v1.nix"

# Optional: external nix builder program that receives (outLink, storePath) args.
# Defaults to `nix-store --realise [--add-root outLink] storePath`.
# external_builder = "/usr/local/bin/nix-snapshotter-builder"

[image_service]
enable = true
containerd_address = "/run/containerd/containerd.sock"
```

### Rootless configuration

For rootless mode, nix-snapshotter automatically detects non-root execution and
defaults to XDG-compliant paths. Create
`~/.config/nix-snapshotter/config.toml`:

```toml
# When running as non-root, defaults are:
#   address         = /run/user/<UID>/containerd/nix-snapshotter.sock
#   root            = ~/.local/share/containerd/io.containerd.snapshotter.v1.nix
#   containerd_address = /run/user/<UID>/containerd/containerd.sock
#
# You only need a config file if overriding defaults.

[image_service]
enable = true
# containerd_address = "/run/user/1000/containerd/containerd.sock"
```

> The rootless defaults use `$XDG_DATA_HOME` (defaulting to `~/.local/share`)
> for the data directory and `/run/user/<UID>` for sockets, following the
> [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).

## 3. Configure containerd

Add the nix proxy plugin to your containerd configuration
(`/etc/containerd/config.toml`):

```toml
version = 2

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "nix"

[[plugins."io.containerd.transfer.v1.local".unpack_config]]
  platform = "linux/amd64"
  snapshotter = "nix"

[proxy_plugins.nix]
  type = "snapshot"
  address = "/run/nix-snapshotter/nix-snapshotter.sock"
```

For rootless containerd, adjust the socket paths accordingly to match the
paths under your `$XDG_RUNTIME_DIR`.

## 4. systemd Service

### Rootful

Install the systemd unit file:

```sh
sudo cp contrib/systemd/nix-snapshotter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nix-snapshotter
```

### Rootless

```sh
mkdir -p ~/.config/systemd/user/
cp contrib/systemd/nix-snapshotter-rootless.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now nix-snapshotter
```

### Verify

```sh
# Rootful
sudo systemctl status nix-snapshotter

# Rootless
systemctl --user status nix-snapshotter
```

## 5. Verify containerd integration

Restart containerd after configuring the proxy plugin:

```sh
# Rootful
sudo systemctl restart containerd

# Rootless
systemctl --user restart containerd
```

Test with nerdctl:

```sh
# Build a nix image with nix2container and load it
nix build github:pdtpartners/nix-snapshotter#image-hello
nix2container --address /run/containerd/containerd.sock load ./result

# Run with nerdctl (NixOS / rootful)
sudo nerdctl run ghcr.io/pdtpartners/hello

# Run with nerdctl (rootless)
CONTAINERD_ADDRESS=$XDG_RUNTIME_DIR/containerd/containerd.sock \
  CONTAINERD_SNAPSHOTTER=nix \
  nerdctl run ghcr.io/pdtpartners/hello
```

## 6. Using with Kubernetes (k3s)

For k3s, configure the kubelet to use nix-snapshotter as the image service:

```sh
k3s server \
  --container-runtime-endpoint unix:///run/containerd/containerd.sock \
  --image-service-endpoint unix:///run/nix-snapshotter/nix-snapshotter.sock
```

## Troubleshooting

### `nix-store not found in PATH`

The nix-snapshotter daemon requires `nix-store` to be available in PATH for
substituting and creating GC roots. Make sure the Nix profile is sourced in
the service environment.

For multi-user Nix installations, add to the service unit:

```ini
[Service]
Environment="PATH=/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
```

For single-user installations (where nix is in `~/.nix-profile/bin`), ensure
the correct PATH is set in the rootless service.

### `/nix/store` not found

Nix must be installed and have built/substituted at least one package for
`/nix/store` to exist. Verify with:

```sh
ls /nix/store
nix-store --realise /nix/store/...some-path...
```

### Containerd doesn't recognize the `nix` snapshotter

Ensure the `[proxy_plugins.nix]` section in `config.toml` matches the address
that nix-snapshotter is listening on, and that both containerd and
nix-snapshotter are running.

### Permission denied on socket

For rootful: ensure the nix-snapshotter socket directory exists and has correct
permissions:

```sh
sudo mkdir -p /run/nix-snapshotter
```

For rootless: ensure `$XDG_RUNTIME_DIR` is set and the socket directory is
writable by your user.

### Nix store paths substituted but containers fail to start

Verify that bind mounts are working:

```sh
# Check if the kernel supports overlayfs
grep -i overlay /proc/filesystems
```

### Using an external builder

If `nix-store` isn't available or you want a custom substitution mechanism, use
`external_builder` in the config:

```toml
external_builder = "/path/to/your/builder"
```

The builder receives two arguments:
1. `outLink` — path for the GC root symlink (may be empty)
2. `storePath` — the `/nix/store/...` path to realise

Example builder script:

```sh
#!/bin/bash
# /usr/local/bin/nix-snapshotter-builder
outLink="$1"
storePath="$2"
if [ -n "$outLink" ]; then
  nix build --out-link "$outLink" "$storePath"
else
  nix-store --realise "$storePath"
fi
```

## non-NixOS Quick Start

### Fedora

```sh
# Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# Install containerd & runc
sudo dnf install -y containerd runc

# Build nix-snapshotter
nix build github:pdtpartners/nix-snapshotter
sudo cp ./result/bin/nix-snapshotter /usr/local/bin/
sudo cp ./result/bin/nix2container /usr/local/bin/

# Install service files
sudo mkdir -p /etc/nix-snapshotter
sudo cp contrib/systemd/nix-snapshotter.service /etc/systemd/system/
sudo tee /etc/nix-snapshotter/config.toml <<EOF
address = "/run/nix-snapshotter/nix-snapshotter.sock"
root = "/var/lib/containerd/io.containerd.snapshotter.v1.nix"

[image_service]
enable = true
containerd_address = "/run/containerd/containerd.sock"
EOF

# Start services
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl enable --now nix-snapshotter
```

### Debian

```sh
# Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install

# Install containerd & runc
sudo apt install -y containerd runc

# Build nix-snapshotter
nix build github:pdtpartners/nix-snapshotter
sudo cp ./result/bin/nix-snapshotter /usr/local/bin/
sudo cp ./result/bin/nix2container /usr/local/bin/

# Install service files
sudo mkdir -p /etc/nix-snapshotter
sudo cp contrib/systemd/nix-snapshotter.service /etc/systemd/system/
sudo tee /etc/nix-snapshotter/config.toml <<EOF
address = "/run/nix-snapshotter/nix-snapshotter.sock"
root = "/var/lib/containerd/io.containerd.snapshotter.v1.nix"

[image_service]
enable = true
containerd_address = "/run/containerd/containerd.sock"
EOF

# Start services
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl enable --now nix-snapshotter
```
