
func! s:ApplyPendingSyntax(bufnr)
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
    call setbufvar(a:bufnr, 'clojure_syntax_keywords', pendingSyntax)
    call setbufvar(a:bufnr, 'clojure_syntax_without_core_keywords', hasCoreKeywords)
    call setbufvar(a:bufnr, '&syntax',
        \ getbufvar(a:bufnr, '&syntax', 'clojure'))
endfunc


" ======= Public interface ================================

func! mantel#async#AdjustPendingRequests(bufnr, delta)
    let oldCount = getbufvar(a:bufnr, 'mantel_pendingRequests', -1)
    if oldCount < 0
        throw 'Illegal state: ' . oldCount . ' pending requests'
    endif

    let newCount = oldCount + a:delta
    call setbufvar(a:bufnr, 'mantel_pendingRequests', newCount)

    if a:delta < 0 && newCount == 0
        " apply all changes at once to avoid flicker
        call s:ApplyPendingSyntax(a:bufnr)
    endif

    return newCount
endfunc

func! mantel#async#ConcatSyntaxKeys(bufnr, kind, keys)
    let pendingSyntax = getbufvar(a:bufnr, 'mantel_pendingSyntax', {})
    if has_key(pendingSyntax, a:kind)
        let pendingSyntax[a:kind] = pendingSyntax[a:kind] + a:keys
    else
        let pendingSyntax[a:kind] = a:keys
    endif
endfunc
