" ==============================================================================
" FILE: autoload/acf.vim
" AUTHOR: presuku
" LICENSE: MIT license. see ../LICENSE.txt
" ==============================================================================
scriptencoding utf-8

" ==============================================================================
" Version Check
if ! (has('timers')
      \ && has('lambda')
      \ && has('patch-8.0.0283')
      \)
  finish
endif

" ==============================================================================
" Save cpo {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}

" ==============================================================================
" Init variables
if !exists('g:acf_update_time')
  let g:acf_update_time = 250
endif

if !exists('g:acf_disable_auto_complete')
  let g:acf_disable_auto_complete = 0
endif

if !exists('g:acf_use_default_mapping')
  let g:acf_use_default_mapping = 0
endif

if !exists('g:acf_debug')
  let g:acf_debug = 0
endif

" ==============================================================================
if exists('g:acf_use_default_mapping')
      \ && g:acf_use_default_mapping
  inoremap <expr><silent><buffer> <CR> pumvisible() ? '<C-y><CR>' : '<CR>'
  inoremap <expr><silent><buffer> <TAB> pumvisible() ? '<DOWN>' : '<TAB>'
  inoremap <expr><silent><buffer> <S-TAB> pumvisible() ? '<UP>' : '<S-TAB>'
  imap <expr><silent><buffer> <C-n> pumvisible() ? '<C-n>' : '<Plug>(acf-manual-complete)'
endif

" ==============================================================================
function! s:init_ctx()
  return {
      \ 'pos'        : [],
      \ 'timer_id'   : -1,
      \ 'has_item'   : -1,
      \ 'startcol'   : 0,
      \ 'base'       : "",
      \ 'do_feedkeys': {},
      \ 'completed_item_word' : ""
      \}
endfunction

let s:ctx = s:init_ctx()

let s:rule_list = {}

function! s:DebugMsg(level, msg, ...) abort
  if a:level < g:acf_debug
    if a:0 == 0
      let msg = a:msg
    else
      let msg = a:msg . ":" . string(a:000[0])
      for l:i in a:000[1:]
        let msg = l:msg . ', ' . string(l:i)
      endfor
    endif
    echomsg "Debug" . string(a:level) . ":" . l:msg
  endif
endfunction

function! s:compare(a, b)
  " function! s:sub_cmp(a, b)
  "     return (a:a > a:b) ? 1 : ((a:a < a:b) ? -1 : 0)
  " endfunction
  let s:sub_cmp = {a, b->(a > b) ? 1 : ((a < b) ? -1 : 0)}
  let r = s:sub_cmp(a:a.priority, a:b.priority)
  if l:r != 0
    return r
  endif
  let r = s:sub_cmp(len(a:a.at), len(a:b.at))
  if l:r != 0
    return r
  endif
  let r = s:sub_cmp(len(a:a.except), len(a:b.except))
  if l:r != 0
    return r
  endif
  let r = s:sub_cmp(len(a:a.syntax), len(a:b.syntax))
  if l:r != 0
    return r
  endif
  return 0
endfunction

function! acf#add_rule(rule)
  if type(a:rule.filetype) == v:t_list
    let filetypes = a:rule.filetype
    let i = index(filetypes, '')
    if i != -1
      let filetypes[i] = '_'
    endif
  else
    let filetypes = empty(a:rule.filetype) ? ['_'] : [a:rule.filetype]
  endif

  for l:ft in l:filetypes
    if !has_key(s:rule_list, l:ft)
      let s:rule_list[l:ft] = [a:rule]
    else
      if index(s:rule_list[l:ft], a:rule) < 0
        call add(s:rule_list[l:ft], a:rule)
      else
        call s:DebugMsg(3, 'already exists a rule', a:rule)
        return
      endif

      call sort(s:rule_list[l:ft], {a, b -> s:compare(a, b)})
    endif
  endfor
endfunction

