" ==============================================================================
" FILE: autoload/acf.vim
" AUTHOR: presuku
" LICENSE: MIT license. see ../LICENSE.txt
" ==============================================================================
scripte utf-8

" ==============================================================================
" Version Check
if ! (has('timers')
      \ && has('lambda')
      \ && has('patch-8.0.0283')
      \)
  finish
en

" ==============================================================================
" Save cpo {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}

" ==============================================================================
" Init variables
if !exists('g:acf_update_time')
  let g:acf_update_time = 250
en

if !exists('g:acf_disable_auto_complete')
  let g:acf_disable_auto_complete = 0
en

if !exists('g:acf_use_default_mapping')
  let g:acf_use_default_mapping = 0
en

if !exists('g:acf_debug')
  let g:acf_debug = 0
en

" ==============================================================================
if exists('g:acf_use_default_mapping')
      \ && g:acf_use_default_mapping
  ino <expr><silent><buffer> <CR> pumvisible() ? '<C-y><CR>' : '<CR>'
  ino <expr><silent><buffer> <TAB> pumvisible() ? '<DOWN>' : '<TAB>'
  ino <expr><silent><buffer> <S-TAB> pumvisible() ? '<UP>' : '<S-TAB>'
  im <expr><silent><buffer> <C-n> pumvisible() ? '<C-n>' : '<Plug>(acf-manual-complete)'
en

" ==============================================================================
fu! s:init_ctx() abort
  retu {
      \ 'pos'        : [],
      \ 'timer_id'   : -1,
      \ 'has_item'   : -1,
      \ 'startcol'   : 0,
      \ 'base'       : "",
      \ 'do_feedkeys': {},
      \ 'ciword' : ""
      \}
endf

let s:ctx = s:init_ctx()

let s:rule_list = {}

fu! s:hashlen(msg)
  let n_msg = strlen(a:msg)
  let n_hash = 0
  let i = 0

  wh i < n_msg
    let ch = a:msg[i]

    if ch ==# '#'
      let n_hash = n_hash + 1
    el
      brea
    en
    let i = i + 1
  endw

  retu n_hash
endf

fu! s:DbgMsg(msg, ...) abort
  let dbg_lv = s:hashlen(a:msg)
  if l:dbg_lv < g:acf_debug
    if a:0 == 0
      let msg = a:msg
    el
      let msg = a:msg . ":" . string(a:000[0])
      for l:i in a:000[1:]
        let msg = l:msg . ', ' . string(l:i)
      endfo
    en
    echom "Dbg" . ":" . l:msg
  en
endf

fu! s:compare(a, b) abort
  let s:sub_cmp = {a, b->(a > b) ? 1 : ((a < b) ? -1 : 0)}
  let r = s:sub_cmp(a:a.priority, a:b.priority)
  if l:r != 0
    retu r
  en
  let r = s:sub_cmp(len(a:a.at), len(a:b.at))
  if l:r != 0
    retu r
  en
  let r = s:sub_cmp(len(a:a.except), len(a:b.except))
  if l:r != 0
    retu r
  en
  let r = s:sub_cmp(len(a:a.syntax), len(a:b.syntax))
  if l:r != 0
    retu r
  en
  retu 0
endf

let s:default_rule = {
      \ 'filetype': [],
      \ 'syntax': [],
      \ 'except': '',
      \ 'priority': 0,
      \ }

fu! s:normalize_rule(rule)
  if !has_key(a:rule, 'at') || !has_key(a:rule, 'func')
    retu {}
  en

  " default rule copy to a:rule, and keep exist keys.
  let nrule = extend(deepcopy(a:rule), s:default_rule, 'keep')

  " filetype
  if type(l:nrule.filetype) !=# v:t_list
    let l:nrule.filetype = [nrule.filetype]
  en
  if empty(l:nrule.filetype)
    " [] => ['_']
    let l:nrule.filetype = ['_']
  el
    " ['' , 'vim'] => ['_', 'vim']
    let i = index(l:nrule.filetype, '')
    if i > -1
      let l:nrule.filetype[i] = '_'
    en
  en

  " syntax
  if type(l:nrule.syntax) !=# v:t_list
    let l:nrule.syntax = [nrule.syntax]
  en

  retu l:nrule
endf


