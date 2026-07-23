# zsh / bash / starship / tmux
{
  pkgs,
  ...
}:
let
  shellAliases = import ./aliases.nix;
in
{
  users.defaultUserShell = pkgs.zsh;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = shellAliases;
    histSize = 50000;

    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [
        "git"
        "sudo"
        "direnv"
        "docker"
        "docker-compose"
        "npm"
        "node"
        "rust"
        "golang"
        "tmux"
      ];
    };

    interactiveShellInit = ''
      # User bins — keep /run/wrappers/bin first (setuid sudo)
      export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/go/bin:$PATH"

      eval "$(starship init zsh)"
      command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

      if command -v fzf >/dev/null; then
        source <(fzf --zsh)
      fi

      mkcd() { mkdir -p "$1" && cd "$1"; }
      ns() { nix shell "nixpkgs#$1" "''${@:2}"; }
      alias nd='nix develop'
    '';
  };

  programs.bash = {
    completion.enable = true;
    shellAliases = shellAliases;
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      command_timeout = 1000;
      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };
      directory = {
        truncation_length = 3;
        fish_style_pwd_dir_length = 1;
      };
      git_branch.symbol = " ";
      nix_shell = {
        symbol = " ";
        format = "via [$symbol$state( \\($name\\))]($style) ";
      };
      nodejs.symbol = " ";
      python.symbol = " ";
      rust.symbol = " ";
      golang.symbol = " ";
      package.disabled = true;
    };
  };

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    keyMode = "vi";
    clock24 = true;
    historyLimit = 50000;
    extraConfig = ''
      set -g mouse on
      set -g base-index 1
      setw -g pane-base-index 1
      set -g renumber-windows on
      set -sg escape-time 10
      set -g focus-events on
      bind r source-file /etc/tmux.conf \; display "reloaded"
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"
    '';
  };
}
