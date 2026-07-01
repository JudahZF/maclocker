{
  description = "MacLocker proximity locker for macOS and Niri/Linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      darwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];
      linuxSystems = [ "aarch64-linux" "x86_64-linux" ];
      systems = darwinSystems ++ linuxSystems;
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;
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
          maclockerNiri = pkgs.stdenvNoCC.mkDerivation {
            pname = "maclocker-niri";
            version = "1.0";

            src = ./.;

            nativeBuildInputs = [
              pkgs.makeWrapper
              pkgs.python3
            ];

            dontBuild = true;

            installPhase = ''
              runHook preInstall

              install -Dm755 linux/maclocker_niri.py "$out/bin/maclocker-niri"
              patchShebangs "$out/bin/maclocker-niri"
              wrapProgram "$out/bin/maclocker-niri" \
                --prefix PATH : ${lib.makeBinPath [
                  pkgs.bluez
                  pkgs.coreutils
                  pkgs.systemd
                ]}
              ln -s "$out/bin/maclocker-niri" "$out/bin/maclocker"

              runHook postInstall
            '';
          };
        in
        if pkgs.stdenv.isDarwin then
          {
            inherit maclocker;
            default = maclocker;
          }
        else
          {
            maclocker = maclockerNiri;
            "maclocker-niri" = maclockerNiri;
            default = maclockerNiri;
          });

      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        if pkgs.stdenv.isDarwin then
          {
            maclocker = {
              type = "app";
              program = "${self.packages.${system}.maclocker}/bin/maclocker";
            };
            default = self.apps.${system}.maclocker;
          }
        else
          let
            niriApp = {
              type = "app";
              program = "${self.packages.${system}.maclocker}/bin/maclocker-niri";
            };
          in
          {
            "maclocker-niri" = niriApp;
            maclocker = niriApp;
            default = niriApp;
          });

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        if pkgs.stdenv.isLinux then
          {
            "maclocker-niri-tests" = pkgs.runCommand "maclocker-niri-tests"
              {
                nativeBuildInputs = [ pkgs.python3 ];
              } ''
              cp -R ${./.} source
              chmod -R u+w source
              cd source
              python3 -m py_compile linux/maclocker_niri.py
              python3 -m unittest discover -s linux/tests
              touch "$out"
            '';
          }
        else
          { });
    };
}
