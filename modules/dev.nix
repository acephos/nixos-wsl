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
      # Review-first diffs via hunk (modem-dev/hunk)
      # https://github.com/modem-dev/hunk — Install / Working with Git
      core.pager = "hunk pager";
      alias = {
        # Opt-in forms from upstream docs (core.pager already set globally)
        hdiff = "-c core.pager=\"hunk pager\" diff";
        hshow = "-c core.pager=\"hunk pager\" show";
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
