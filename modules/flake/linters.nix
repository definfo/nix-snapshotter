{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.git-hooks-nix.flakeModule
  ];

  perSystem = { pkgs, lib, ... }: {
    treefmt = {
      projectRootFile = "flake.nix";
      settings = {
        global.excludes = [ ];
        formatter.golangci-lint.options = lib.mkForce [
          "fmt"
          "--config"
          ".golangci.yml"
        ];
      };

      programs = {
        golangci-lint = {
          enable = true;
          configFile = ".golangci.yml";
        };
        shellcheck.enable = true;
      };
    };

    pre-commit.settings = {
      package = pkgs.prek;
      configPath = ".pre-commit-config.flake.yaml";
      hooks = {
        go2nix = {
          enable = true;
          name = "go2nix";
          description = "Check go2nix.toml lockfile";
          entry =
            let
              script = pkgs.writeShellScript "go2nix-wrapper" ''
                exec ${lib.getExe pkgs.go2nix} generate .
              '';
            in
            toString script;
          files = "go\\.(mod|sum)$";
          pass_filenames = false;
        };
        treefmt.enable = true;
      };
    };
  };
}
