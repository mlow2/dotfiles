#!/bin/bash
# ==========================================
# Automated Dotfiles Deployment
# ==========================================

echo "Starting dotfiles setup..."

# 1. Create necessary directory structures
mkdir -p ~/.vim/{undodir,tmp,pack/tpope/start} ~/.local/bin

# 2. Clone vim-commentary plugin silently
git clone https://github.com/tpope/vim-commentary.git ~/.vim/pack/tpope/start/vim-commentary 2>/dev/null || true

# 3. Setup the bare git repository
git clone --bare https://github.com/mlow2/dotfiles.git $HOME/.dotfiles.git
function config {
   /usr/bin/git --git-dir=$HOME/.dotfiles.git/ --work-tree=$HOME "$@"
}

# 4. Checkout the files (Backing up existing files if they conflict)
echo "Checking out dotfiles..."
config checkout 2>/dev/null
if [ $? = 0 ]; then
  echo "Checked out dotfiles."
else
  echo "Backing up pre-existing dotfiles..."
  mkdir -p ~/.dotfiles_backup
  config checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | xargs -I{} mv {} ~/.dotfiles_backup/{}
  config checkout
fi

# 5. Hide untracked files in the status view
config config --local status.showUntrackedFiles no

# 6. Generate the pbcopy script natively (avoids tracking OS-specific bin folders)
cat << 'EOF' > ~/.local/bin/pbcopy
#!/bin/bash
cat | base64 | tr -d '\n' | awk '{printf "\033]52;c;%s\a", $0}'
EOF
chmod +x ~/.local/bin/pbcopy

echo "Setup complete! Please run: source ~/.bashrc"
