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
elsei g:acf_update_time < 30
  let g:acf_update_time = 30
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
        \ 'startline'  : 0,
        \ 'startcol'   : 0,
        \ 'base'       : "",
        \ 'do_feedkeys': {},
        \ 'ciword'     : "",
        \ 'busy'       : 0,
        \}
endf

let s:ctx = s:init_ctx()

let s:rule_list = {}

fu! s:hashlen(msg) abort
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
  if dbg_lv < g:acf_debug
    if a:0 == 0
      let msg = a:msg
    el
      let msg = a:msg . ":" . string(a:000[0])
      for i in a:000[1:]
        let msg = msg . ', ' . string(i)
      endfo
    en
    echom "Dbg" . ":" . msg
  en
endf

fu! s:compare(a, b) abort
  let s:sub_cmp = {a, b->(a > b) ? 1 : ((a < b) ? -1 : 0)}
  let r = s:sub_cmp(a:a.priority, a:b.priority)
  if r != 0 | retu r | en
  let r = s:sub_cmp(len(a:a.at), len(a:b.at))
  if r != 0 | retu r | en
  let r = s:sub_cmp(len(a:a.except), len(a:b.except))
  if r != 0 | retu r | en
  let r = s:sub_cmp(len(a:a.syntax), len(a:b.syntax))
  if r != 0 | retu r | en
  retu 0
endf

let s:default_rule = {
      \ 'filetype': [],
      \ 'syntax': [],
      \ 'except': '',
      \ 'priority': 0,
      \ 'not_found': 0,
      \ }

fu! s:normalize_rule(rule) abort
  if !has_key(a:rule, 'at') || !has_key(a:rule, 'func')
    retu {}
  en

  " default rule copy to a:rule, and keep exist keys.
  let nrule = extend(deepcopy(a:rule), s:default_rule, 'keep')

  " filetype
  if type(nrule.filetype) !=# v:t_list
    let nrule.filetype = [nrule.filetype]
  en
  if empty(nrule.filetype)
    " [] => ['_']
    let nrule.filetype = ['_']
  el
    " ['' , 'vim'] => ['_', 'vim']
    let i = index(nrule.filetype, '')
    if i > -1
      let nrule.filetype[i] = '_'
    en
  en

  " syntax
  if type(nrule.syntax) !=# v:t_list
    let nrule.syntax = [nrule.syntax]
  en

  retu nrule
endf


fu! acf#add_rule(rule) abort
  " normalize user input.
  let nrule = s:normalize_rule(a:rule)
  if empty(nrule)
    echom 'ERROR: In acf#add_rule(), input rule is invalid:' . string(a:rule)
    retu
  en
  for ft in nrule.filetype
    if !has_key(s:rule_list, ft)
      let s:rule_list[ft] = [nrule]
    el
      if index(s:rule_list[ft], nrule) < 0
        cal add(s:rule_list[ft], nrule)
      el
        cal s:DbgMsg('### already exists a rule', a:rule)
        retu
      en
      cal sort(s:rule_list[ft], {a, b -> s:compare(a, b)})
    en
  endfo
endf

fu! s:get_syntax_link_chain() abort
  let [l, c] = s:get_saved_cursor_pos()
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

fu! s:execute_func(rule, sl, sc, base) abort
  cal s:DbgMsg('### s:execute_func::a:rule', a:rule)
  cal s:DbgMsg('### s:execute_func::a:sl', a:sl, ', sc', a:sc)
  cal s:DbgMsg('### s:execute_func::a:base', a:base)

  let s:ctx.startline = a:sl
  let s:ctx.startcol = a:sc
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
      let a:rule.not_found = 1
      retu 1
    el
      if !empty(s:ctx.do_feedkeys)
        cal s:DbgMsg('### s:execute_func::no item, but do_feedkeys')
        retu 2
      el
        cal s:DbgMsg("### s:execute_func::no item")
        retu 0
      en
    en
  endt
endf

