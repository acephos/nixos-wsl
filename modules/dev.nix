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
      core.pager = "delta";
      interactive.diffFilter = "delta --color-only";
      delta = {
        navigate = true;
        line-numbers = true;
        side-by-side = false;
      };
      merge.conflictstyle = "zdiff3";
      rerere.enabled = true;
      # Identity lives in home-manager (home/git.nix) — not here.
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
