
augroup MantelAutoHighlightGroup
    autocmd!
    autocmd BufReadPost *.clj,*.clj[cs] call mantel#TryHighlight()
    autocmd BufWritePost *.clj,*.clj[cs] call mantel#TryHighlight('always')
augroup END

