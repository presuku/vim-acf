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
function! s:init_ctx() abort
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

function! s:sharplen(msg)
  let n_msg = strlen(a:msg)
  let n_sharp = 0
  let i = 0

  while i < n_msg
    let ch = a:msg[i]

    if ch ==# '#'
      let n_sharp = n_sharp + 1
    else
      break
    endif
    let i = i + 1
  endwhile

  return n_sharp
endfunction

function! s:DbgMsg(msg, ...) abort
  let dbg_lv = s:sharplen(a:msg)
  if l:dbg_lv < g:acf_debug
    if a:0 == 0
      let msg = a:msg
    else
      let msg = a:msg . ":" . string(a:000[0])
      for l:i in a:000[1:]
        let msg = l:msg . ', ' . string(l:i)
      endfor
    endif
    echomsg "Dbg" . ":" . l:msg
  endif
endfunction

function! s:compare(a, b) abort
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

let s:default_rule = {
      \ 'filetype': [],
      \ 'syntax': [],
      \ 'except': '',
      \ 'priority': 0,
      \ }

function! s:normalize_rule(rule)
  if !has_key(a:rule, 'at') || !has_key(a:rule, 'func')
    return {}
  endif

  " default rule copy to a:rule, and keep exist keys.
  let nrule = extend(deepcopy(a:rule), s:default_rule, 'keep')

  " filetype
  if type(l:nrule.filetype) !=# v:t_list
    let l:nrule.filetype = [nrule.filetype]
  endif
  if empty(l:nrule.filetype)
    " [] => ['_']
    let l:nrule.filetype = ['_']
  else
    " ['' , 'vim'] => ['_', 'vim']
    let i = index(l:nrule.filetype, '')
    if i > -1
      let l:nrule.filetype[i] = '_'
    endif
  endif

  " syntax
  if type(l:nrule.syntax) !=# v:t_list
    let l:nrule.syntax = [nrule.syntax]
  endif

  return l:nrule
endfunction


function! acf#add_rule(rule) abort
  " normalize user input.
  let nrule = s:normalize_rule(a:rule)
  if empty(l:nrule)
    echomsg 'ERROR: In acf#add_rule(), input rule is invalid:' . string(a:rule)
    return
  endif

  for l:ft in l:nrule.filetype
    if !has_key(s:rule_list, l:ft)
      let s:rule_list[l:ft] = [l:nrule]
    else
      if index(s:rule_list[l:ft], l:nrule) < 0
        call add(s:rule_list[l:ft], l:nrule)
      else
        call s:DbgMsg('### already exists a rule', a:rule)
        return
      endif

      call sort(s:rule_list[l:ft], {a, b -> s:compare(a, b)})
    endif
  endfor
endfunction

function! s:get_syntax_link_chain() abort
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
  call s:DbgMsg('## get_syntax_link_chain::syntax', synnames)

  return synnames
endfunction

