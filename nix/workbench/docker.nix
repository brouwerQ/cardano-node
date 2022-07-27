let
  basePort              = 30000;
  cacheDirDefault       = "${__getEnv "HOME"}/.cache/cardano-workbench";
  stateDir              = "run/current";
in
{ pkgs
, lib
, workbench
##
, cacheDir              ? cacheDirDefault
, extraSupervisorConfig ? {}
, useCabalRun           ? false
, enableEKG             ? true
##
, ...
}:
with lib;
let
  backend =
    rec
    { name = "docker";

      inherit (import ./profiles/services-config.nix {inherit lib; inherit workbench; inherit basePort; inherit stateDir; inherit useCabalRun; inherit enableEKG;}) topologyForNodeSpec nodePublicIP finaliseNodeService finaliseNodeConfig finaliseNodeArgs finaliseGeneratorService finaliseGeneratorConfig finaliseTracerService;

      materialise-profile =
        { profileNix }:
        pkgs.runCommand "workbench-profile-outputs-${profileNix.name}-dockerd" {}
          ''
          mkdir $out
          cp ${dockerd.mkSupervisorConf profileNix} $out/docker.conf
          '';

      ## IMPORTANT:  keep in sync with envArgs in 'workbench/default.nix/generateProfiles/environment'.
      env-args-base =
        {
          inherit (pkgs) cardanoLib;
          inherit stateDir cacheDir basePort;
          staggerPorts = true;
        };

      ## Backend-specific Nix bits:
      dockerd =
        {
          inherit
            extraSupervisorConfig;

          ## mkSupervisorConf :: Profile -> SupervisorConf
          mkSupervisorConf =
            profile:
            pkgs.callPackage ./docker-conf.nix
            { inherit (profile) node-services generator-service;
              inherit
                pkgs lib stateDir
                basePort
                extraSupervisorConfig;
            };
        };
    };

  all-profiles =
    workbench.all-profiles
      { inherit backend;
        envArgs = backend.env-args-base;
      };
in
{
  inherit cacheDir stateDir basePort;
  inherit workbench;
  inherit backend;
  inherit all-profiles;
}
