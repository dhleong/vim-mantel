func! mantel#async#AdjustPendingRequests(bufnr, delta)
    let oldCount = getbufvar(a:bufnr, 'mantel_pendingRequests', -1)
    if oldCount < 0
        throw 'Illegal state: ' . oldCount . ' pending requests'
    endif

    let newCount = oldCount + a:delta
    call setbufvar(a:bufnr, 'mantel_pendingRequests', newCount)
endfunc

func! mantel#async#ConcatSyntaxKeys(bufnr, kind, keys)
    let pendingSyntax = getbufvar(a:bufnr, 'mantel_pendingSyntax', {})
    if has_key(pendingSyntax, a:kind)
        let pendingSyntax[a:kind] = pendingSyntax[a:kind] + a:keys
    else
        let pendingSyntax[a:kind] = a:keys
    endif
endfunc
