
" ======= utils ===========================================

func! s:hasNsRefers(bufnr)
    " currently, this only works in clj files; I'm not sure, but
    " I don't *think* it works in cljc files....
    return expand('#' . a:bufnr . ':e') ==# 'clj'
endfunc


" ======= Public interface ================================

func! mantel#Highlight()
    " reset pending state for new request
    " TODO cancel pending requests (?)
    let b:mantel_pendingRequests = 0

    let b:mantel_pendingSyntax = {
        \ 'clojureFunc': [],
        \ 'clojureMacro': [],
        \ 'clojureVariable': [],
        \ } " TODO other core types?

    let bufnr = bufnr('%')

    " fetch public vars exported by *this* ns
    let ns = fireplace#ns()
    call mantel#publics#FetchVarsForPairs(bufnr, [['', ns]])

    " fetch public vars in aliased ns (eg: s/def from spec)
    call mantel#aliases#Fetch(bufnr)

    if s:hasNsRefers(bufnr)
        " use ns-refers to fetch referred vars
        call mantel#refers#Fetch(bufnr, ns)
    endif
endfunc
