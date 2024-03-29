
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
    \."       '(def if do let quote var fn loop recur "
    \.'         monitor-enter monitor-exit . new set!)'
    \.'      "clojureCond" '
    \."       '(case cond cond-> cond->> condp if-let if-not if-some when"
    \.'         when-first when-let when-not when-some)'
    \.'      "clojureException" '
    \."       '(throw try catch finally)"
    \.'      "clojureRepeat" '
    \."       '(doseq dotimes while)"
    \.'     }'
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
        \. '       (map (fn [{:keys [alias] :as item}]'
        \. '              (if (contains? ' . s:reservedSyntaxWords . ' alias)'
        \. '                (update item :alias (partial str "\\"))'
        \. '                item)))'
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
        \ '"(when (resolve ' . "'" . '" . v:val . ")'
        \."   (name (keyword '" . '" . v:val . ")))"'
        \ )
    let request = '(some->> [' .   join(items, ' ') . ' ]'
                \.'     (keep identity)'
                \.'     seq'
                \.'     (clojure.string/join "\", \"")'
                \.'     (#(str "[\"" % "\"]"))'
                \.'     (symbol))'

    " NOTE: it'd be nice to just use FetchVarsViaEval here, but this session
    " doesn't seem to be able to see the clojure.core vars for some reason,
    " which breaks all the reader stuff and generally makes things hard to
    " maintain. It should be a fairly safe bet, however, that, if they are
    " successfully resolved, they're macros
    call mantel#async#Message(a:bufnr, {
        \ 'mantel': {'platform': 'clj'},
        \ 'op': 'eval',
        \ 'code': request,
        \ }, function('s:onResolvedNonCljsVars', [a:bufnr]))
endfunc


" ======= callbacks =======================================

func! s:onResolvedNonCljsVars(bufnr, resp) abort
    if has_key(a:resp, 'ex') || has_key(a:resp, 'err')
        call mantel#async#NotifyError(get(a:resp, 'err', get(a:resp, 'ex', '')))
    elseif !has_key(a:resp, 'value')
        return
    endif

    " TODO it'd be nice if we could properly evaluate the type of
    " the var, instead of assuming they're macros
    if a:resp.value !=# 'nil'
        let resolved = eval(a:resp.value)
        call mantel#async#ConcatSyntaxKeys(a:bufnr, 'clojureMacro', resolved)
    endif
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
endfunc

func! s:onFetchTypedVarsResponse(bufnr, type, vars) abort
    call mantel#async#ConcatSyntaxKeys(a:bufnr, a:type, a:vars)
endfunc

func! s:onEvalResponse(bufnr, printErrors, callback, resp) abort
    if !has_key(a:resp, 'value')
        if a:printErrors && has_key(a:resp, 'ex')
            call mantel#async#NotifyError(a:resp.ex)
        elseif a:printErrors && has_key(a:resp, 'err') && a:resp.err !~# '^WARNING'
            " log the error
            call mantel#async#NotifyError(a:resp.err)
        endif

        " whatever the case, don't try to eval
        return
    endif

    try
        let evaluated = eval(a:resp.value)
        call a:callback(evaluated)
    catch /.*/
        echom 'ERR evaluating: ' . a:resp.value
        echom v:errmsg
    endtry
endfunc


" ======= Public interface ================================

func! mantel#nrepl#FetchVarsViaEval(bufnr, code)
    " Asynchronously fetch vars by eval'ing clj code
    " The code should produce a sequence of maps with at least one of
    " the following keys:
    "  - `:var-ref` A Var instance
    "  - `:alias`   String; how the var is refer'd in the calling ns
    "  - `:?macro`  A symbol that *might* be the fqn of a macro

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

    call mantel#nrepl#EvalAsVim(
        \ a:bufnr,
        \ a:code,
        \ function('s:onFetchTypedVarsResponse', [a:bufnr, a:type]),
        \ )
endfunc

func! mantel#nrepl#EvalAsVim(bufnr, code, callback)
    let printErrors = 1
    if type(a:code) == v:t_dict
        let code = a:code.code
        let printErrors = get(a:code, 'printErrors', printErrors)
    else
        let code = a:code
    endif

    let request = {
        \ 'op': 'eval',
        \ 'code': s:wrapDictWithEvalable(code),
        \ }

    if type(a:code) == v:t_dict && has_key(a:code, 'platform')
        let request.platform = a:code.platform
    endif

    call mantel#async#Message(a:bufnr,
        \ request,
        \ function('s:onEvalResponse', [a:bufnr, printErrors, a:callback]),
        \ )
endfunc
