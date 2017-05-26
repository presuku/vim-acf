" ==============================================================================
" FILE: plugin/acf.vim
" AUTHOR: presuku
" LICENSE: MIT license. see ../LICENSE.txt
" ==============================================================================
scriptencoding utf-8

" ==============================================================================
" Load Once
if exists('g:loaded_acf')
    finish
endif
let g:loaded_acf = 1

" ==============================================================================
" Version Check
if ! (has('timers')
      \ && has('lambda')
      \ && has('patch-8.0.0283')
      \)
  echom "vim-acf support vim8.0.0283 or later"
  finish
endif

" ==============================================================================
" Save cpo
let s:save_cpo = &cpo
set cpo&vim

" ==============================================================================
command! AcfEnable call acf#enable_timer()
command! AcfDisable call acf#disable_timer()

" ==============================================================================
augroup InitAcfEvent
  autocmd!
  autocmd InsertEnter * call acf#set_timer()
  autocmd InsertLeave * call acf#stop_timer()
  autocmd CompleteDone * call acf#complete_done()
augroup END

" ==============================================================================
inoremap <silent><buffer> <Plug>(acf-manual-complete)
      \ <C-r>=acf#get_completion(1)<CR>

" ==============================================================================
" Restore cpo
let &cpo = s:save_cpo
unlet s:save_cpo

