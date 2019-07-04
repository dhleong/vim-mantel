
" ======= constants =======================================

" including these words in any syntax list causes errors when vim tries
" to apply syntax to them
let s:reservedSyntaxWords =
    \ '#{"contains" "oneline" "fold" "display" "extend" "concealends" "conceal"'
    \.'"cchar" "contained" "containedin" "nextgroup" "transparent" "skipwhite"'
    \.'"skipnl" "skipempty"}'

" special case symbol-type mappings; these might read as macros, but actually
" we want them to be clojureSpecial, for example
let s:specials =
    \ '(->> {"clojureSpecial" '
    \."       '[def if do let quote var fn loop recur throw try catch finally "
    \.'         monitor-enter monitor-exit . new set!]}'
    \.'     (reduce-kv (fn [m kind entries]'
    \.'                   (merge m'
    \.'                          (zipmap (map str entries) '
    \.'                                  (repeat kind))))'
    \.'                {}))'

" ======= utils ===========================================

func! s:wrapCljWithMapToType(clj)
    " from clojure we have to use the fully qualified class name,
    " but from clojurescript we need to use *just* `MultiFn`
    let multiFn = '#?('
        \. ':cljs MultiFn '
        \. ':default clojure.lang.MultiFn '
        \. ')'

    return '(letfn [(fn-ref? [v]'
        \. '          (or (seq (:arglists (meta v)))'
        \. '              (when-let [derefd (when (var? v) @v)]'
        \. '                (or (fn? derefd)'
        \. '                    (instance? ' . multiFn . ' derefd)))))]'
        \. '  (->> ' . a:clj
        \. '       (filter (fn [{:keys [alias]}]'
        \. '                 (not (contains? '
        \.                     s:reservedSyntaxWords . ' alias))))'
        \. '       (map (fn [{:keys [var-ref alias ?macro]}]'
        \. '              (let [m (meta var-ref)'
        \. '                    n (str (or alias (:name m) ?macro))]'
        \. '                [n'
        \. '                 (or (get ' . s:specials . ' n)'
        \. '                     (cond'
        \. '                       ?macro "mantelMaybeMacro"'
        \. '                       (:macro m) "clojureMacro"'
        \. '                       (fn-ref? var-ref) "clojureFunc"'
        \. '                       :else "clojureVariable"))])))'
        \. '       (group-by second)'
        \. '       (reduce-kv'
        \. '          (fn [m kind entries]'
        \. '             (assoc m kind (map first entries)))'
        \. '          {})))'
endfunc

func! s:wrapDictWithEvalable(clj)
    return printf(g:fireplace#reader, a:clj)
endfunc

func! s:resolveNonCljsVars(bufnr, symbols) abort
    " Given a collection of namespaced symbols that couldn't be resolved in
    " the cljs context, attempt to resolve them in the clj context
    let items = map(copy(a:symbols),
        \ '"(if (clojure.core/resolve ' . "'" . '" . v:val . ")'
        \."   (clojure.core/name (clojure.core/keyword '"
        \.'" . v:val . ")))"'
        \ )
    let request = '(clojure.core/->> [' .   join(items, ' ') . ' ]'
                \.'     (clojure.core/keep clojure.core/identity)'
                \.'     (clojure.string/join "\", \"")'
                \.'     (#(clojure.core/str "[\"" % "\"]"))'
                \.'     (clojure.core/symbol))'

    " NOTE: it'd be nice to just use FetchVarsViaEval here, but this session
    " doesn't seem to be able to see the clojure.core vars for some reason,
    " which breaks all the reader stuff and generally makes things hard to
    " maintain. It should be a fairly safe bet, however, that, if they are
    " successfully resolved, they're macros
    call mantel#async#AdjustPendingRequests(a:bufnr, 1)
    call fireplace#message({
        \ 'op': 'eval',
        \ 'session': 0,
        \ 'code': request,
        \ }, function('s:onResolvedNonCljsVars', [a:bufnr]))
endfunc


" ======= callbacks =======================================

func! s:onResolvedNonCljsVars(bufnr, resp) abort
    if has_key(a:resp, 'ex') || has_key(a:resp, 'err')
        if has_key(a:resp, 'ex')
            call mantel#async#AdjustPendingRequests(a:bufnr, -1)
        endif
        echom a:resp
    elseif !has_key(a:resp, 'value')
        return
    endif

    " TODO it'd be nice if we could properly evaluate the type of
    " the var, instead of assuming their macros
    let resolved = eval(a:resp.value)
    call mantel#async#ConcatSyntaxKeys(a:bufnr, 'clojureMacro', resolved)
    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc

func! s:onFetchVarsResponse(bufnr, publics) abort
    for key in keys(a:publics)
        if key ==# 'mantelMaybeMacro'
            " special case; these symbols might point to macros
            " that the cljs env doesn't see
            call s:resolveNonCljsVars(a:bufnr, a:publics[key])
        else
            call mantel#async#ConcatSyntaxKeys(a:bufnr, key, a:publics[key])
        endif
    endfor

    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc

func! s:onFetchTypedVarsResponse(bufnr, type, vars) abort
    call mantel#async#ConcatSyntaxKeys(a:bufnr, a:type, a:vars)
    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc

func! s:onEvalResponse(bufnr, callback, resp) abort
    if !has_key(a:resp, 'value')
        if has_key(a:resp, 'ex')
            " we can get multiple 'err' responses, but should only
            " get one ex
            call mantel#async#AdjustPendingRequests(a:bufnr, -1)
            echom 'mantel error:' . a:resp.ex
        endif

        if has_key(a:resp, 'err') && a:resp.err !~# '^WARNING'
            " log the error
            echom 'mantel error:' . a:resp.err
        endif

        " whatever the case, don't try to eval
        return
    endif

    let evaluated = eval(a:resp.value)
    call a:callback(evaluated)
    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc


" ======= Public interface ================================

func! mantel#nrepl#FetchVarsViaEval(bufnr, code)
    " Asynchronously fetch vars by eval'ing clj code
    " The code should produce a sequence of maps with at least one of
    " the following keys:
    "  - `:var-ref` A Var instance
    "  - `:alias`   String; how the var is refer'd in the calling ns
    "  - `:?macro`  A symbol that *might* be the fqn of a macro

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)

    call mantel#nrepl#EvalAsVim(
        \ a:bufnr,
        \ s:wrapCljWithMapToType(a:code),
        \ function('s:onFetchVarsResponse', [a:bufnr]),
        \ )
endfunc

func! mantel#nrepl#FetchTypedVarsViaEval(bufnr, type, code)
    " Asynchronously fetch vars by eval'ing clj code
    " The code should produce a sequence of symbols or strings that are
    " aliases to vars of the given `type`, where `type` is one of the
    " syntax types, eg: clojureFunc, clojureVariable, etc.

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)

    call mantel#nrepl#EvalAsVim(
        \ a:bufnr,
        \ a:code,
        \ function('s:onFetchTypedVarsResponse', [a:bufnr, a:type]),
        \ )
endfunc

func! mantel#nrepl#EvalAsVim(bufnr, code, callback)
    let request = {
        \ 'op': 'eval',
        \ 'code': s:wrapDictWithEvalable(a:code),
        \ }

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)
    call fireplace#message(
        \ request,
        \ function('s:onEvalResponse', [a:bufnr, a:callback]),
        \ )
endfunc
