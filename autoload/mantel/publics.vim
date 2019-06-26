func! mantel#publics#FetchVarsForPairs(bufnr, prefixAndNsPairs) abort
    " Given a collection of [prefix, ns] pairs, fetch public vars
    " from each ns, prefixed with the associated prefix

    " convert input (list of tuples) to edn format
    let pairs = []
    for [prefix, ns] in a:prefixAndNsPairs
        " we call ns-publics directly to workaround the clojurescript
        " limitation of (ns-publics) being a macro
        call add(pairs, printf("[\"%s\", (ns-publics '%s)]", prefix, ns))
    endfor

    " we could also just use cider's `ns-vars-with-meta` op and parse the
    " results in vim... but we'd have to issue N requests and coordinate them
    " all. Plus, this lets us do the processing asynchronously
    let request = '(mapcat '
              \ . '  (fn [[prefix publics]]'
              \ . '    (->> publics'
              \ . '         (map (fn [[var-name var-ref]]'
              \ . '                 {:alias (str prefix var-name)'
              \ . '                  :var-ref var-ref}))))'
              \ . '  [' . join(pairs, ' ') . '])'
    call mantel#nrepl#FetchVarsViaEval(a:bufnr, request)
endfunc
