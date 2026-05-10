{
  description = "GPUMD: Graphics Processing Units Molecular Dynamics";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          enableCUDA = true;
          config = {
            allowUnfree = true;
            cudaSupport = true;
            cudaCapability = [ "6.1" ];
          };
          cudaVersion = "12.9";
          overlays = [
            (final: prev: {
              # Target the specific CUDA set you are using
              cudaPackages_12_9 = prev.cudaPackages_12_9.overrideScope (cfinal: cprev: {
                # Override the cudnn attribute within that scope
                cudnn = cprev.cudnn.overrideAttrs (oldAttrs: rec{
                  version = "9.11.1.4"; # Your desired version
                  src = prev.fetchurl {
                    # You must provide the URL and hash for the specific version
                    url = "https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-x86_64/cudnn-linux-x86_64-${version}_cuda12-archive.tar.xz";
                    hash = "sha256-YJrEikSORTMoek18YgVr8TD66MOx6yohgIDingAm7Bg=";
                  };
                });
              });
            })
          ];

        };
        cudaLibs =
          with pkgs.cudaPackages_12_9;[
            cuda_nvcc
            cuda_cudart
            libcufft
            libcurand
            libcublas
            libcublasmp
            libcusolver
            libcusolvermp
          ];
      in
      {
        packages.gpumd = pkgs.stdenv.mkDerivation rec{
          pname = "gpumd";
          version = "5.2"; # Or latest
          src = pkgs.fetchFromGitHub {
            owner = "brucefan1983";
            repo = "GPUMD";
            rev = "v5.2"; # Use specific release tag
            sha256 = "sha256-DNIk8LxjboeYdGcR3gox/UHgcYEJoa7fyotwTssAtJA="; # Update this
          };

          wrapperOptions = with pkgs;[
            # ollama embeds llama-cpp binaries which actually run the ai models
            # these llama-cpp binaries are unaffected by the ollama binary's DT_RUNPATH
            # LD_LIBRARY_PATH is temporarily required to use the gpu
            # until these llama-cpp binaries can have their runpath patched
            "--suffix LD_LIBRARY_PATH : '${addDriverRunpath.driverLink}/lib'"
            "--suffix LD_LIBRARY_PATH : '${lib.makeLibraryPath (map lib.getLib cudaLibs)}'"
          ];
          wrapperArgs = builtins.concatStringsSep " " wrapperOptions;


          nativeBuildInputs = with pkgs; [
            cudaLibs
            makeWrapper
          ];

          # GPUMD builds by entering src and running make
          preBuild = "cd src";

          installPhase = ''
            mkdir -p $out/bin
            cp gpumd nep $out/bin/
          '';
          postFixup =
            # expose runtime libraries necessary to use the gpu
            ''
              wrapProgram "$out/bin/gpumd" ${wrapperArgs}
              wrapProgram "$out/bin/nep" ${wrapperArgs}
            '';

        };

        defaultPackage = self.packages.${system}.gpumd;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            self.packages.${system}.gpumd
            cudaLibs
          ];
        };
      }
    );
}

