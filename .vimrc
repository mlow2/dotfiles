" ==============================================================================
" >>>                          CORE VIM SETTINGS                             <<<
" ==============================================================================

" --- General ---
set nocompatible            " Don't be Vi-compatible
syntax on                   " Enable syntax highlighting
filetype plugin indent on   " Enable filetype-based indentation

" --- Line Numbers ---
set number                  " Absolute line number for current line
set relativenumber          " Relative line numbers for others

" --- Indentation ---
set tabstop=4               " Number of spaces a <Tab> counts for
set shiftwidth=4            " Spaces for each level of (auto)indent
set expandtab               " Use spaces instead of tabs
set smartindent             " Auto-indent new lines

" --- Search ---
set ignorecase              " Case-insensitive search...
set smartcase               " ...unless uppercase letters are used
set incsearch               " Highlight while typing
set hlsearch                " Highlight search results

" --- Interface ---
set cursorline              " Highlight the current line
set scrolloff=10            " Keep 10 lines above/below cursor
set showcmd                 " Show incomplete commands
set wildmenu                " Enhanced command-line completion
set lazyredraw              " Redraw only when needed (faster)
set mouse=a                 " Enable mouse support

" --- Backups & Undo ---
set undofile                " Persistent undo
set undodir=~/.vim/undodir  " Set the undo directory
set backupdir=~/.vim/tmp//  " Keep backup files in a safe place
set directory=~/.vim/tmp//  " Swap files location

" --- Misc ---
set encoding=utf-8
set timeout
set timeoutlen=500          " Timeout for mapped sequences after <leader>

" ==============================================================================
" >>>                         CUSTOM KEY MAPPINGS                            <<<
" ==============================================================================

" --- Leader Key Setup ---
let mapleader = " "
nnoremap <Space> :noh<CR>   " Space clears search highlight

" --- Safe Registers (Black Hole & Vault) ---
" Delete into the void (preserves clipboard)
nnoremap <leader>d "_d
vnoremap <leader>d "_d
" Paste the last explicitly yanked text
nnoremap <leader>P "0p
vnoremap <leader>P "0p

" --- Clipboard (Cross-Platform / SSH / macOS Bridge) ---
" Yank to system clipboard using pbcopy (OSC 52 over SSH, or native on Mac)
vnoremap <leader>y :w !pbcopy<CR><CR>
nnoremap <leader>Y :.w !pbcopy<CR><CR>

" ==============================================================================
" >>>                 LATEX & TEXT OBJECT CUSTOMIZATIONS                     <<<
" ==============================================================================

" --- 1. VISUAL MODE BINDS (The Text Objects) ---
" Inside math: jumps back after first $, swaps sides, jumps forward before second $
vnoremap i$ T$ot$
" Around math: jumps onto first $, starts visual, jumps onto second $
vnoremap a$ F$vf$

" --- 2. NORMAL MODE BINDS (Recursive - MUST BE 'nmap') ---
" Inside Math ($)
nmap ci$ vi$c
nmap di$ vi$d
nmap yi$ vi$y

" Around Math ($)
nmap ca$ va$c
nmap da$ va$d
nmap ya$ va$y

" --- 3. CUSTOM ACTIONS & OVERRIDES (Non-Recursive) ---
" Line navigation
nnoremap H ^
nnoremap L $
nnoremap j gj
nnoremap k gk
nnoremap Y y$

" Paragraph jumping with screen centering
nnoremap K {zz
nnoremap J }zz
vnoremap K {zz
vnoremap J }zz

" File top/bottom jumping with screen centering
nnoremap gg ggzz
nnoremap G Gzz

" LaTeX Environment Jumpers with screen centering
nnoremap ]e /\\end{<CR>zz
nnoremap [e ?\\begin{<CR>zz

" Fast inline math generation in Insert mode
inoremap $$ $$<Left>

" Search jumping with screen centering
nnoremap n nzz
nnoremap N Nzz

" Center the screen immediately after hitting Enter on a new search
cnoremap <expr> <CR> getcmdtype() =~ '[/?]' ? "<CR>zz" : "<CR>"
