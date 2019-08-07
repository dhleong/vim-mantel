
let s:pendingRequests = {}

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

func! s:onMessage(bufnr, callback, resp)
    if !has_key(s:pendingRequests, a:resp.id)
        " request canceled
        return
    endif

    unlet s:pendingRequests[a:resp.id]

    call a:callback(a:resp)

    if empty(s:pendingRequests)
        call s:ApplyPendingSyntax(a:bufnr)
    endif
endfunc


" ======= Public interface ================================

func! mantel#async#ConcatSyntaxKeys(bufnr, kind, keys)
    let pendingSyntax = getbufvar(a:bufnr, 'mantel_pendingSyntax', {})
    if has_key(pendingSyntax, a:kind)
        let pendingSyntax[a:kind] = pendingSyntax[a:kind] + a:keys
    else
        let pendingSyntax[a:kind] = a:keys
    endif
endfunc

func! mantel#async#Cancel()
    " Cancel all pending async#Message requests
    let s:pendingRequests = {}
endfunc

func! mantel#async#Message(bufnr, msg, callback)
    let opts = get(a:msg, 'mantel', {})

    " Forwards to fireplace#message in a way that can be canceled
    let Callback = function('s:onMessage', [a:bufnr, a:callback])

    let preferredPlatform = get(opts, 'platform', '')
    if preferredPlatform ==# 'clj'
        let platform = fireplace#clj()
    elseif preferredPlatform ==# 'cljs'
        let platform = fireplace#cljs()
    else
        let platform = fireplace#platform(a:bufnr)
    endif

    let request = platform.Message(
        \ a:msg,
        \ Callback,
        \ )
    let s:pendingRequests[request.id] = 1
endfunc
