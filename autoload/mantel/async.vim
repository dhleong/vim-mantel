func! mantel#async#AdjustPendingRequests(bufnr, delta)
    let oldCount = getbufvar(a:bufnr, 'mantel_pendingRequests', -1)
    if oldCount < 0
        throw 'Illegal state: ' . oldCount . ' pending requests'
    endif

    let newCount = oldCount + a:delta
    call setbufvar(a:bufnr, 'mantel_pendingRequests', newCount)
endfunc
