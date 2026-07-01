{
  description = "MacLocker menu bar app";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          maclocker = pkgs.stdenvNoCC.mkDerivation rec {
            pname = "maclocker";
            version = "1.0";

            src = pkgs.fetchurl {
              url = "https://github.com/JudahZF/maclocker/releases/download/v${version}/MacLocker-${version}.zip";
              hash = "sha256-Z9wzXbpaRR2sho7oLjRTImqD334mRSjIXVk4dxLnelI=";
            };

            nativeBuildInputs = [ pkgs.unzip pkgs.makeWrapper ];

            unpackPhase = ''
              unzip "$src"
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p "$out/Applications" "$out/bin"
              cp -R MacLocker.app "$out/Applications/MacLocker.app"
              makeWrapper /usr/bin/open "$out/bin/maclocker" \
                --add-flags "$out/Applications/MacLocker.app"

              runHook postInstall
            '';
          };
        in
        {
          inherit maclocker;
          default = maclocker;
        });

      apps = forAllSystems (system: {
        maclocker = {
          type = "app";
          program = "${self.packages.${system}.maclocker}/bin/maclocker";
        };
        default = self.apps.${system}.maclocker;
      });
    };
}
