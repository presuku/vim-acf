# vim-acf
Timer(`+timers`) based auto completion framework for vim8.

## Requirements
* Vim8 (patch-8.0.0283 or later) for `mode(1)`

## Install
* vim-plug
```
Plug 'presuku/vim-acf.vim'
```

## Feature

* Timer(`+timers`)-based callback.
  * vim-acf callback a function every `g:acf_update_time`.

* Rule-based fallback search.
  * Searching matched rule by `at` in order of `priority` in same `filetype`.

* Filetype-based fallback search.
  * No found matched rule in current filetype, to next search in "" (blank) filetype.

## Usage

### Options

```vim script
let g:acf_update_time = 250 " default 250ms
```

### Recommend setting

```vim script
set completeopt=menuone,noselect,noinsert
```

### Add rules to trigger `func`.

* C or other
  * First, you need to install the omnifunc plugin for each language (ex. vim-clag for C).
```vim script
call acf#add_rule({
      \ 'filetype' : ['c'],
      \ 'priority' : 8,
      \ 'at'       : '/\%#',
      \ 'func'     : function("feedkeys", ["\<C-x>\<C-f>", "n"]),
      \ 'syntax'   : ['Comment', 'String']
      \})

call acf#add_rule({
      \ 'filetype' : ['c', 'cpp', 'java'],
      \ 'priority' : 9,
      \ 'at'       : '\k\{1,}\%(\.\|->\|::\)\%#',
      \ 'func'     : function("feedkeys", ["\<C-x>\<C-o>", "n"]),
      \})
```

* Vim script
```vim script
call acf#add_rule({
      \ 'filetype' : ['vim'],
      \ 'priority' : 9,
      \ 'at'       : '\%(\k\|:\)\{1,}\%#',
      \ 'func'     : function("feedkeys", ["\<C-x>\<C-v>", "n"]),
      \})
```

* For any filetype.
```vim script
call acf#add_rule({
      \ 'filetype' : [''],
      \ 'priority' : 7,
      \ 'at'       : '\k\{3,}\%#',
      \ 'func'     : function("feedkeys", ["\<C-n>", "n"]),
      \})

call acf#add_rule({
      \ 'filetype' : [''],
      \ 'priority' : 8,
      \ 'at'       : '/\%#',
      \ 'func'     : function("feedkeys", ["\<C-x>\<C-f>", "n"]),
      \})

let g:nsnip_prefix="snip"
function! s:acf_neosnippet_complete()
  let ctx = acf#get_context()
  let n_prefix = len(g:nsnip_prefix)
  let base = l:ctx.base[n_prefix:]
  let list = []
  let val = values(neosnippet#helpers#get_completion_snippets())
  for v in val
    if v.word =~ '^'. l:base
      let v.menu = '[nsnip]'
      call add(list, v)
    endif
  endfor
  call sort(list)
  call complete(l:ctx.startcol, list)
  return ''
endfunction

call acf#add_rule({
      \ 'filetype' : [''],
      \ 'priority' : 9,
      \ 'at'       : '\%(^\|\s\)\zs'.g:nsnip_prefix.'\%#',
      \ 'func'     : {-> s:acf_neosnippet_complete() },
      \})
```

## Thanks

* [lexima.vim](https://github.com/cohama/lexima.vim) by @cohama
  * Base plugin system from this plugin, 
    and a lot of vim script to be used for reference or study.

* [SimpleAutoComplPop](https://github.com/roxma/SimpleAutoComplPop) by @roxma, ns9tks
  * Just idea from this plugin.

* [quickrun](http://github.com/thinca/vim-quickrun) by @thinca
  * Easy and quickly debugging (learning) for vim script.

## License

MIT (c) @presuku

