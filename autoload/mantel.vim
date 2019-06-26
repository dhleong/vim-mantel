
" ======= utils ===========================================

func! s:hasNsRefers(bufnr)
    " currently, this only works in clj files; I'm not sure, but
    " I don't *think* it works in cljc files....
    return expand('#' . a:bufnr . ':e') ==# 'clj'
endfunc


" ======= Public interface ================================

func! mantel#Highlight()
    " reset; 1 for the the ns-aliases call below
    let b:mantel_pendingRequests = 0

    " TODO other core types?
    let b:mantel_pendingSyntax = {
        \ 'clojureFunc': [],
        \ 'clojureMacro': [],
        \ 'clojureVariable': [],
        \ }

    let bufnr = bufnr('%')

    " fetch public vars exported by *this* ns
    let ns = fireplace#ns()
    call mantel#ns#FetchVarsForPairs(bufnr, [['', ns]])

    " fetch public vars in aliased ns (eg: s/def from spec)
    call mantel#aliases#Fetch(bufnr)

    if s:hasNsRefers(bufnr)
        " use ns-refers to fetch referred vars
        call mantel#refers#Fetch(bufnr)
    endif
endfunc