function! s:get_syntax_link_chain()
  let [b, l, c, o] =  getpos('.')
  let synid = synID(l, c, 1)

  let synids = []
  call add(synids, synid)
  while 1
    let trans_synid = synIDtrans(synid)
    if synid == trans_synid
      break
    else
      call add(synids, trans_synid)
    endif
    let synid = trans_synid
  endwhile

  let synnames =  map(synids, {key, val->synIDattr(val, "name")})
  call s:DebugMsg(2, 'syntax', synnames)

  return synnames
endfunction

function! s:execute_func(rule, startcol, base)
  call s:DebugMsg(3, 'a:rule', a:rule)
  call s:DebugMsg(3, 'a:startcol', a:startcol)
  call s:DebugMsg(3, 'a:base', a:base)

  let s:ctx.startcol = a:startcol
  let s:ctx.base = a:base
  let s:ctx.do_feedkeys = (string(a:rule.func) =~# "function('feedkeys'.*")
        \ ? a:rule
        \ : {}

  try
    call a:rule.func()
  catch
    call s:DebugMsg(3, "some error", v:exception)
    return -1
  finally
    if pumvisible()
      call s:DebugMsg(3, "has item(s)")
      return 1
    else
      if !empty(s:ctx.do_feedkeys)
        call s:DebugMsg(3, 'no item, but do_feedkeys')
        return 1
      else
        call s:DebugMsg(3, "no item")
        return 0
      endif
    endif
  endtry
endfunction

function! s:get_completion(ft)
  let syntax_chain = s:get_syntax_link_chain()
  let [cb, cl, cc, co] =  getpos('.')
  let searchlimit = l:cl
  let ft = (a:ft ==# '') ? '_' : a:ft
  let result = 0

  call s:DebugMsg(2, 'a:ft', a:ft)
  let rules = has_key(s:rule_list, l:ft) ? s:rule_list[l:ft] : []
  for l:rule in rules
    call s:DebugMsg(3, "###rurles###", l:rule)
    call s:DebugMsg(3, "###do_feedkeys###", s:ctx.do_feedkeys)
    if !empty(s:ctx.do_feedkeys)
      if l:rule != s:ctx.do_feedkeys
        continue
      else
        let s:ctx.do_feedkeys = {}
        continue
      endif
    endif
    let [sl, sc] = searchpos(rule.at, 'bcWn', searchlimit)
    let excepted = has_key(rule, 'except') ?
          \ searchpos(rule.except, 'bcWn', searchlimit) !=# [0, 0] : 0
    if [sl, sc] !=# [0, 0] && !excepted
      let base = getline('.')[sc-1:cc]
      if base ==# s:ctx.completed_item_word
        return 0
      endif
      if !has_key(rule, 'syntax') || empty(rule.syntax)
        let result = s:execute_func(rule, l:sc, l:base)
        if l:result
          return l:result
        endif
      else
        for l:syn in syntax_chain
          if index(rule.syntax, syn) >=# 0
            call s:DebugMsg(3, 'l:syn', l:syn)
            let result = s:execute_func(rule, l:sc, l:base)
            if l:result
              return l:result
            else
              break
            endif
          endif
        endfor
      endif
    endif
  endfor

  return l:result
endfunction

function! acf#save_cursor_pos() abort
  let s:ctx.pos = getpos('.')
  call s:DebugMsg(2, "save pos", s:ctx.pos)
endfunction

function! s:get_saved_cursor_pos() abort
  call s:DebugMsg(2, "get saved pos", s:ctx.pos)
  return s:ctx.pos
endfunction

function! acf#stop_timer() abort
  call s:DebugMsg(0, "stop timer::")
  let info = timer_info(s:ctx.timer_id)
  if !empty(info)
    call s:DebugMsg(0, "stop timer::stop!!")
    call timer_stop(s:ctx.timer_id)
  endif
  let s:ctx = s:init_ctx()
endfunction

function! s:cb_get_completion(timer_id) abort
  let ok_mode = ['i', 'R']
  let s:ctx.mode = mode(1)
  let l:saved = s:get_saved_cursor_pos()
  let l:current = getpos('.')
  call acf#save_cursor_pos()

  " mode check
  if index(ok_mode, s:ctx.mode[0]) < 0
    call s:DebugMsg(0,
          \ "cb_get_completion::callbacked in normal/virtual/other mode",
          \ s:ctx.mode)

    call acf#stop_timer()
    let s:ctx.has_item = -1
    return
  endif

  " ix / Rx mode check
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'x'
    call s:DebugMsg(1, "cb_get_completion::ctrlx ix/Rx mode", s:ctx.mode)
    let s:ctx.has_item = -1
    return
  endif

  " iV / RV
  " Add iV / RV / cV mode patch:
  " https://gist.github.com/presuku/fa7f351e792a9e74bfbd61684f0139ab
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'V'
    call s:DebugMsg(1, "cb_get_completion::ctrlx iV/RV/cV mode", s:ctx.mode)
    let s:ctx.has_item = -1
    return
  endif

  if l:saved != l:current
    let s:ctx.has_item = -1
    let s:ctx.do_feedkeys = {}
    let s:ctx.completed_item_word = ""
    call s:DebugMsg(1, "cb_get_completion::cursor moved i")
    return
  endif

  if s:ctx.has_item == 0
    call s:DebugMsg(0, "cb_get_completion::no item")
    return
  endif

  if pumvisible()
    call s:DebugMsg(2, "cb_get_completion::pumvisible")
    let s:ctx.do_feedkeys = {}
    return
  else
    " ic / Rc
    if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'c'
      let s:ctx.has_item = -1
      call feedkeys("\<C-e>", "n")
      call s:DebugMsg(1, "cb_get_completion::pum cancel (ctrlx ic/Rc mode)", s:ctx.mode)
      return
    endif
  endif

  call s:DebugMsg(1, "cb_get_completion::cursor hold i")
  try
    let save_shm = &l:shm
    setlocal shm&vim
    setlocal shm+=c
    let result = s:get_completion(&ft)
    if (l:result == 0) && (&ft != '')
      call s:DebugMsg(1, 'cb_get_completion::fallback any filetype')
      let result = s:get_completion('')
    endif
    if l:result == 0
      call s:DebugMsg(1, 'cb_get_completion::empty result')
      return
    endif
  finally
    let &l:shm = l:save_shm
    let s:ctx.has_item = !empty(s:ctx.do_feedkeys) ? -1 : l:result
    call s:DebugMsg(1, 'cb_get_completion::has_item', s:ctx.has_item)
  endtry
endfunction

function! acf#set_timer() abort
  if g:acf_disable_auto_complete
    return
  endif
  call s:DebugMsg(0, "set timer::")
  call acf#stop_timer()
  call acf#get_completion(0)
  let s:ctx.timer_id =
        \ timer_start(g:acf_update_time,
        \             function('s:cb_get_completion'),
        \             {'repeat':-1}
        \ )
endfunction

function! acf#enable_timer() abort
  let g:acf_disable_auto_complete = 0
endfunction

function! acf#disable_timer() abort
  call acf#stop_timer()
  let g:acf_disable_auto_complete = 1
endfunction

function! acf#complete_done() abort
  call acf#save_cursor_pos()
  if has_key(v:completed_item, 'word')
    let s:ctx.completed_item_word = v:completed_item['word']
  else
    let s:ctx.completed_item_word = ""
  endif
  call s:DebugMsg(2, "CompleteDone", v:completed_item)
endfunction

function! acf#get_completion(manual) abort
  if a:manual
    call s:DebugMsg(0, "acf#get_completion::manual")
    call acf#save_cursor_pos()
    let s:ctx.do_feedkeys = {}
    let s:ctx.completed_item_word = ""
  endif
  call s:cb_get_completion(-1)
  return ""
endfunction

function! acf#get_context() abort
  return s:ctx
endfunction

" ==============================================================================
" Restore cpo
let &cpo = s:save_cpo

