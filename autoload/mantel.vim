
" ======= constants =======================================

" including these words in any syntax list causes errors when vim tries
" to apply syntax to them
let s:reservedSyntaxWords =
    \ '#{"contains" "oneline" "fold" "display" "extend" "concealends" "conceal"'
    \.'"cchar" "contained" "containedin" "nextgroup" "transparent" "skipwhite"'
    \.'"skipnl" "skipempty"}'


" ======= utils ===========================================

func! s:hasNsRefers(bufnr)
    " currently, this only works in clj files; I'm not sure, but
    " I don't *think* it works in cljc files....
    return expand('#' . a:bufnr . ':e') ==# 'clj'
endfunc

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

func! s:fetchVarsForPrefixAndNsPairs(bufnr, prefixAndNsPairs) abort
    " convert input (list of tuples) to edn format
    let pairs = []
    for [prefix, ns] in a:prefixAndNsPairs
        " we call ns-publics directly to workaround the clojurescript
        " limitation of (ns-publics) being a macro
        call add(pairs, printf("[\"%s\", (ns-publics '%s)]", prefix, ns))
    endfor

    " we could also just use cider's `ns-vars-with-meta` op and parse the
    " results in vim... but we'd have to issue N requests and coordinate them
    " all. Plus, this lets us do the processing asynchronously
    let request = '(mapcat '
              \ . '  (fn [[prefix publics]]'
              \ . '    (->> publics'
              \ . '         (map (fn [[var-name var-ref]]'
              \ . '                 {:alias (str prefix var-name)'
              \ . '                  :var-ref var-ref}))))'
              \ . '  [' . join(pairs, ' ') . '])'
    " echom pairs
    let request = s:wrapDictWithEvalable(s:wrapCljWithMapToType(request))
    echom fireplace#message({
        \ 'op': 'eval',
        \ 'code': request,
        \ }, function('s:onAliasedPublics', [a:bufnr]))
endfunc

" ======= callbacks =======================================

func! s:onPendingRequestFinished(bufnr)
    let oldCount = getbufvar(a:bufnr, 'mantel_pendingRequests', -1)
    if oldCount <= 0
        throw 'Illegal state: ' . oldCount . ' pending requests'
    endif

    let newCount = oldCount - 1
    call setbufvar(a:bufnr, 'mantel_pendingRequests', newCount)

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
    let hasCoreKeywords = 0 " TODO s:hasNsRefers(a:bufnr)

    " apply results
    let b:clojure_syntax_keywords = pendingSyntax
    let b:clojure_syntax_without_core_keywords = hasCoreKeywords
    let &syntax = &syntax
endfunc

func! s:onAliasedPublics(bufnr, resp)
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

func! s:onNsAliases(bufnr, resp)
    if !has_key(a:resp, 'ns-aliases')
        return
    endif

    " aliases is a map of alias -> ns; we can uses ns-publics
    " to fetch a list of all the public vars in those ns to
    " build candidates for aliased var usage (eg: s/def from spec)
    let nsAliases = a:resp['ns-aliases']
    let pairs = []

    " build pairs
    for alias in keys(nsAliases)
        let ns = nsAliases[alias]
        call add(pairs, [ alias . '/', ns ])
    endfor

    call s:fetchVarsForPrefixAndNsPairs(a:bufnr, pairs)
endfunc

func! mantel#AliasedVars()
    " TODO other core types?
    let b:mantel_pendingRequests = 2
    let b:mantel_pendingSyntax = {
        \ 'clojureFunc': [],
        \ 'clojureMacro': [],
        \ 'clojureVariable': [],
        \ }

    let bufnr = bufnr('%')

    " fetch public vars exported by *this* ns
    let ns = fireplace#ns()
    call s:fetchVarsForPrefixAndNsPairs(bufnr, [['', ns]])

    " fetch aliased namespaces (eg: clojure.spec :as s) so we can fetch public
    " vars in each
    call fireplace#message({'op': 'ns-aliases'},
        \ function('s:onNsAliases', [bufnr]))

    if s:hasNsRefers(bufnr)
        " TODO use ns-refers
    endif
endfunc
