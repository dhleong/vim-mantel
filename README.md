mantel
======

*Pretty decoration for your Fireplace*

## What?

Mantel is a plugin for Vim that provides asynchronous, semantic highlighting
for Clojure and Clojurescript. We make use of the new asynchronous nrepl
communication offered in latest versions of [vim-fireplace][1] and some clever
tricks to extract the vars in use in your namespace and assign then an
appropriate syntax group, augmenting the builtin syntax highlighting.

## How?

Install with your favorite method. You'll also need [vim-fireplace][1].
I like [vim-plug][2]:

```vim
Plug 'tpope/vim-fireplace'
Plug 'dhleong/vim-mantel'
```

[1]: https://github.com/tpope/vim-fireplace
[2]: https://github.com/junegunn/vim-plug
