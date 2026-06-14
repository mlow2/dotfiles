#!/usr/bin/env bash
# ==========================================
# Dotfiles bootstrap / updater
# ==========================================
# Bare-repo dotfiles deploy and update tool. CLI-driven with interactive
# fallback. Idempotent: first run clones, later runs fetch + fast-forward.
# Use --help for full usage.

set -euo pipefail

# ---------- configuration ----------
REPO_URL="${DOTFILES_REPO:-https://github.com/mlow2/dotfiles.git}"
GIT_DIR="$HOME/.dotfiles.git"
BACKUP_ROOT="$HOME/.dotfiles_backup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"

# Component flags (0 = skip, 1 = install/update)
INSTALL_VIM=0
INSTALL_TMUX=0
INSTALL_BASH=0
INTERACTIVE=0

# ---------- helpers ----------
config() {
    /usr/bin/git --git-dir="$GIT_DIR" --work-tree="$HOME" "$@"
}

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
bootstrap.sh - bare-repo dotfiles deploy/update

Usage:
  bootstrap.sh                 Interactive prompts for each component
  bootstrap.sh [component ...] Non-interactive; install only the listed components

Components (any combination):
  --all          Vim + Tmux + Bash
  --vim          .vimrc, ~/.vim plugin dirs, vim-commentary, vscode_vim.jsonc
  --tmux         .tmux.conf
  --bash         .bashrc, .bash_common, .bash_secrets.example,
                 ~/.local/bin/pbcopy; seeds ~/.bash_secrets if missing
  --interactive  Force interactive prompts even when other flags are passed
  --help, -h     Show this help and exit

Environment:
  DOTFILES_REPO  Override repo URL
                 (default: https://github.com/mlow2/dotfiles.git)

Behavior:
  * First run: clones the bare repo into ~/.dotfiles.git, then checks out
    the selected components from HEAD.
  * Subsequent runs: fetches origin and selectively checks out the
    requested files from origin/<default-branch>. Local HEAD is then
    fast-forwarded (only when it is a strict ancestor of origin) so
    uninstalled components stay opted-out.
  * Collision-safe: for every file, the script compares the working-tree
    blob SHA against the target ref's blob. If they differ, the existing
    file is moved to ~/.dotfiles_backup/<timestamp>/ before the new
    version is restored. Nothing is ever overwritten silently.
  * Fails loudly when local HEAD has diverged from origin (e.g. unpushed
    + remote-altered history). Resolve manually with `config rebase`
    or `config log HEAD...origin/<branch>` before re-running.
USAGE
}

# Parse CLI flags. Sets INSTALL_* and INTERACTIVE.
parse_args() {
    if [ $# -eq 0 ]; then
        INTERACTIVE=1
        return
    fi
    while [ $# -gt 0 ]; do
        case "$1" in
            --all)         INSTALL_VIM=1; INSTALL_TMUX=1; INSTALL_BASH=1 ;;
            --vim)         INSTALL_VIM=1 ;;
            --tmux)        INSTALL_TMUX=1 ;;
            --bash)        INSTALL_BASH=1 ;;
            --interactive) INTERACTIVE=1 ;;
            --help|-h)     usage; exit 0 ;;
            *)             usage; die "unknown argument: $1" ;;
        esac
        shift
    done
}

# Prompt the user when in interactive mode. Overrides whatever flags set.
run_interactive_prompts() {
    log "Interactive mode. Press y/n for each component (default n)."
    local reply
    read -r -p "  Install/update Vim config?  (y/n) " reply
    [[ $reply =~ ^[Yy]$ ]] && INSTALL_VIM=1 || INSTALL_VIM=0
    read -r -p "  Install/update Tmux config? (y/n) " reply
    [[ $reply =~ ^[Yy]$ ]] && INSTALL_TMUX=1 || INSTALL_TMUX=0
    read -r -p "  Install/update Bash config? (y/n) " reply
    [[ $reply =~ ^[Yy]$ ]] && INSTALL_BASH=1 || INSTALL_BASH=0
}

