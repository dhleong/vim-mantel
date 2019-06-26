" ======= public ==========================================

func! mantel#refers#Fetch(bufnr, ns)
    let request = "(->> (ns-refers '" . a:ns . ')'
              \ . '     (map second)'
              \ . '     (filter #(not= "clojure.core"'
              \ . '                    (->> % meta :ns)))'
              \ . '     (map (fn [var-ref]'
              \ . '             {:alias (-> var-ref meta :name)'
              \ . '              :var-ref var-ref})))'
    call mantel#nrepl#FetchVarsViaEval(a:bufnr, request)
endfunc
