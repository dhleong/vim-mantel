func! mantel#imports#Fetch(bufnr, ns)
    " Fetch imported vars for the given namespace
    let request = "(->> (ns-imports '" . a:ns . ')'
              \ . '     (mapcat (fn [[class-name klass]]'
              \ . '               [class-name'
              \ . '                (.getName klass)])))'
    call mantel#nrepl#FetchTypedVarsViaEval(
        \ a:bufnr,
        \ 'clojureVariable',
        \ request,
        \ )
endfunc
