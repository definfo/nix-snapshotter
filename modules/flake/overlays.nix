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

    k3s = super.k3s_1_34.override {
      buildGoModule = args:
        let
          isFunc = builtins.isFunction args;
          shouldPatch = !isFunc && 
                        args.pname != "k3s-cni-plugins" && 
                        args.pname != "k3s-containerd";
          
          patchedSrc = super.runCommand "k3s-patched-src" {} ''
            cp -r ${args.src} $out
            chmod -R u+w $out
            cd $out
            patch -p1 < ${./patches/k3s-nix-snapshotter.patch}
          '';
        in
          if shouldPatch then
            super.buildGoModule (args // {
              src = patchedSrc;
              vendorHash = {
                "sha256-IJi5gVxBsAjeQHi5rQpNRvWOXuNPx2Rtsy18VL+2Yxo=" = "sha256-Y3Dc/aWNpiNxDaJb3RAudwN7Ep6WdhSCQmtjt1pNk1w=";
              }.${args.vendorHash};
            })
          else
            super.buildGoModule args;
    };
  };

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        # Apply default overlay to provide nix-snapshotter for NixOS tests &
        # configurations.
        overlays = [ self.overlays.default ];
      };
    };
}