fu! s:get_completion(ft) abort
  let syntax_chain = s:get_syntax_link_chain()
  let [cl, cc] = s:get_saved_cursor_pos()
  let searchlimit = cl
  let ft = (a:ft ==# '') ? '_' : a:ft
  let result = 0

  cal s:DbgMsg('## s:get_completion::ft', a:ft)
  let rules = has_key(s:rule_list, ft) ? s:rule_list[ft] : []
  cal s:DbgMsg("#### s:get_completion::rules", rules)

  for rule in rules
    cal s:DbgMsg("### s:get_completion::rule", rule)
    cal s:DbgMsg("### s:get_completion::do_feedkeys", s:ctx.do_feedkeys)
    if !empty(s:ctx.do_feedkeys)
      if rule != s:ctx.do_feedkeys
        con
      el
        let s:ctx.do_feedkeys = {}
        con
      en
    en
    let [sl, sc] = searchpos(rule.at, 'bcWn', searchlimit)
    let search_reduce = ((s:ctx.startline ==# sl && s:ctx.startcol <= sc) ?
          \ rule.not_found : 0)
    cal s:DbgMsg("### s:get_completion::search_reduce", search_reduce)
    let rule.not_found = search_reduce
    let excepted = has_key(rule, 'except') && !empty(rule.except) ?
          \ searchpos(rule.except, 'bcWn', searchlimit) !=# [0, 0] : 0
    if [sl, sc] ==# [0, 0] || excepted || search_reduce
      con
    en

    cal s:DbgMsg("#### s:get_completion::sc", sc, "cc", cc)
    let base = getline('.')[sc-1:cc-2]
    cal s:DbgMsg("### s:get_completion::base", base, ", s:ctx.ciword", s:ctx.ciword)
    if base ==# s:ctx.ciword
          \ || base[-strlen(s:ctx.ciword):] ==# s:ctx.ciword
      retu 0
    en
    if !has_key(rule, 'syntax') || empty(rule.syntax)
      let result = s:execute_func(rule, sl, sc, base)
      if result | retu result | en
    el
      for syn in syntax_chain
        if index(rule.syntax, syn) < 0 | con | en
        cal s:DbgMsg("### s:get_completion::syn", syn)
        let result = s:execute_func(rule, sl, sc, base)
        if result
          retu result
        el
          brea
        en
      endfo
    en
  endfo

  retu result
endf

fu! s:save_cursor_pos() abort
  let s:ctx.pos = getpos('.')
  cal s:DbgMsg("## save pos", s:ctx.pos)
  retu s:ctx.pos[1:2]
endf

fu! s:get_saved_cursor_pos() abort
  cal s:DbgMsg("## get saved pos", s:ctx.pos)
  retu s:ctx.pos[1:2]
endf

fu! acf#stop_timer() abort
  cal s:DbgMsg("acf#stop_timer")
  let info = timer_info(s:ctx.timer_id)
  if !empty(info)
    cal s:DbgMsg("acf#stop_timer::stop timer!!")
    cal timer_stop(s:ctx.timer_id)
  en
  let s:ctx = s:init_ctx()
  if exists("b:save_shm")
    let &shm = b:save_shm
  en
  let b:save_shm = ''
endf

fu! s:cb_get_completion(timer_id) abort
  let ok_mode = ['i', 'R']
  let s:ctx.mode = mode(1)
  let saved_pos = s:get_saved_cursor_pos()
  let current_pos = s:save_cursor_pos()

  " mode check
  if index(ok_mode, s:ctx.mode[0]) < 0
    cal s:DbgMsg(
          \ "s:cb_get_completion::callbacked in normal/virtual/other mode",
          \ s:ctx.mode)

    cal acf#stop_timer()
    let s:ctx.busy = 0
    retu
  en

  " busy check
  if s:ctx.busy == 1
    cal s:DbgMsg("s:cb_get_completion::busy")
    retu
  el
    let s:ctx.busy = 1
  en

  " ix / Rx mode check
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'x'
    cal s:DbgMsg("s:cb_get_completion::ctrlx ix/Rx mode", s:ctx.mode)
    let s:ctx.has_item = -1
    let s:ctx.busy = 0
    retu
  en

  " iV / RV
  " Add iV / RV / cV mode patch:
  " https://gist.github.com/presuku/fa7f351e792a9e74bfbd61684f0139ab
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'V'
    cal s:DbgMsg("# s:cb_get_completion::ctrlx iV/RV/cV mode", s:ctx.mode)
    let s:ctx.has_item = -1
    let s:ctx.busy = 0
    retu
  en

  " ir / Rr
  " Add ir / Rr / cr mode patch:
  " https://gist.github.com/presuku/dc6bb11dfdb83535d82b1b6d7310e5bf
  if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'r'
    cal s:DbgMsg("# s:cb_get_completion::ctrlx ir/Rr/cr mode", s:ctx.mode)
    let s:ctx.has_item = -1
    let s:ctx.busy = 0
    retu
  en

  if saved_pos != current_pos
    cal s:DbgMsg("# s:cb_get_completion::cursor moved i")
    let s:ctx.has_item = -1
    let s:ctx.do_feedkeys = {}
    let s:ctx.ciword = ""
    let s:ctx.busy = 0
    retu
  en

  if s:ctx.has_item == 0
    cal s:DbgMsg("s:cb_get_completion::no item")
    let s:ctx.busy = 0
    retu
  en

  if pumvisible()
    cal s:DbgMsg("## s:cb_get_completion::pumvisible")
    let s:ctx.do_feedkeys = {}
    let s:ctx.busy = 0
    retu
  el
    " ic / Rc
    if len(s:ctx.mode) > 1 && s:ctx.mode[1] ==# 'c'
      cal feedkeys("\<C-e>", "n")
      cal s:DbgMsg("# s:cb_get_completion::pum cancel (ctrlx ic/Rc mode)", s:ctx.mode)
      if !empty(s:ctx.do_feedkeys)
        let s:ctx.do_feedkeys.not_found = 1
      endif
      let s:ctx.has_item = -1
      let s:ctx.busy = 0
      retu
    en
  en

  let result = -1
  cal s:DbgMsg("# s:cb_get_completion::cursor hold i")
  try
    let result = s:get_completion(&ft)
    if (result == 0) && (&ft != '')
      cal s:DbgMsg("# s:cb_get_completion::fallback any filetype")
      let result = s:get_completion('')
    en
    if result == 0
      cal s:DbgMsg("# s:cb_get_completion::empty result")
      retu
    els
      cal s:DbgMsg("# s:cb_get_completion::something wrong")
      retu
    en
  fina
    let s:ctx.has_item = !empty(s:ctx.do_feedkeys) ? -1 : result
    if result == 2
      cal s:DbgMsg("s:cb_get_completion::cal 2nd timer_start()")
      cal timer_start(g:acf_update_time/3, function('s:cb_get_completion'))
    endif
    cal s:DbgMsg("# s:cb_get_completion::has_item", s:ctx.has_item)
    let s:ctx.busy = 0
  endt
endf

fu! acf#set_timer() abort
  cal s:DbgMsg("acf#set_timer")
  if v:insertmode ==# 'n'
    retu
  en
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
  cal s:save_cursor_pos()
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
    cal s:save_cursor_pos()
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

