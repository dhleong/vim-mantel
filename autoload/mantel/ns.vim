
" ======= constants =======================================

let s:maxNsLines = 100


" ======= Callbacks =======================================

func! s:onNsEval(bufnr, resp)
    if has_key(a:resp, 'err')
        echom 'ERROR' . string(a:resp)
        return
    elseif !has_key(a:resp, 'value')
        return
    endif

    echom a:resp

    call mantel#async#AdjustPendingRequests(a:bufnr, -1)
endfunc

func! s:onPath(bufnr, resp)
    if !has_key(a:resp, 'path')
        return
    endif

    let path = a:resp.path
    echom "got path: " . path
    let contents = join(readfile(path, '', s:maxNsLines), '\n')
    let readerNs = 'clojure.edn'
    if matchstr(path, '.cljs$') !=# ''
        let readerNs = 'cljs.reader'
    endif

    " TODO 
    let request = '(let [ns-form (->> "' . escape(contents, '"') . '"'
              \ . '                   (' . readerNs . '/read-string))'
              \ . '      macros (filter'
              \ . '               #(and (seq? %)'
              \ . '                     (= :require-macros (first %)))'
              \ . '               ns-form)'
              \ . '      refers (filter'
              \ . '               #(and (seq? %)'
              \ . '                     (= :require (first %)))'
              \ . '               ns-form)]'
              \ . '  refers)'
    echom "request: " . request
    call fireplace#message({
        \ 'op': 'eval',
        \ 'code': request,
        \ }, function('s:onNsEval', [a:bufnr]))
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
