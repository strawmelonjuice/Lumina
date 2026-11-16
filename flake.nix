{
  description = "Lumina flake";
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
    flake-compat.url = "github:edolstra/flake-compat";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-compat,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      oatVersion = "0.6.2";

      oatJs = pkgs.fetchurl {
        url = "https://unpkg.com/@knadh/oat@${oatVersion}/oat.min.js";
        hash = "sha256-Gy/KLTDGBKRpTK4huaxWVRomC7Jyg4XH/ernagO0nvw=";
      };

      oatCss = pkgs.fetchurl {
        url = "https://unpkg.com/@knadh/oat@${oatVersion}/oat.min.css";
        hash = "sha256-9jvC3Vd3Fh2xiGdsA+4xk85yMOTnsHdLcY7MZo3h2LE=";
      };

      oatVendorDir = pkgs.runCommand "oat-vendor" { } ''
        mkdir -p $out
        cp ${oatJs} $out/oat.min.js
        cp ${oatCss} $out/oat.min.css
        echo "${oatVersion}" > $out/.rev
      '';
      dependencies = {
        gleam = pkgs.gleam
        # gleam-local
        ;
        curl = pkgs.curl;
        erlang = pkgs.beam29Packages.erlang;
        rebar3 = pkgs.beam29Packages.rebar3;
        elp = pkgs.erlang-language-platform;
        clang = pkgs.clang;
        deno = pkgs.deno;
        esbuild = pkgs.esbuild;
        watchexec = pkgs.watchexec;
        postgres = pkgs.postgresql_18;
        dbmate = pkgs.dbmate;

        just = pkgs.just;

        libs = pkgs.stdenv.mkDerivation {
          pname = "lumina-deps";
          version = "1.0";
          src = ./.;

          dontFixup = true;
          nativeBuildInputs = [
            deps.gleam
            deps.erlang
            deps.rebar3
            deps.deno
            pkgs.cacert
            pkgs.git
            pkgs.nukeReferences
          ];

          buildPhase = ''
            export HOME=$(mktemp -d)
            export DENO_DIR=$(mktemp -d)


            # 1. Pre-fetch Gleam packages
            (cd ./lumina/web/initialiser && gleam deps download)
            (cd ./lumina/backend && gleam deps download)

            # Pre-fetch deno packages
            ${deps.deno}/bin/deno cache --node-modules-dir=auto npm:minifier || true
            mkdir -p $out/deno-cache
            cp -r "$DENO_DIR"/* $out/deno-cache/
          '';

          installPhase = ''
            mkdir -p $out/spa $out/backend
            cp -r ./lumina/web/initialiser/build/packages $out/spa/packages
            cp -r ./lumina/backend/build/packages $out/backend/packages
            find $out -type f -exec nuke-refs {} +
          '';

          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = "sha256-glYmf6WPyyWCoNWQElRlXosODP9ez3AtHuIjWlMJ3M0=";
        };

      };
      deps = dependencies;

      scripts = {
        prepare-build = pkgs.writeShellScriptBin "prepare-build" ''
          set -euo pipefail

          # Write prelude to SPA src directory
          [ ! -f ./lumina/web/initialiser/prelude.mts ] && gleam export typescript-prelude > ./lumina/web/initialiser/prelude.mts || echo ""

          # Build SPA
          (cd ./lumina/web/initialiser && gleam build)

          # Create bundleable export from Oat's JS.
          echo 'export function oat () {' > ./lumina/web/initialiser/build/dev/javascript/lumina_spa/oat.mjs
          cat ${oatJs} >> ./lumina/web/initialiser/build/dev/javascript/lumina_spa/oat.mjs
          echo '}' >> ./lumina/web/initialiser/build/dev/javascript/lumina_spa/oat.mjs

          # Patch SPA, Oat and Lustre Server Component runtime into Lumina a single web js bundle.
          echo 'import { main } from "./lumina_spa.mjs"; import { ServerComponent } from "../lustre/priv/static/lustre-server-component.mjs"; import { oat } from "./oat.mjs"; document.addEventListener("DOMContentLoaded", main()); oat()' > "./lumina/web/initialiser/build/dev/javascript/lumina_spa/client.mjs"
          ${deps.esbuild}/bin/esbuild ./lumina/web/initialiser/build/dev/javascript/lumina_spa/client.mjs \
            --bundle --format=esm --platform=browser \
            --outfile=./lumina/backend/priv/client.js
          ${deps.esbuild}/bin/esbuild ./lumina/web/initialiser/build/dev/javascript/lumina_spa/client.mjs \
            --bundle --format=esm --platform=browser --minify \
            --outfile=./lumina/backend/priv/client.min.js

          # Bundle Oat into Lumina web css bundle.
          echo -en "/*\n* Lumina/Peonies\n* Copyright (C) 2018-2026 MLC 'Strawmelonjuice' Bloeiman and contributors.\n*\n* This software is licensed under the European Union Public Licence (EUPL) v1.2.\n* You may not use this work except in compliance with the Licence.\n* You may obtain a copy of the Licence at: https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12\n*\n* AI TRAINING NOTICE: Rights for TDM and AI training are EXPRESSLY RESERVED\n* under Art 4(3) Dir 2019/790. AI training constitutes a Derivative Work. \n* See LICENCE file in the repository root for full details.\n*\n*\n* This software is provided "AS IS", WITHOUT WARRANTY OF ANY KIND.\n* See the Licence for the specific language governing permissions and limitations.\n*\n* This bundled file also contains CSS contents for Oat CSS, which is licenced under MIT <https://github.com/knadh/oat/blob/master/LICENSE>. Big thank you to Kailash Nadh for this library.\n*/" > "./lumina/backend/priv/lumina.css"
          echo -en "\n\n/* Oat.css {{ oat_version }} */\n" >> "./lumina/backend/priv/lumina.css"
          cat ${oatCss} >> "./lumina/backend/priv/lumina.css"
          # And Lumina's own.
          echo -en "\n\n/* Lumina's own styles */\n" >> "./lumina/backend/priv/lumina.css"
          cat ./lumina/backend/priv/static/lumina-base.css >> "./lumina/backend/priv/lumina.css"
          cat ./lumina/backend/priv/static/lumina-extended.css >> "./lumina/backend/priv/lumina.css"

          # Minify the css bundle
          ${deps.deno}/bin/deno x minifier lumina/backend/priv/lumina.css --output lumina/backend/priv/lumina.min.css

          # Also copy over other files, such as licence file.
          cp ./LICENCE ./lumina/backend/priv/licence
          ${deps.just}/bin/just embed-docs
        '';

        run = pkgs.writeShellScriptBin "run" ''
          set -euo pipefail
          ${scripts.prepare-build}/bin/prepare-build

          (cd ./lumina/backend/ && gleam run)
        '';
        into-shipment = pkgs.writeShellScriptBin "into-shipment" ''
          set -euo pipefail
        '';
      };

      gleam-local = pkgs.rustPlatform.buildRustPackage rec {
        pname = "gleam";
        version = "1.19.2";
        src = pkgs.fetchFromGitHub {
          owner = "gleam-lang";
          repo = "gleam";
          rev = # Tagged
            "v1.19.2";
          hash = "sha256-L7M1/nGDiB4D+yX1cjQ7mqNQ7YuC1BctLXEvnNjPz7A=";
        };
        cargoLock = {
          lockFile = "${src}/Cargo.lock";
        };
        nativeBuildInputs = [
          pkgs.pkg-config
        ];
        buildInputs = [ pkgs.dbus ];
        doCheck = false;
        dontCargoInstallPostBuildHook = true;
        installPhase = ''
          mkdir -p $out/bin
          find . -name gleam -type f -executable -exec cp {} $out/bin/gleam \;
        '';
      };
      buildInputs =
        (with dependencies; [
          gleam
          curl
          erlang
          rebar3
          elp
          clang
          deno
          watchexec
          postgres
          dbmate
          just
        ])
        ++ (with scripts; [
          prepare-build
          run
          into-shipment
        ]);
    in
    {
      devShells.default = pkgs.mkShell {
        inherit buildInputs;

        shellHook = ''
          mkdir -p ./vendor/oat
          cp -r ${oatVendorDir} ./vendor/oat

          export LUMINA_DEBUG='1'
          echo "Use just to run these recipes."
          if [ ! -d "$PGDATA" ]; then
              export PGDATA="$(pwd)/lumina/backend/build/data/data/.postgres"
              export PGHOST="/tmp"
              export LOG_PATH="$PGDATA/server.log"
              initdb --auth=trust -U postgres
              echo "listen_addresses = '127.0.0.1'" >> "$PGDATA/postgresql.conf"
              echo "port = 5432" >> "$PGDATA/postgresql.conf"
              echo "unix_socket_directories = '$PGHOST'" >> "$PGDATA/postgresql.conf"
          fi
        '';
      };
      packages.x86_64-linux.lumina-server = pkgs.stdenv.mkDerivation {
        pname = "lumina-server";
        inherit buildInputs;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        buildPhase = ''
          runHook preBuild


          export HOME=$(mktemp -d)
          export DENO_DIR=$(mktemp -d)
          cp -r ${dependencies.libs}/deno-cache/* "$DENO_DIR/" || true
          chmod -R +w "$DENO_DIR"

          # Restore pre-fetched Gleam dependencies
          mkdir -p ./lumina/web/initialiser/build ./lumina/backend/build
          cp -r ${dependencies.libs}/spa/packages ./lumina/web/initialiser/build/packages
          cp -r ${dependencies.libs}/backend/packages ./lumina/backend/build/packages
          chmod -R +w ./lumina/web/initialiser/build/packages ./lumina/backend/build/packages



          ${scripts.prepare-build}/bin/prepare-build

          (cd ./lumina/backend/ && gleam export erlang-shipment)

          runHook postBuild
                    	'';
        version = "1.0";
        src = ./.;
        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp -r  ./lumina/backend/build/erlang-shipment $out/shipment
          chmod +x $out/shipment/entrypoint.sh

          wrapProgram $out/shipment/entrypoint.sh \
            --prefix PATH : ${pkgs.lib.makeBinPath [ dependencies.erlang ]} \
            --add-flags "run"

          ln -s $out/shipment/entrypoint.sh $out/bin/lumina-server

          runHook postInstall
        '';
      };
      packages.x86_64-linux.default = self.packages.x86_64-linux.lumina-server;
    };
}
