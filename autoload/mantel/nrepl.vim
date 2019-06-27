
" ======= constants =======================================

" including these words in any syntax list causes errors when vim tries
" to apply syntax to them
let s:reservedSyntaxWords =
    \ '#{"contains" "oneline" "fold" "display" "extend" "concealends" "conceal"'
    \.'"cchar" "contained" "containedin" "nextgroup" "transparent" "skipwhite"'
    \.'"skipnl" "skipempty"}'


" ======= utils ===========================================

func! s:wrapCljWithMapToType(clj)
    return '(->> ' . a:clj
        \. '     (filter (fn [{:keys [alias]}]'
        \. '               (not (contains? '
        \.                   s:reservedSyntaxWords . ' alias))))'
        \. '     (map (fn [{:keys [var-ref alias]}]'
        \. '            (let [m (meta var-ref)]'
        \. '              [(or alias (:name m))'
        \. '               (cond'
        \. '                 (:macro m) "clojureMacro"'
        \. '                 (seq (-> m :arglists)) "clojureFunc"'
        \. '                 :else "clojureVariable")])))'
        \. '     (group-by second)'
        \. '     (reduce-kv'
        \. '        (fn [m kind entries]'
        \. '           (assoc m kind (map first entries)))'
        \. '        {}))'
endfunc

func! s:wrapDictWithEvalable(clj)
    return printf(g:fireplace#reader, a:clj)
endfunc


" ======= callbacks =======================================

func! s:onFetchVarsResponse(bufnr, publics)
    for key in keys(a:publics)
        call mantel#async#ConcatSyntaxKeys(a:bufnr, key, a:publics[key])
    endfor

    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc

func! s:onEvalResponse(callback, resp)
    if has_key(a:resp, 'err')
        echom 'ERROR' . string(a:resp)
        return
    elseif !has_key(a:resp, 'value')
        return
    endif

    let evaluated = eval(a:resp.value)
    call a:callback(evaluated)
endfunc


" ======= Public interface ================================

func! mantel#nrepl#FetchVarsViaEval(bufnr, code)
    " Asynchronously fetch vars by eval'ing clj code
    " The code should produce a sequence of maps with the
    " keys `:var-ref` and, optionally, `:alias`

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)

    call mantel#nrepl#EvalAsVim(
        \ s:wrapCljWithMapToType(a:code),
        \ function('s:onFetchVarsResponse', [a:bufnr]),
        \ )
endfunc

func! mantel#nrepl#EvalAsVim(code, callback)
    call fireplace#message({
        \ 'op': 'eval',
        \ 'code': s:wrapDictWithEvalable(a:code),
        \ }, function('s:onEvalResponse', [a:callback]))
endfunc
