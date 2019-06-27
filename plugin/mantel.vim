
augroup MantelAutoHighlightGroup
    autocmd!
    autocmd BufRead *.clj,*.clj[cs] call mantel#TryHighlight()
augroup END

