" ==============================================================================
" FILE: plugin/acf.vim
" AUTHOR: presuku
" LICENSE: MIT license. see ../LICENSE.txt
" ==============================================================================
scripte utf-8

" ==============================================================================
" Load Once
if exists('g:loaded_acf')
    fini
en
let g:loaded_acf = 1

" ==============================================================================
" Version Check
if ! (has('timers')
      \ && has('lambda')
      \ && has('patch-8.0.0283')
      \)
  echom "vim-acf support vim8.0.0283 or later"
  fini
en

" ==============================================================================
" Save cpo
let s:save_cpo = &cpo
set cpo&vim

" ==============================================================================
com! AcfEnable cal acf#enable_timer()
com! AcfDisable cal acf#disable_timer()

" ==============================================================================
aug InitAcfEvent
  au!
  au InsertEnter * cal acf#set_timer()
  au InsertLeave * cal acf#stop_timer()
  au CompleteDone * cal acf#complete_done()
aug END

" ==============================================================================
ino <silent><buffer> <Plug>(acf-manual-complete)
      \ <C-r>=acf#get_completion(1)<CR>

" ==============================================================================
" Restore cpo
let &cpo = s:save_cpo
unl s:save_cpo

