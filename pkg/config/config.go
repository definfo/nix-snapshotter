package config

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"dario.cat/mergo"
	"github.com/containerd/log"
	"github.com/pelletier/go-toml/v2"
)

var (
	defaultAddress            = "/run/nix-snapshotter/nix-snapshotter.sock"
	defaultRoot               = "/var/lib/containerd/io.containerd.snapshotter.v1.nix"
	defaultContainerdAddress  = "/run/containerd/containerd.sock"
	defaultRootlessAddress    = "/run/user/" + userID() + "/containerd/nix-snapshotter.sock"
	defaultRootlessRoot       = userDataDir() + "/containerd/io.containerd.snapshotter.v1.nix"
	defaultRootlessCtrAddress = "/run/user/" + userID() + "/containerd/containerd.sock"
)

// userID returns the current user's UID as a string for XDG runtime paths.
func userID() string {
	return fmt.Sprintf("%d", os.Getuid())
}

// userDataDir returns the user data directory following XDG Base Directory specification.
func userDataDir() string {
	if xdg := os.Getenv("XDG_DATA_HOME"); xdg != "" {
		return xdg
	}
	return filepath.Join(os.Getenv("HOME"), ".local/share")
}

// Config provides nix-snapshotter configuration data.
type Config struct {
	Address         string             `toml:"address"`
	Root            string             `toml:"root"`
	ExternalBuilder string             `toml:"external_builder"`
	ImageService    ImageServiceConfig `toml:"image_service"`
}

type ImageServiceConfig struct {
	Enable            bool   `toml:"enable"`
	ContainerdAddress string `toml:"containerd_address"`
}

// New returns a default config suitable for the current user
// (rootful or rootless).
func New() *Config {
	// Detect rootless mode: if running as non-root, use XDG-style paths.
	if os.Getuid() != 0 {
		return &Config{
			Address: defaultRootlessAddress,
			Root:    defaultRootlessRoot,
			ImageService: ImageServiceConfig{
				Enable:            true,
				ContainerdAddress: defaultRootlessCtrAddress,
			},
		}
	}
	return &Config{
		Address: defaultAddress,
		Root:    defaultRoot,
		ImageService: ImageServiceConfig{
			Enable:            true,
			ContainerdAddress: defaultContainerdAddress,
		},
	}
}

// Merge will fill any attributes with non-empty override attribute values.
func (cfg *Config) Merge(override *Config) error {
	return mergo.Merge(cfg, override, mergo.WithOverride)
}

// Load will unmarshal a toml file at the given config path and merge it
// with this config. If it doesn't exist, then do nothing.
func (cfg *Config) Load(ctx context.Context, configPath string) error {
	r, err := os.Open(configPath)
	if err != nil {
		log.G(ctx).WithError(err).Debugf("Not loading config from %q", configPath)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	defer func() {
		if err := r.Close(); err != nil {
			log.G(ctx).WithError(err).Debugf("Failed to close config file")
		}
	}()

	log.G(ctx).Debugf("Loading config from %q", configPath)
	override := &Config{}
	dec := toml.NewDecoder(r).DisallowUnknownFields()
	if err := dec.Decode(override); err != nil {
		return fmt.Errorf("failed to load nix-snapshotter config from %q: %w", configPath, err)
	}

	err = cfg.Merge(override)
	if err != nil {
		return fmt.Errorf("failed to merge nix-snapshotter config from %q: %w", configPath, err)
	}

	log.G(ctx).Debugf("Loaded config %+v", cfg)
	return nil
}