# Clone the bare repo on first run; do nothing if it already exists.
# Sets JUST_CLONED=1 when we created the repo this invocation.
#
# `git clone --bare` does NOT configure a fetch refspec, so subsequent
# `git fetch origin` would leave refs/remotes/origin/* empty and break
# our update path. We add the standard refspec explicitly (idempotent).
JUST_CLONED=0
ensure_repo() {
    if [ -d "$GIT_DIR" ]; then
        log "Bare repo present at $GIT_DIR"
    else
        log "Cloning $REPO_URL into $GIT_DIR (bare)"
        git clone --bare "$REPO_URL" "$GIT_DIR"
        config config --local status.showUntrackedFiles no
        JUST_CLONED=1
    fi

    if ! config config --get-all remote.origin.fetch \
            | grep -qx '+refs/heads/\*:refs/remotes/origin/\*'; then
        log "Configuring fetch refspec on origin"
        config config --add remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
    fi
}

# Fetch from origin and decide which ref to check out from.
#
# We cannot do `config pull --ff-only` in a partial-deploy worktree:
# tracked files that the user never installed look like "local deletions"
# to git, so pull aborts with a delete-vs-modify conflict. Instead we
# fetch, point TARGET_REF at origin's tip, do per-file checkouts, and
# finalize by advancing local HEAD only when it is a strict ancestor of
# the target (i.e. clean fast-forward).
TARGET_REF=""
update_repo() {
    if [ "$JUST_CLONED" -eq 1 ]; then
        TARGET_REF="HEAD"
        log "Fresh clone; HEAD already matches origin."
        return
    fi

    log "Fetching latest from origin"
    config fetch --quiet origin

    local default_branch
    default_branch=$(config symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
    if [ -z "$default_branch" ]; then
        # Bare clones don't always have origin/HEAD; use local HEAD's branch.
        default_branch=$(config symbolic-ref --short HEAD 2>/dev/null || true)
    fi
    default_branch="${default_branch:-main}"
    TARGET_REF="origin/$default_branch"

    # Sanity-check the ref actually exists.
    if ! config rev-parse --verify --quiet "$TARGET_REF" >/dev/null; then
        die "Remote-tracking ref $TARGET_REF not found. Try: config fetch origin"
    fi

    # Sanity-check local HEAD vs origin to avoid silently rewriting
    # local-only commits (e.g. user edits committed but not yet pushed).
    local local_head target merge_base
    local_head=$(config rev-parse HEAD)
    target=$(config rev-parse "$TARGET_REF")
    if [ "$local_head" = "$target" ]; then
        return
    fi
    merge_base=$(config merge-base HEAD "$TARGET_REF" 2>/dev/null || true)
    if [ "$merge_base" = "$local_head" ]; then
        log "Origin is ahead by $(config rev-list --count "$local_head..$target") commit(s); will fast-forward after install."
    elif [ "$merge_base" = "$target" ]; then
        warn "Local HEAD is ahead of $TARGET_REF by $(config rev-list --count "$target..$local_head") commit(s)."
        warn "Sourcing files from local HEAD instead. Run 'config push' to share."
        TARGET_REF="HEAD"
    else
        die "Local HEAD has diverged from $TARGET_REF. Inspect with 'config log HEAD...$TARGET_REF' and rebase before re-running."
    fi
}

# Advance local HEAD to TARGET_REF after a successful install pass.
# Uses --mixed so the index moves with HEAD (uninstalled components
# remain as 'D' status, which accurately reflects the partial deploy)
# while the working tree is left untouched.
finalize_head() {
    if [ -z "$TARGET_REF" ] || [ "$TARGET_REF" = "HEAD" ] || [ "$JUST_CLONED" -eq 1 ]; then
        return
    fi
    local local_head target
    local_head=$(config rev-parse HEAD)
    target=$(config rev-parse "$TARGET_REF")
    [ "$local_head" = "$target" ] && return

    log "Advancing HEAD to $TARGET_REF"
    config reset --mixed --quiet "$TARGET_REF"
}

# Per-file safe checkout.
#
# Granular `git checkout HEAD -- <file>` would silently overwrite a colliding
# working-tree file with the tracked version, so we cannot rely on git to
# protect the user. Instead, for each file we compare the working-tree blob
# SHA against HEAD's blob SHA; if they differ, the working-tree copy is moved
# under $BACKUP_DIR/<file> before we let git restore the tracked version.
#
# This path is identical on first install and on updates: no special-casing
# for JUST_CLONED, no parsing of error messages, no fallback. If the user
# kept uncommitted edits, they end up safely under ~/.dotfiles_backup/<ts>/.
checkout_files() {
    local files=("$@")
    local f target_blob old_blob local_hash dest
    for f in "${files[@]}"; do
        # Target blob: what the new version should be. Fails loudly if untracked.
        if ! target_blob=$(config rev-parse "$TARGET_REF:$f" 2>/dev/null); then
            die "$f is not tracked in the bare repo at $TARGET_REF; cannot checkout"
        fi
        # Old blob: what the previously-installed version was (HEAD before
        # any update this run). Used to distinguish "clean upgrade" from
        # "user has local edits". Empty if file was not previously tracked.
        old_blob=$(config rev-parse "HEAD:$f" 2>/dev/null || true)

        if [ -e "$HOME/$f" ]; then
            local_hash=$(git hash-object -- "$HOME/$f")
            if [ "$local_hash" = "$target_blob" ]; then
                # Already at target version. Run checkout anyway so the
                # index entry is refreshed (cheap, no-op on disk).
                config checkout "$TARGET_REF" -- "$f"
                continue
            fi
            if [ -n "$old_blob" ] && [ "$local_hash" = "$old_blob" ]; then
                # Clean upgrade from old tracked version to new; no backup.
                log "Updating $f ($old_blob -> $target_blob)"
                config checkout "$TARGET_REF" -- "$f"
                continue
            fi
            # Local file diverges from both old and new tracked state.
            dest="$BACKUP_DIR/$f"
            mkdir -p "$(dirname "$dest")"
            mv "$HOME/$f" "$dest"
            log "Backed up locally-modified $f -> $dest"
        fi

        config checkout "$TARGET_REF" -- "$f"
    done
}

# ---------- components ----------
install_vim() {
    log "Component: vim"
    mkdir -p "$HOME/.vim/undodir" "$HOME/.vim/tmp" "$HOME/.vim/pack/tpope/start"

    if [ ! -d "$HOME/.vim/pack/tpope/start/vim-commentary/.git" ]; then
        log "Cloning vim-commentary plugin"
        git clone --quiet https://github.com/tpope/vim-commentary.git \
            "$HOME/.vim/pack/tpope/start/vim-commentary"
    else
        log "vim-commentary already installed; skipping clone"
    fi

    local files=(.vimrc)
    # vim2code.py is tracked alongside .vimrc; pull it in too if available.
    if config cat-file -e "$TARGET_REF:vim2code.py" 2>/dev/null; then
        files+=(vim2code.py)
    fi

    checkout_files "${files[@]}"

    generate_vscode_vim
}

install_tmux() {
    log "Component: tmux"
    local files=(.tmux.conf)
    checkout_files "${files[@]}"
}

install_bash() {
    log "Component: bash"

    local files=(.bashrc .bash_common .bash_secrets.example)
    # Tolerate older repos that only track .bashrc.
    local resolved=()
    for f in "${files[@]}"; do
        if config cat-file -e "$TARGET_REF:$f" 2>/dev/null; then
            resolved+=("$f")
        else
            warn "$f is not tracked in the repo at $TARGET_REF; skipping"
        fi
    done
    if [ ${#resolved[@]} -eq 0 ]; then
        die "No bash files are tracked in the repo. Nothing to install."
    fi
    checkout_files "${resolved[@]}"

    # Install the standalone pbcopy script for non-interactive contexts
    # (xargs pbcopy, scripts where the shell function is not loaded).
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/pbcopy" <<'PBCOPY'
#!/usr/bin/env bash
cat | base64 | tr -d '\n' | awk '{printf "\033]52;c;%s\a", $0}'
PBCOPY
    chmod +x "$HOME/.local/bin/pbcopy"
    log "Installed ~/.local/bin/pbcopy"

    # Seed ~/.bash_secrets from the tracked example on first install only.
    # Never overwrite a real ~/.bash_secrets that the user has customized.
    if [ -f "$HOME/.bash_secrets.example" ] && [ ! -f "$HOME/.bash_secrets" ]; then
        cp "$HOME/.bash_secrets.example" "$HOME/.bash_secrets"
        log "Seeded ~/.bash_secrets from .bash_secrets.example (edit it for this machine)"
    fi

    # Guarantee .bashrc sources .bash_common, even if the user's local
    # .bashrc was kept (e.g. a distro default that isn't tracked).
    if [ -f "$HOME/.bashrc" ] && ! grep -Fq '.bash_common' "$HOME/.bashrc"; then
        log "Appending .bash_common sourcing line to ~/.bashrc"
        cat >> "$HOME/.bashrc" <<'BASHRC_APPEND'

# Added by dotfiles bootstrap.sh
[ -f ~/.bash_common ] && . ~/.bash_common
BASHRC_APPEND
    fi
}

# ---------- vim2code.py wiring ----------
# Bootstrap-time generation only (no git hook). Runs the tracked vim2code.py
# against the freshly-checked-out .vimrc and writes the JSONC artifact to
# $HOME/vscode_vim.jsonc. The artifact is intentionally untracked: VSCode
# settings.json is per-machine, and we never want to overwrite it blindly.
generate_vscode_vim() {
    local script="$HOME/vim2code.py"
    local output="$HOME/vscode_vim.jsonc"

    if [ ! -f "$script" ]; then
        warn "vim2code.py not present in repo; skipping VSCode Vim translation"
        return
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found; skipping vim2code.py. Install python3 and re-run --vim to regenerate."
        return
    fi

    log "Generating VSCode Vim settings via vim2code.py"
    ( cd "$HOME" && python3 "$script" ) > "$output"
    log "Wrote $output"

    cat <<EOF
    NOTE: $output is JSONC (JSON + // comments) and contains only the
    VSCode Vim emulator settings translated from your .vimrc.
    Merge the contents into your VSCode settings.json:
      macOS: ~/Library/Application Support/Code/User/settings.json
      Linux: ~/.config/Code/User/settings.json
    Review the leading "UNSUPPORTED FEATURES" comment block (if any) for
    mappings that the VSCode Vim emulator cannot represent.
EOF
}

# ---------- main ----------
main() {
    parse_args "$@"

    if [ "$INTERACTIVE" -eq 1 ]; then
        run_interactive_prompts
    fi

    if [ "$INSTALL_VIM" -eq 0 ] && [ "$INSTALL_TMUX" -eq 0 ] && [ "$INSTALL_BASH" -eq 0 ]; then
        log "Nothing selected. Exiting without changes."
        exit 0
    fi

    ensure_repo
    update_repo

    [ "$INSTALL_VIM"  -eq 1 ] && install_vim
    [ "$INSTALL_TMUX" -eq 1 ] && install_tmux
    [ "$INSTALL_BASH" -eq 1 ] && install_bash

    finalize_head

    log "Done. Open a new shell or run: source ~/.bashrc"
}

main "$@"