fu! acf#add_rule(rule) abort
  " normalize user input.
  let nrule = s:normalize_rule(a:rule)
  if empty(l:nrule)
    echom 'ERROR: In acf#add_rule(), input rule is invalid:' . string(a:rule)
    retu
  en

  for l:ft in l:nrule.filetype
    if !has_key(s:rule_list, l:ft)
      let s:rule_list[l:ft] = [l:nrule]
    el
      if index(s:rule_list[l:ft], l:nrule) < 0
        cal add(s:rule_list[l:ft], l:nrule)
      el
        cal s:DbgMsg('### already exists a rule', a:rule)
        retu
      en

      cal sort(s:rule_list[l:ft], {a, b -> s:compare(a, b)})
    en
  endfo
endf

fu! s:get_syntax_link_chain() abort
  let [b, l, c, o] =  getpos('.')
  let synid = synID(l, c, 1)

  let synids = []
  cal add(synids, synid)
  while 1
    let trans_synid = synIDtrans(synid)
    if synid == trans_synid
      brea
    el
      cal add(synids, trans_synid)
    en
    let synid = trans_synid
  endw

  let synnames =  map(synids, {key, val->synIDattr(val, "name")})
  cal s:DbgMsg('## get_syntax_link_chain::syntax', synnames)

  retu synnames
endf

