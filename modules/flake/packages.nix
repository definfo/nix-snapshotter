{
  perSystem = { pkgs, config, ... }: {
    packages = rec {
      inherit (pkgs)
        containerd
        containerd-1_7
        k3s
        nix-snapshotter
        ;

      default = nix-snapshotter;
    };

    devShells.default = pkgs.mkShell {
      inputsFrom = [
        config.treefmt.build.devShell
        config.pre-commit.devShell
      ];

      packages =
        with pkgs;
        [
          containerd
          cri-tools
          delve
          gdb
          golangci-lint
          gopls
          gotools
          kind
          kubectl
          redis
          rootlesskit
          runc
          slirp4netns
          nerdctl

          go
          go-tools
          govulncheck
          go-junit-report
          go-task
          go-mod-upgrade
          go2nix
        ]
        ++ nix-snapshotter.nativeBuildInputs;
    };
  };
}
