let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-26.05";
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
  # Gleam 1.19.2 requires a newer version of Rust.
  nixpkgs-unstable = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
  pkgs-unstable = import nixpkgs-unstable {
    config = { };
    overlays = [ ];
  };
  gleam = pkgs-unstable.rustPlatform.buildRustPackage rec {
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

    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.dbus ];

    doCheck = false;
    dontCargoInstallPostBuildHook = true;

    installPhase = ''
      mkdir -p $out/bin
      find . -name gleam -type f -executable -exec cp {} $out/bin/gleam \;
    '';
  };
in
{
  shell = pkgs.mkShellNoCC {
    packages = with pkgs; [
      gleam
      beam29Packages.erlang
      beam29Packages.rebar3
      erlang-language-platform
      clang
      deno
      just
      watchexec
      postgresql_18
      dbmate
    ];

    shellHook = ''
      export LUMINA_DEBUG='1'
      just --list
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
}
