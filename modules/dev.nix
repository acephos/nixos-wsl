# Git, direnv, docker
{
  ...
}:
{
  programs.git = {
    enable = true;
    lfs.enable = true;
    config = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.editor = "nvim";
      # Review-first diffs via tuicr (agavra/tuicr).
      core.pager = "delta";
      alias = {
        review = "!tuicr";
        review-wip = "!tuicr -w";
        review-pr = "!tuicr pr";
      };
      merge.conflictstyle = "zdiff3";
      rerere.enabled = true;
      # Identity lives in home-manager (home/default.nix) — not here.
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };
}
