{ pkgs ? import <nixpkgs> {} }:

# Prerequisites
  # install Nix package manager or use NixOS

# The purpose of this shell is to:
  # install postgresql
  # install chuck-stack-nushell-psql-migration
  # create a local psql cluster (in this directory)
  # run the migrations and report success or failure
  # allow you to view and interact with the results using 'psql'
  # allow you to use the database with aichat function calling
  # destroy all artifacts upon leaving the shell

let
  # Fetch chuck-stack-nushell-psql-migration source
  migrationUtilSrc = pkgs.fetchgit {
    url = "https://github.com/chuckstack/chuck-stack-nushell-psql-migration";
    rev = "e67c7c8e5ed411314396585f53106ef51868ac00";  # suppressed migration table not found error
    sha256 = "sha256-EL6GEZ3uvBsnR8170SBY+arVfUsLXPVxKPEOqIVgedA=";
  };

  # Create pg_jsonschema extension package
  pg_jsonschema_ext = pkgs.stdenv.mkDerivation {
    name = "pg_jsonschema-extension";
    src = ./pg_extension/17;
    installPhase = ''
      mkdir -p $out/lib $out/share/postgresql/extension
      cp pg_jsonschema.so $out/lib/
      cp pg_jsonschema.control $out/share/postgresql/extension/
      cp pg_jsonschema--0.3.3.sql $out/share/postgresql/extension/
    '';
  };

  # Combine PostgreSQL with extension using buildEnv (no rebuild)
  postgresql-with-jsonschema = pkgs.buildEnv {
    name = "postgresql-with-jsonschema";
    paths = [ pkgs.postgresql pg_jsonschema_ext ];
  };

  # Function to setup migration utility and start test environment
  startTest = pkgs.writeShellScriptBin "start-test" ''
    # Setup migration utility in test directory
    mkdir -p "$STK_TEST_DIR/tools/migration"
    cp -r ${migrationUtilSrc}/src/* "$STK_TEST_DIR/tools/migration/"
    
    # Run the nushell start-test script
    cd "$STK_TEST_DIR"
    ${pkgs.nushell}/bin/nu "$STK_PWD_SHELL/start-test.nu"
  '';

  # Function to cleanup test environment
  stopTest = pkgs.writeShellScriptBin "stop-test" ''
    if [ -n "$STK_STOP_SCRIPT" ] && [ -f "$STK_STOP_SCRIPT" ]; then
      ${pkgs.nushell}/bin/nu "$STK_STOP_SCRIPT"
    else
      echo "Error: Stop script not found. STK_STOP_SCRIPT=$STK_STOP_SCRIPT"
      exit 1
    fi
  '';

  # Function to override usql to psql
  usql-override = pkgs.writeShellScriptBin "usql" ''
    exec ${postgresql-with-jsonschema}/bin/psql "$@"
  '';

in pkgs.mkShell {
  buildInputs = [
    postgresql-with-jsonschema
    pkgs.nushell
    pkgs.postgrest
    pkgs.bat
    pkgs.aichat
    pkgs.typst
    #pkgs.git
    startTest
    stopTest
    usql-override
  ];

  shellHook = ''
    # Setup environment variables for chuck-stack test environment
    export STK_PWD_SHELL=$PWD
    export STK_STOP_SCRIPT="$PWD/stop-test.nu"
    export STK_TEST_DIR="/tmp/stk-test-$$"
    export PGHOST="$STK_TEST_DIR/pgdata"
    export PGDATA="$PGHOST"
    export PGUSERSU=postgres
    export STK_SUPERUSER=stk_superuser
    export STK_USER=stk_login
    export PGUSER=$STK_SUPERUSER
    export PGDATABASE=stk_db
    export STK_PG_ROLE="stk_api_role"
    export STK_PG_SESSION="'{\"psql_user\": \"$STK_USER\"}'"
    export PSQLRC="$STK_TEST_DIR"/.psqlrc
    export STK_PSQLRC_NU="$STK_TEST_DIR"/.psqlrc-nu
    export HISTFILE="$STK_TEST_DIR/.psql_history"
    export USQL_DSN=""
    export f="-r %functions%"
    
    # Documentation paths
    export STK_DOCS_PATH="/opt/chuckstack.github.io"
    export AICHAT_ROLES_DIR="$STK_DOCS_PATH/src-ls/roles/"
    
    # aichat aliases (will be set up after environment starts)
    alias aix="aichat -f $STK_TEST_DIR/schema-details/ "
    alias aix-conv-detail="aichat -f $STK_TEST_DIR/schema-details/ -f $STK_DOCS_PATH/src-ls/postgres-convention/"
    alias aix-conv-sum="aichat -f $STK_TEST_DIR/schema-details/ -f $STK_DOCS_PATH/src-ls/postgres-conventions.md"

    # Start the test environment using nushell
    start-test

    # Switch to test directory and powerless user for regular operations
    cd "$STK_TEST_DIR"
    export PGUSER=$STK_USER

    # Setup cleanup trap
    cleanup() {
      stop-test
    }
    trap cleanup EXIT
  '';
}
