
" ======= callbacks =======================================


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

    call mantel#ns#FetchVarsForPairs(a:bufnr, pairs)
    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc


" ======= Public interface ================================

func! mantel#aliases#Fetch(bufnr)
    " Fetch vars prefixed with a namespace alias

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)

    " fetch aliased namespaces (eg: clojure.spec :as s) so we can fetch public
    " vars in each
    call fireplace#message({'op': 'ns-aliases'},
        \ function('s:onNsAliases', [a:bufnr]))
endfunc
