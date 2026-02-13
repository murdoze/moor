nnoremap LL :wa<CR>:make<CR>

set autoindent
set hlsearch
set incsearch
set isk+=-,!
set foldmethod=marker

nnoremap <silent> <PageUp> 25<Up>
nnoremap <silent> <PageDown> 25<Down>

command W write

iabbrev up <C-v>u2227
iabbrev down <C-v>u2228
iabbrev down2 <C-v>u22bb
iabbrev phii <C-v>u03c6
iabbrev bar <C-v>u0a6
iabbrev bb <C-v>u2588

function! SynGroup()
    let l:s = synID(line('.'), col('.'), 1)
    echo synIDattr(l:s, 'name') . ' -> ' . synIDattr(synIDtrans(l:s), 'name') . "\t fg=" . synIDattr(synIDtrans(l:s), "fg#") . " bg=" . synIDattr(synIDtrans(l:s), "bg#") . " bold=" . synIDattr(synIDtrans(l:s), "bold")
endfun


"nmap <C-\> :call SynGroup()<CR>
