# vim-acf (Vim Auto Completion Framework)

- Timer (`+timers`) based auto completion framework for vim8.
- Written by pure vim script.
- Simple and thin framework because it uses built-in completion with a feedkeys().

## Requirements

* Vim8 with +timers and +lambda
  * patch-8.0.0283 or later is recommended for `mode(1)`.

## Install

* vim-plug

  ```vim
  Plug 'presuku/vim-acf.vim'
  ```

## Feature

* Timer(`+timers`)-based callback.
  * vim-acf callback a function every `g:acf_update_time`.

* Rule-based fallback searching.
  * Searching matched rule by `at` in order of `priority` in same `filetype`.

* Filetype-based fallback searching.
  * No found matched rule in current filetype, to next search in "" (blank) filetype.

## Usage

### Options

```vim
let g:acf_update_time = 250 " default 250ms
```

### Recommend setting

```vim
set completeopt=menuone,noselect,noinsert
```

### Add rules to trigger `func`.

First, you need to install the omnifunc plugin for each language (ex. vim-clag for C).

#### C or other

* Completing file (and directory) names by `i_CTRL-X_CTRL-F` on Comment and String syntax
  when the cursor after `/`.

  ```vim
  call acf#add_rule({
        \ 'filetype' : ['c'],
        \ 'priority' : 8,
        \ 'at'       : '/\%#',
        \ 'func'     : function("feedkeys", ["\<C-x>\<C-f>", "n"]),
        \ 'syntax'   : ['Comment', 'String']
        \})
  ```
* Call omnifunc by `i_CTRL-X_CTRL-O` when the cursor after a `\k.` or `\k->` or `\k::`. (`\k` is keyword characters. see `:help \k`)

  ```vim
  call acf#add_rule({
        \ 'filetype' : ['c', 'cpp', 'java'],
        \ 'priority' : 9,
        \ 'at'       : '\k\{1,}\%(\.\|->\|::\)\%#',
        \ 'func'     : function("feedkeys", ["\<C-x>\<C-o>", "n"]),
        \})
  ```

#### Vim script

* Completing file (and directory) names by `i_CTRL-X_CTRL-F` on Comment and String syntax
  when the cursor after `/`. vim commands by `i_CTRL-X_CTRL-V` when the cursor after a `\k` or `:`. (`\k` is keyword characters. see `:help \k`)

  ```vim
  call acf#add_rule({
        \ 'filetype' : ['vim'],
        \ 'priority' : 9,
        \ 'at'       : '\%(\k\|:\)\{1,}\%#',
        \ 'func'     : function("feedkeys", ["\<C-x>\<C-v>", "n"]),
        \})
  ```

#### For any filetype.

* Completing keywords by `i_CTRL-N` when the cursor after a `\k\k\k` (three keyword characters).

  ```vim
  call acf#add_rule({
        \ 'filetype' : [''],
        \ 'priority' : 7,
        \ 'at'       : '\k\{3,}\%#',
        \ 'func'     : function("feedkeys", ["\<C-n>", "n"]),
        \})
  ```

* Fallback-ed completing file names by `i_CTRL-X_CTRL-F` when the cursor after a `/`.

  ```vim
  call acf#add_rule({
        \ 'filetype' : [''],
        \ 'priority' : 8,
        \ 'at'       : '/\%#',
        \ 'func'     : function("feedkeys", ["\<C-x>\<C-f>", "n"]),
        \})
  ```

* Completing [neosnippet](https://github.com/Shougo/neosnippet)'s list when the cursor after `snip`.

  * you can also use `complete()` function.

  ```vim
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

