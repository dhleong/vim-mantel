
" ======= constants =======================================

let s:maxNsLines = 100


" ======= Callbacks =======================================

func! s:onNsEval(bufnr, resp)
    if has_key(a:resp, 'macros')
        " we can't get meta on these, but they were explicitly
        " refer'd as macros, so they ought to be
        call mantel#async#ConcatSyntaxKeys(
            \ a:bufnr,
            \ 'clojureMacro',
            \ a:resp.macros,
            \ )
    endif

    if has_key(a:resp, 'vars') && len(a:resp.vars)
        " okay, one more hop: resolve the types of the non-macro referred vars
        let vars = map(a:resp.vars, '"{:var-ref (var " . v:val . ")}"')
        let request = '[' . join(vars, ' ') . ']'
        call mantel#nrepl#FetchVarsViaEval(a:bufnr, request)
    endif

    " this async bit is done
    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc

func! s:onPath(bufnr, resp)
    if !has_key(a:resp, 'path')
        return
    endif

    let path = a:resp.path
    let contents = join(readfile(path, '', s:maxNsLines), '\n')
    let readerNs = 'cljs.reader'  " we're *probably* in clojurescript
    if matchstr(path, '.cljs$') ==# ''
        let readerNs = 'clojure.edn'
    endif

    " NOTE: since accessing var metadata and things like (ns-publics) are
    " compile-time *only* in clojurescript, we have to first fetch the
    " symbols, then issue *another* request to get their info
    let request = '(let [ns-form (->> "' . escape(contents, '"') . '"'
              \ . '                   (' . readerNs . '/read-string))'
              \ . '      parsed (binding [cljs.env/*compiler* (atom nil)]'
              \ . '               (cljs.analyzer/parse'
              \ . "                 'ns"
              \ . '                 (cljs.analyzer/empty-env)'
              \ . '                 ns-form))]'
              \ . '  {:macros (map first (:use-macros parsed))'
              \ . '   :vars (map (fn [[var-name var-ns]]'
              \ . '                (str var-ns "/" var-name))'
              \ . '              (:uses parsed))})'

    call mantel#nrepl#EvalAsVim(
        \ request,
        \ function('s:onNsEval', [a:bufnr]))
endfunc


" ======= Public interface ================================

func! mantel#ns#ParseReferred(bufnr, ns)
    " Parse the (ns) form for the given ns and extract :refer'd vars.
    " This is for situations where ns-refers isn't available, and is
    " likely a *terrible* idea.

    call mantel#async#AdjustPendingRequests(a:bufnr, 1)
    call fireplace#message({
        \ 'op': 'ns-path',
        \ 'ns': a:ns,
        \ }, function('s:onPath', [a:bufnr]))
endfunc