fu! s:execute_func(rule, startcol, base) abort
  cal s:DbgMsg('### s:execute_func::a:rule', a:rule)
  cal s:DbgMsg('### s:execute_func::a:startcol', a:startcol)
  cal s:DbgMsg('### s:execute_func::a:base', a:base)

  let s:ctx.startcol = a:startcol
  let s:ctx.base = a:base
  let s:ctx.do_feedkeys = (string(a:rule.func) =~# "function('feedkeys'.*")
        \ ? a:rule
        \ : {}

  try
    cal a:rule.func()
  cat
    cal s:DbgMsg("### s:execute_func::some error", v:exception)
    retu -1
  fina
    if pumvisible()
      cal s:DbgMsg("### s:execute_func::has item(s)")
      retu 1
    el
      if !empty(s:ctx.do_feedkeys)
        cal s:DbgMsg('### s:execute_func::no item, but do_feedkeys')
        retu 1
      el
        cal s:DbgMsg("### s:execute_func::no item")
        retu 0
      en
    en
  endt
endf

fu! s:get_completion(ft) abort
  let syntax_chain = s:get_syntax_link_chain()
  let [cb, cl, cc, co] =  getpos('.')
  let searchlimit = l:cl
  let ft = (a:ft ==# '') ? '_' : a:ft
  let result = 0

  cal s:DbgMsg('## s:get_completion::ft', a:ft)
  let rules = has_key(s:rule_list, l:ft) ? s:rule_list[l:ft] : []
  for l:rule in rules
    cal s:DbgMsg("### s:get_completion::rule", l:rule)
    cal s:DbgMsg("### s:get_completion::do_feedkeys", s:ctx.do_feedkeys)
    if !empty(s:ctx.do_feedkeys)
      if l:rule != s:ctx.do_feedkeys
        con
      el
        let s:ctx.do_feedkeys = {}
        con
      en
    en
    let [sl, sc] = searchpos(rule.at, 'bcWn', searchlimit)
    let excepted = has_key(rule, 'except') ?
          \ searchpos(rule.except, 'bcWn', searchlimit) !=# [0, 0] : 0
    if [sl, sc] !=# [0, 0] && !excepted
      let base = getline('.')[sc-1:cc]
      cal s:DbgMsg("### s:get_completion::base, s:ctx.ciword", base, s:ctx.ciword)
      if base[-strlen(s:ctx.ciword):] ==# s:ctx.ciword
        retu 0
      en
      if !has_key(rule, 'syntax') || empty(rule.syntax)
        let result = s:execute_func(rule, l:sc, l:base)
        if l:result
          retu l:result
        en
      el
        for l:syn in syntax_chain
          if index(rule.syntax, syn) >=# 0
            cal s:DbgMsg("### s:get_completion::syn", l:syn)
            let result = s:execute_func(rule, l:sc, l:base)
            if l:result
              retu l:result
            el
              brea
            en
          en
        endfo
      en
    en
  endfo

  retu l:result
endf

fu! acf#save_cursor_pos() abort
  let s:ctx.pos = getpos('.')
  cal s:DbgMsg("## save pos", s:ctx.pos)
endf

fu! s:get_saved_cursor_pos() abort
  cal s:DbgMsg("## get saved pos", s:ctx.pos)
  retu s:ctx.pos
endf

fu! acf#stop_timer() abort
  cal s:DbgMsg("acf#stop_timer")
  let info = timer_info(s:ctx.timer_id)
  if !empty(info)
    cal s:DbgMsg("acf#stop_timer::stop timer!!")
    cal timer_stop(s:ctx.timer_id)
  en
  let s:ctx = s:init_ctx()
  let &shm = b:save_shm
  let b:save_shm = ''
endf

fu! s:cb_get_completion(timer_id) abort
  let ok_mode = ['i', 'R']
  let s:ctx.mode = mode(1)
  let l:saved = s:get_saved_cursor_pos()
  let l:current = getpos('.')
  cal acf#save_cursor_pos()

  " mode check
  if index(ok_mode, s:ctx.mode[0]) < 0
    cal s:DbgMsg(
          \ "s:cb_get_completion::callbacked in normal/virtual/other mode",
          \ s:ctx.mode)

    cal acf#stop_timer()
    retu
  en

  " ix / Rx mode check
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'x'
    cal s:DbgMsg("s:cb_get_completion::ctrlx ix/Rx mode", s:ctx.mode)
    let s:ctx.has_item = -1
    retu
  en

  " iV / RV
  " Add iV / RV / cV mode patch:
  " https://gist.github.com/presuku/fa7f351e792a9e74bfbd61684f0139ab
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'V'
    cal s:DbgMsg("# s:cb_get_completion::ctrlx iV/RV/cV mode", s:ctx.mode)
    let s:ctx.has_item = -1
    retu
  en

  " ir / Rr
  " Add ir / Rr / cr mode patch:
  " https://gist.github.com/presuku/dc6bb11dfdb83535d82b1b6d7310e5bf
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'r'
    cal s:DbgMsg("# s:cb_get_completion::ctrlx ir/Rr/cr mode", s:ctx.mode)
    let s:ctx.has_item = -1
    retu
  en

  if l:saved != l:current
    let s:ctx.has_item = -1
    let s:ctx.do_feedkeys = {}
    let s:ctx.ciword = ""
    cal s:DbgMsg("# s:cb_get_completion::cursor moved i")
    retu
  en

  if s:ctx.has_item == 0
    cal s:DbgMsg("s:cb_get_completion::no item")
    retu
  en

  if pumvisible()
    cal s:DbgMsg("## s:cb_get_completion::pumvisible")
    let s:ctx.do_feedkeys = {}
    retu
  el
    " ic / Rc
    if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'c'
      let s:ctx.has_item = -1
      cal feedkeys("\<C-e>", "n")
      cal s:DbgMsg("# s:cb_get_completion::pum cancel (ctrlx ic/Rc mode)", s:ctx.mode)
      retu
    en
  en

  cal s:DbgMsg("# s:cb_get_completion::cursor hold i")
  try
    let result = s:get_completion(&ft)
    if (l:result == 0) && (&ft != '')
      cal s:DbgMsg("# s:cb_get_completion::fallback any filetype")
      let result = s:get_completion('')
    en
    if l:result == 0
      cal s:DbgMsg("# s:cb_get_completion::empty result")
      retu
    en
  fina
    let s:ctx.has_item = !empty(s:ctx.do_feedkeys) ? -1 : l:result
    cal s:DbgMsg("# s:cb_get_completion::has_item", s:ctx.has_item)
  endt
endf

fu! acf#set_timer() abort
  cal s:DbgMsg("acf#set_timer")
  if g:acf_disable_auto_complete
    retu
  en
  if !exists("b:save_shm") || b:save_shm !=# ''
    let b:save_shm = &shm
  en
  setl shm+=c
  cal acf#stop_timer()
  cal acf#get_completion(0)
  let s:ctx.timer_id =
        \ timer_start(g:acf_update_time,
        \             function('s:cb_get_completion'),
        \             {'repeat':-1}
        \ )
endf

fu! acf#enable_timer() abort
  let g:acf_disable_auto_complete = 0
endf

fu! acf#disable_timer() abort
  cal acf#stop_timer()
  let g:acf_disable_auto_complete = 1
endf

fu! acf#complete_done() abort
  cal acf#save_cursor_pos()
  if has_key(v:completed_item, 'word')
    let s:ctx.ciword = v:completed_item['word']
  el
    let s:ctx.ciword = ""
  en
  cal s:DbgMsg("## acf#complete_done", v:completed_item)
endf

fu! acf#get_completion(manual) abort
  cal s:DbgMsg("acf#get_completion")
  if a:manual
    cal s:DbgMsg("acf#get_completion::manual")
    cal acf#save_cursor_pos()
    let s:ctx.has_item = -1
    let s:ctx.do_feedkeys = {}
    let s:ctx.ciword = ""
  en
  cal s:cb_get_completion(-1)
  retu ""
endf

fu! acf#get_context() abort
  retu s:ctx
endf

" ==============================================================================
" Restore cpo
let &cpo = s:save_cpo

