# Ink — fish. Prompt de dos líneas: ruta y rama; ● si el último comando salió bien, ○ si falló.
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx BROWSER helium-browser
fish_add_path -m $HOME/.local/bin

status is-interactive; or return
set -g fish_greeting

# Colores: solo grises
set -g fish_color_normal e4e4e4
set -g fish_color_command ffffff --bold
set -g fish_color_keyword ffffff
set -g fish_color_param c8c8c8
set -g fish_color_option c8c8c8
set -g fish_color_quote 9a9a9a
set -g fish_color_redirection 9a9a9a
set -g fish_color_end 6e6e6e
set -g fish_color_operator 9a9a9a
set -g fish_color_escape 9a9a9a
set -g fish_color_comment 5c5c5c
set -g fish_color_error ffffff --underline
set -g fish_color_autosuggestion 6e6e6e
set -g fish_color_valid_path --underline
set -g fish_pager_color_prefix ffffff --bold
set -g fish_pager_color_completion c8c8c8
set -g fish_pager_color_description 6e6e6e
set -g fish_pager_color_selected_background --background=3a3a3a

# fzf: tarjeta redonda en grises
set -gx FZF_DEFAULT_OPTS '--height=40% --layout=reverse --border=rounded --info=inline --prompt="● " --pointer="▶" --color=fg:#c8c8c8,bg:-1,hl:#ffffff,fg+:#ffffff,bg+:#1e1e1e,hl+:#ffffff,info:#6e6e6e,prompt:#ffffff,pointer:#ffffff,marker:#ffffff,spinner:#6e6e6e,header:#6e6e6e,border:#3a3a3a'
command -q fd; and set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
# man con colores de bat (ANSI → grises)
command -q bat; and set -gx MANPAGER "sh -c 'col -bx | bat -l man -p --theme=ansi'"

function __ink_branch
    set -l b (git symbolic-ref --short HEAD 2>/dev/null; or git rev-parse --short HEAD 2>/dev/null); or return
    set -l dirty ''
    test -n "$(git status --porcelain 2>/dev/null | head -n1)"; and set dirty ' ✱'
    printf ' %s%s%s%s' (set_color 8a8a8a) $b $dirty (set_color normal)
end

function fish_prompt
    set -l last $status
    set -l mark '●'
    test $last -ne 0; and set mark '○'
    set -q SSH_CONNECTION; and echo -n -s (set_color 8a8a8a) $USER@(prompt_hostname) ' '
    echo -s (set_color --bold ffffff) (prompt_pwd --dir-length=0) (set_color normal) (__ink_branch)
    echo -n -s (set_color ffffff) $mark ' ' (set_color normal)
end
function fish_right_prompt; end

if command -q eza
    alias ls 'eza --group-directories-first --icons=auto'
    alias ll 'eza -lh --group-directories-first --icons=auto'
    alias la 'eza -lah --group-directories-first --icons=auto'
end
command -q bat; and alias cat 'bat --paging=never --theme=ansi'
alias update 'sudo pacman -Syu'
alias grep 'grep --color=auto'
abbr -a g git
abbr -a gs 'git status -sb'
abbr -a gl 'git log --oneline --graph -15'
abbr -a gd 'git diff'

command -q zoxide; and zoxide init fish | source
command -q fzf; and fzf --fish | source

function y   # yazi: al salir, cd al directorio donde te quedaste
    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if set -l cwd (command cat -- "$tmp"); and test -n "$cwd"; and test "$cwd" != "$PWD"
        cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

# `if` y no `; and`: en shells anidadas (SHLVL > 1) la condición falla y el primer prompt saldría con ○
if test "$SHLVL" -le 1; and command -q fastfetch
    fastfetch
end
