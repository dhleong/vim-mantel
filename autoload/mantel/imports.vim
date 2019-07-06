func! mantel#imports#Fetch(bufnr, ns)
    " Fetch imported classes for the given namespace
    " Currently we also include constructor use (eg `(ArrayList.)`) as
    " a clojureVariable, but future use might consider highlighting that
    " as clojureFunc.
    let request = "(->> (ns-imports '" . a:ns . ')'
              \ . '     (mapcat (fn [[class-name klass]]'
              \ . '               [class-name'
              \ . '                #?(:clj  (.getName klass)'
              \ . '                   :cljs nil)]))'
              \ . '     (keep identity)'
              \ . '     (mapcat #(vector % (str % "."))))'
    call mantel#nrepl#FetchTypedVarsViaEval(
        \ a:bufnr,
        \ 'clojureVariable',
        \ request,
        \ )
endfunc
