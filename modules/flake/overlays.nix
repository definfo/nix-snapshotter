{ self, inputs, ... }:

{
  # Provide overlay to add `nix-snapshotter`.
  flake.overlays.default = self: super: {
    containerd-1_7 = super.containerd.overrideAttrs (_: rec {
      version = "1.7.28";

      src = self.fetchFromGitHub {
        owner = "containerd";
        repo = "containerd";
        tag = "v${version}";
        hash = "sha256-vz7RFJkFkMk2gp7bIMx1kbkDFUMS9s0iH0VoyD9A21s=";
      };

      outputs = [ "out" ];

      buildPhase = ''
        runHook preBuild
        patchShebangs .
        make binaries "VERSION=v${version}" "REVISION=${src.rev}"
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm555 bin/* -t $out/bin
        runHook postInstall
      '';
    });

    nix-snapshotter = self.callPackage ../../package.nix {
      inherit (inputs) globset;
    };

    # `k3s-nix-snapshotter` is available in k3s 1.33.10+, 1.34.6+,
    # and 1.35.3+, so this overlay only keeps the local checkpoint fix.
    k3s =
      let
        patchVendoredContainerd = oldAttrs: {
          # buildGoModule creates the vendor tree during configurePhase.
          preBuild = (oldAttrs.preBuild or "") + ''
            patch --forward -p1 < ${./patches/containerd-checkpoint-not-found.patch} || true
          '';
        };
      in
      (super.k3s_1_34.override {
        overrideBundleAttrs = patchVendoredContainerd;
      }).overrideAttrs
        patchVendoredContainerd;
  };

  flake.overlays.go2nix = self: super: {
    inherit (inputs.go2nix.packages.${self.stdenv.hostPlatform.system}) go2nix;
    goEnv = inputs.go2nix.lib.mkGoEnv {
      inherit (self) go go2nix callPackage;
      nixPackage = self.nixVersions.nix_2_34; # Nix >= 2.34 is required
    };
  };

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        # Apply default overlay to provide nix-snapshotter for NixOS tests &
        # configurations.
        overlays = [
          self.overlays.default
          self.overlays.go2nix
        ];
      };
    };
}