function! s:execute_func(rule, startcol, base) abort
  call s:DbgMsg('### s:execute_func::a:rule', a:rule)
  call s:DbgMsg('### s:execute_func::a:startcol', a:startcol)
  call s:DbgMsg('### s:execute_func::a:base', a:base)

  let s:ctx.startcol = a:startcol
  let s:ctx.base = a:base
  let s:ctx.do_feedkeys = (string(a:rule.func) =~# "function('feedkeys'.*")
        \ ? a:rule
        \ : {}

  try
    call a:rule.func()
  catch
    call s:DbgMsg("### s:execute_func::some error", v:exception)
    return -1
  finally
    if pumvisible()
      call s:DbgMsg("### s:execute_func::has item(s)")
      return 1
    else
      if !empty(s:ctx.do_feedkeys)
        call s:DbgMsg('### s:execute_func::no item, but do_feedkeys')
        return 1
      else
        call s:DbgMsg("### s:execute_func::no item")
        return 0
      endif
    endif
  endtry
endfunction

function! s:get_completion(ft) abort
  let syntax_chain = s:get_syntax_link_chain()
  let [cb, cl, cc, co] =  getpos('.')
  let searchlimit = l:cl
  let ft = (a:ft ==# '') ? '_' : a:ft
  let result = 0

  call s:DbgMsg('## s:get_completion::ft', a:ft)
  let rules = has_key(s:rule_list, l:ft) ? s:rule_list[l:ft] : []
  for l:rule in rules
    call s:DbgMsg("### s:get_completion::rule", l:rule)
    call s:DbgMsg("### s:get_completion::do_feedkeys", s:ctx.do_feedkeys)
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
            call s:DbgMsg("### s:get_completion::syn", l:syn)
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
  call s:DbgMsg("## save pos", s:ctx.pos)
endfunction

function! s:get_saved_cursor_pos() abort
  call s:DbgMsg("## get saved pos", s:ctx.pos)
  return s:ctx.pos
endfunction

function! acf#stop_timer() abort
  call s:DbgMsg("acf#stop_timer")
  let info = timer_info(s:ctx.timer_id)
  if !empty(info)
    call s:DbgMsg("acf#stop_timer::stop timer!!")
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
    call s:DbgMsg(
          \ "s:cb_get_completion::callbacked in normal/virtual/other mode",
          \ s:ctx.mode)

    call acf#stop_timer()
    return
  endif

  " ix / Rx mode check
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'x'
    call s:DbgMsg("s:cb_get_completion::ctrlx ix/Rx mode", s:ctx.mode)
    let s:ctx.has_item = -1
    return
  endif

  " iV / RV
  " Add iV / RV / cV mode patch:
  " https://gist.github.com/presuku/fa7f351e792a9e74bfbd61684f0139ab
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'V'
    call s:DbgMsg("# s:cb_get_completion::ctrlx iV/RV/cV mode", s:ctx.mode)
    let s:ctx.has_item = -1
    return
  endif

  " ir / Rr
  " Add ir / Rr / cr mode patch:
  " https://gist.github.com/presuku/dc6bb11dfdb83535d82b1b6d7310e5bf
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'r'
    call s:DbgMsg("# s:cb_get_completion::ctrlx ir/Rr/cr mode", s:ctx.mode)
    let s:ctx.has_item = -1
    return
  endif

  if l:saved != l:current
    let s:ctx.has_item = -1
    let s:ctx.do_feedkeys = {}
    let s:ctx.completed_item_word = ""
    call s:DbgMsg("# s:cb_get_completion::cursor moved i")
    return
  endif

  if s:ctx.has_item == 0
    call s:DbgMsg("s:cb_get_completion::no item")
    return
  endif

  if pumvisible()
    call s:DbgMsg("## s:cb_get_completion::pumvisible")
    let s:ctx.do_feedkeys = {}
    return
  else
    " ic / Rc
    if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'c'
      let s:ctx.has_item = -1
      call feedkeys("\<C-e>", "n")
      call s:DbgMsg("# s:cb_get_completion::pum cancel (ctrlx ic/Rc mode)", s:ctx.mode)
      return
    endif
  endif

  call s:DbgMsg("# s:cb_get_completion::cursor hold i")
  try
    let save_shm = &l:shm
    setlocal shm&vim
    setlocal shm+=c
    let result = s:get_completion(&ft)
    if (l:result == 0) && (&ft != '')
      call s:DbgMsg("# s:cb_get_completion::fallback any filetype")
      let result = s:get_completion('')
    endif
    if l:result == 0
      call s:DbgMsg("# s:cb_get_completion::empty result")
      return
    endif
  finally
    let &l:shm = l:save_shm
    let s:ctx.has_item = !empty(s:ctx.do_feedkeys) ? -1 : l:result
    call s:DbgMsg("# s:cb_get_completion::has_item", s:ctx.has_item)
  endtry
endfunction

function! acf#set_timer() abort
  if g:acf_disable_auto_complete
    return
  endif
  call s:DbgMsg("acf#set_timer")
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
  call s:DbgMsg("## acf#complete_done", v:completed_item)
endfunction

function! acf#get_completion(manual) abort
  call s:DbgMsg("acf#get_completion")
  if a:manual
    call s:DbgMsg("acf#get_completion::manual")
    call acf#save_cursor_pos()
    let s:ctx.has_item = -1
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

