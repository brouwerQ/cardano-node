/*
  This file defines tullia tasks and cicero actions.

  Tullia is a sandboxed multi-runtime DAG task runner with Cicero support.
  Tasks can be written in different languages and are compiled for each runtime using Nix.
  It comes with essential building blocks for typical CI/CD scenarios.
  Learn more: https://github.com/input-output-hk/tullia

  Cicero is an if-this-then-that machine on HashiCorp Nomad.
  It can run any event-and-state-driven automation actions
  and hence CI/CD pipelines are a natural fit.
  In tandem with Tullia, an action could be described as
  the rule that describes when a Tullia task is to be invoked.
  Learn more: https://github.com/input-output-hk/cicero
*/

let
  ciInputName = "GitHub event";
  repository = "input-output-hk/cardano-node";
in
rec {
  tasks =
    let
      common =
        { config
        , ...
        }: {
          preset = {
            nix.enable = true;

            github.ci = {
              enable = config.actionRun.facts != { };
              inherit repository;
              remote = config.preset.github.lib.readRepository ciInputName null;
              revision = config.preset.github.lib.readRevision ciInputName null;
            };
          };

          nomad.driver = "exec";
        };


      mkBulkJobsTask = jobsAttrs: { config
                                  , lib
                                  , ...
                                  }: {
        imports = [ common ];

        command.text = config.preset.github.status.lib.reportBulk {
          bulk.text = ''
            nix eval .#outputs.hydraJobs --apply __attrNames --json |
            nix-systems -i |
            jq 'with_entries(select(.value))' # filter out systems that we cannot build for
          '';
          each.text = ''nix build -L .#hydraJobs."$1".${jobsAttrs}'';
          skippedDescription = lib.escapeShellArg "No nix builder available for this system";
        };

        env.NIX_CONFIG = ''
          # `kvm` for NixOS tests
          # `benchmark` for benchmarks
          extra-system-features = kvm benchmark
          # bigger timeouts (900 by default on cicero) needed for some derivations (especially on darwin)
          max-silent-time = 1800
        '';

        memory = 1024 * 32;
        nomad.resources.cpu = 10000;
      };
    in
    {
      "ci/pr/required" = mkBulkJobsTask "pr.required";
      "ci/pr/nonrequired" = mkBulkJobsTask "pr.nonrequired";
      "ci/push/required" = mkBulkJobsTask "required";

      "ci/cardano-deployment" = { lib, ... } @ args: {
        imports = [ common ];
        command.text = ''
          nix build -L .#hydraJobs.cardano-deployment
        '';
        memory = 1024 * 16;
        nomad.resources.cpu = 10000;
      };

      "ci/push" = { lib, ... } @ args: {
        imports = [ common ];
        after = [ "ci/push/required" "ci/cardano-deployment" ];
      };

      "ci/pr" = { lib, ... } @ args: {
        imports = [ common ];
        after = [ "ci/pr/required" "ci/pr/nonrequired" "ci/cardano-deployment" ];
      };
    };

  actions =
    let
      prIo = ''
        #lib.io.github_pr
        #input: "${ciInputName}"
        #repo: "${repository}"
      '';
      pushIo = ''
        #lib.io.github_push
        #input: "${ciInputName}"
        #repo: "${repository}"
        #branch: "master|staging|trying"
      '';
    in
    {

      "cardano-node/ci/push/required" = {
        task = "ci/push/required";
        io = pushIo;
      };
      "cardano-node/ci/push/cardano-deployment" = {
        task = "ci/cardano-deployment";
        io = pushIo;
      };

      "cardano-node/ci/pr/required" = {
        task = "ci/pr/required";
        io = prIo;
      };
      "cardano-node/ci/pr/nonrequired" = {
        task = "ci/pr/nonrequired";
        io = prIo;
      };
      "cardano-node/ci/pr/cardano-deployment" = {
        task = "ci/cardano-deployment";
        io = prIo;
      };
    };
}
