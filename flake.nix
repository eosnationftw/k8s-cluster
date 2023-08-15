{
  description = "K8S Firehose";
  nixConfig.bash-prompt = "[nix(k8s-firehose)] >> ";
  inputs = { nixpkgs.url = "github:nixos/nixpkgs/23.05"; };

  outputs = { self, nixpkgs }:
    let pkgs = nixpkgs.legacyPackages.x86_64-linux.pkgs;
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        name = "K8S Firehose";
        buildInputs = [ pkgs.fluxcd pkgs.istioctl pkgs.kind pkgs.kubectl ];
        shellHook = ''
          # Deleting kind cluster if present
          kind delete cluster > /dev/null 2>&1

          echo "========================================================="
          echo "Nix shell for $name"
          echo "Make sure you read the README before testing the cluster."
          echo "========================================================="

          # Starting kind cluster
          bash ./startup.sh
        '';
      };
    };
}
