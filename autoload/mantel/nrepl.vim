
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
        \. '              [alias, (cond'
        \. '                        (:macro m) "clojureMacro"'
        \. '                        (seq (-> m :arglists)) "clojureFunc"'
        \. '                        :else "clojureVariable")])))'
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

func! s:onPendingRequestFinished(bufnr)
    let newCount = mantel#async#AdjustPendingRequests(a:bufnr, -1)

    if newCount > 0
        " still pending requests; we want to apply all changes at once
        " to avoid flicker
        return
    endif

    " due to the way the syntax_keywords map is applied, we cannot allow
    " empty lists
    let pendingSyntax = getbufvar(a:bufnr, 'mantel_pendingSyntax', {})
    for key in keys(pendingSyntax)
        if empty(pendingSyntax[key])
            unlet pendingSyntax[key]
        endif
    endfor

    " we can only get the core keywords (eg: macros like `and`) via ns-refers
    " TODO setting this to 1 also disables default highlighting for things
    " like `throw`, `new`, `case`, etc.
    let hasCoreKeywords = 0 " TODO s:hasNsRefers(a:bufnr)

    " apply results
    let b:clojure_syntax_keywords = pendingSyntax
    let b:clojure_syntax_without_core_keywords = hasCoreKeywords
    let &syntax = &syntax
endfunc

func! s:onEvalResponse(bufnr, resp)
    if has_key(a:resp, 'err')
        echom 'ERROR' . string(a:resp)
        return
    elseif !has_key(a:resp, 'value')
        return
    endif

    let pendingSyntax = getbufvar(a:bufnr, 'mantel_pendingSyntax', {})
    let publics = eval(a:resp.value)
    for key in keys(publics)
        let pendingSyntax[key] = pendingSyntax[key] + publics[key]
    endfor

    call s:onPendingRequestFinished(a:bufnr)
endfunc


" ======= Public interface ================================

func! mantel#nrepl#FetchVarsViaEval(bufnr, code)
    " Asynchronously fetch vars by eval'ing clj code

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)

    let request = s:wrapDictWithEvalable(s:wrapCljWithMapToType(a:code))
    call fireplace#message({
        \ 'op': 'eval',
        \ 'code': request,
        \ }, function('s:onEvalResponse', [a:bufnr]))
endfunc
