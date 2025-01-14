pkgs: _:
let
  mkPoetryEnv = { groups, python, extras ? [ "*" ] }: pkgs.poetry2nix.mkPoetryEnv {
    inherit python groups extras;
    projectDir = pkgs.gitignoreSource ../.;
    editablePackageSources = { ibis = pkgs.gitignoreSource ../ibis; };
    overrides = [
      (import ../poetry-overrides.nix)
      pkgs.poetry2nix.defaultPoetryOverrides
    ];
    preferWheels = true;
  };

  mkPoetryDevEnv = python: mkPoetryEnv {
    inherit python;
    groups = [ "dev" "docs" "test" ];
  };
  mkPoetryQuartoDevEnv = python: mkPoetryEnv {
    inherit python;
    groups = [ "dev" "quarto" ];
  };
in
{
  ibisTestingData = pkgs.fetchFromGitHub {
    name = "ibis-testing-data";
    owner = "ibis-project";
    repo = "testing-data";
    rev = "2b3968deaa1a28791b2901dbbcc9bfd3d2f23e9b";
    sha256 = "sha256-q1b5IcOl5oIFXP7/P5RufncjHEVrWp4NjoU2uo/BE9U=";
  };

  ibis39 = pkgs.callPackage ./ibis.nix { python3 = pkgs.python39; };
  ibis310 = pkgs.callPackage ./ibis.nix { python3 = pkgs.python310; };
  ibis311 = pkgs.callPackage ./ibis.nix { python3 = pkgs.python311; };

  ibisDevEnv39 = mkPoetryDevEnv pkgs.python39;
  ibisDevEnv310 = mkPoetryDevEnv pkgs.python310;
  ibisDevEnv311 = mkPoetryDevEnv pkgs.python311;

  ibisQuartoDevEnv310 = mkPoetryQuartoDevEnv pkgs.python310;

  ibisSmallDevEnv = mkPoetryEnv {
    python = pkgs.python311;
    groups = [ "dev" ];
    extras = [ ];
  };

  # TODO(cpcloud): remove once https://github.com/NixOS/nixpkgs/pull/232090 is merged
  quarto = pkgs.callPackage ./quarto { };

  changelog = pkgs.writeShellApplication {
    name = "changelog";
    runtimeInputs = [ pkgs.nodePackages.conventional-changelog-cli ];
    text = ''
      conventional-changelog --config ./.conventionalcommits.js "$@"
    '';
  };

  check-release-notes-spelling = pkgs.writeShellApplication {
    name = "check-release-notes-spelling";
    runtimeInputs = [ pkgs.changelog pkgs.coreutils pkgs.ibisSmallDevEnv ];
    text = ''
      tmp="$(mktemp)"
      changelog --release-count 1 --output-unreleased --outfile "$tmp"
      if ! codespell "$tmp"; then
        # cat -n to output line numbers
        cat -n "$tmp"
        exit 1
      fi
    '';
  };

  update-lock-files = pkgs.writeShellApplication {
    name = "update-lock-files";
    runtimeInputs = with pkgs; [ just poetry ];
    text = "just lock";
  };

  gen-examples = pkgs.writeShellApplication {
    name = "gen-examples";
    runtimeInputs = [
      pkgs.ibisDevEnv311
      (pkgs.rWrapper.override {
        packages = with pkgs.rPackages; [
          Lahman
          janitor
          palmerpenguins
          stringr
          tidyverse
        ];
      })
      pkgs.google-cloud-sdk
    ];

    text = ''
      python "$PWD/ibis/examples/gen_registry.py" "''${@}"
    '';
  };

  gen-all-extras = pkgs.writeShellApplication {
    name = "gen-all-extras";
    runtimeInputs = with pkgs; [ yj jq ];
    text = ''
      echo -n 'all = '
      yj -tj < pyproject.toml | jq -rM '.tool.poetry.extras | with_entries(select(.key != "all")) | [.[]] | add | unique | sort'
    '';
  };

  check-poetry-version = pkgs.writeShellApplication {
    name = "check-poetry-version";
    runtimeInputs = [
      (
        mkPoetryEnv {
          python = pkgs.python3;
          groups = [ ];
          extras = [ ];
        }
      ).pkgs.poetry
    ];
    text = ''
      expected="$1"
      out="$(poetry --version --no-ansi)"
      if [[ "$out" != *"$expected"* ]]; then
        >&2 echo "error: expected version $expected; got: $out"
        exit 1
      fi
    '';
  };
}
