
" ======= constants =======================================

" including these words in any syntax list causes errors when vim tries
" to apply syntax to them
let s:reservedSyntaxWords =
    \ '#{"contains" "oneline" "fold" "display" "extend" "concealends" "conceal"'
    \.'"cchar" "contained" "containedin" "nextgroup" "transparent" "skipwhite"'
    \.'"skipnl" "skipempty"}'


" ======= utils ===========================================

func! s:wrapCljWithMapToType(clj)
    return '(letfn [(fn-ref? [v]'
        \. '          (or (seq (:arglists (meta v)))'
        \. '              (when-let [derefd (when (var? v) @v)]'
        \. '                (or (fn? derefd)'
        \. '                    (instance? MultiFn derefd)))))]'
        \. '  (->> ' . a:clj
        \. '       (filter (fn [{:keys [alias]}]'
        \. '                 (not (contains? '
        \.                     s:reservedSyntaxWords . ' alias))))'
        \. '       (map (fn [{:keys [var-ref alias]}]'
        \. '              (let [m (meta var-ref)]'
        \. '                [(or alias (:name m))'
        \. '                 (cond'
        \. '                   (:macro m) "clojureMacro"'
        \. '                   (fn-ref? var-ref) "clojureFunc"'
        \. '                   :else "clojureVariable")])))'
        \. '       (group-by second)'
        \. '       (reduce-kv'
        \. '          (fn [m kind entries]'
        \. '             (assoc m kind (map first entries)))'
        \. '          {})))'
endfunc

func! s:wrapDictWithEvalable(clj)
    return printf(g:fireplace#reader, a:clj)
endfunc


" ======= callbacks =======================================

func! s:onFetchVarsResponse(bufnr, publics) abort
    for key in keys(a:publics)
        call mantel#async#ConcatSyntaxKeys(a:bufnr, key, a:publics[key])
    endfor

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
    " The code should produce a sequence of maps with the keys:
    "  - `:var-ref` (Optional, if :alias is provided)
    "  - `:alias`   (Optional, if :var-ref is provided)

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)

    call mantel#nrepl#EvalAsVim(
        \ a:bufnr,
        \ s:wrapCljWithMapToType(a:code),
        \ function('s:onFetchVarsResponse', [a:bufnr]),
        \ )
endfunc

func! mantel#nrepl#EvalAsVim(bufnr, code, callback)
    call mantel#async#AdjustPendingRequests(a:bufnr, 1)
    call fireplace#message({
        \ 'op': 'eval',
        \ 'code': s:wrapDictWithEvalable(a:code),
        \ }, function('s:onEvalResponse', [a:bufnr, a:callback]))
endfunc
