
let s:lastHighlightChange = -1

" ======= utils ===========================================

func! s:hasNsRefers(bufnr)
    " only cljs seems to lack this
    return expand('#' . a:bufnr . ':e') !=# 'cljs'
endfunc


" ======= Public interface ================================

func! mantel#Highlight() abort
    " cancel all pending
    call mantel#async#Cancel()

    " reset pending state for new request
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
    else
        " attempt to parse the (ns) form of the current file
        " to extract referred vars
        call mantel#ns#ParseReferredPath(bufnr, expand('%:p'))
    endif

    " fetch imported classes
    call mantel#imports#Fetch(bufnr, ns)
endfunc

func! mantel#TryHighlight(...) abort
    let change = changenr()
    if change == s:lastHighlightChange && a:0 == 0
        " Nop; avoid unnecessary highlight requests
        return
    endif
    let s:lastHighlightChange = change

    " Attempt to perform highlighting if there's an active
    " fireplace repl connection available
    if fireplace#op_available('eval')
        try
            " this line acts as an explicit piggiebacked check:
            call fireplace#client()

            call mantel#Highlight()
        catch /not an open channel/
        catch /REPL/
        catch /AssertionError/
            " occurs when not run on a cljs file when not piggiebacked
        endtry
    endif
endfunc
