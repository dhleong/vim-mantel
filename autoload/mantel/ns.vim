
" ======= constants =======================================

let s:maxNsLines = 100


" ======= utils ===========================================

func! s:trimToNsForm(contents)
    let contents = a:contents
    let i = 0
    let nesting = 0
    let hasSeenNs = 0

    while i < len(contents)
        if contents[i] ==# '('
            let nesting += 1
        elseif contents[i] ==# ')'
            let nesting -= 1
        endif

        if nesting == 0 && hasSeenNs
            return contents[:i]
        elseif !hasSeenNs && nesting > 0
            " see if this is the ns form
            if contents[i-1:] =~# '\<ns\>'
                let hasSeenNs = 1
            endif
        endif

        let i += 1
    endwhile

    return contents
endfunc


" ======= Callbacks =======================================

func! s:onNsEval(bufnr, vars)
    if type(a:vars) != type([])
        return
    endif

    if len(a:vars)
        " okay, one more hop: resolve the types of the non-macro referred vars
        let vars = []
        for v in a:vars
            " if we can't resolve the var, it might be a macro
            call add(vars, "(if-let [var-ref (resolve '" . v . ')]'
                        \. '  {:var-ref var-ref}'
                        \. "  {:?macro '" . v . '})')
        endfor
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
    if !filereadable(path)
        " probably given a relative path
        return
    endif

    let contents = join(readfile(path, '', s:maxNsLines), '\n')
    let contents = s:trimToNsForm(contents)

    let readerNs = 'cljs.reader'  " we're *probably* in clojurescript
    if matchstr(path, '.cljs$') ==# ''
        let readerNs = 'clojure.edn'
    endif

    " ensure the cljs analyzer ns is loaded
    call fireplace#message({
        \ 'op': 'eval',
        \ 'code': "(require 'cljs.analyzer)"
        \ })

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
              \ . '  (->> (concat'
              \ . '         (:use-macros parsed)'
              \ . '         (:uses parsed))'
              \ . '       (map (fn [[var-name var-ns]]'
              \ . '              (str var-ns "/" var-name)))))'

    call mantel#nrepl#EvalAsVim(
        \ a:bufnr,
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

func! mantel#ns#ParseReferredPath(bufnr, path)
    " Version of ParseReferred where the path to the file is provided
    " directly. ns-path occasionally returns a relative path, and I'm
    " not sure how to extract the relative path

    " NOTE: this isn't async, but some of the callbacks assume that
    " there's an async request pending, so let's make it happen here
    call mantel#async#AdjustPendingRequests(a:bufnr, 1)
    call s:onPath(a:bufnr, {'path': a:path})
endfunc
