mantel
======

*Pretty decoration for your Fireplace*

## What?

Mantel is a plugin for Vim that provides asynchronous, semantic highlighting
for Clojure and Clojurescript. We make use of the new asynchronous nrepl
communication offered in latest versions of [vim-fireplace][1] and some clever
tricks to extract the vars in use in your namespace and assign then an
appropriate syntax group, augmenting the builtin syntax highlighting.

### Supported environments

Mantel uses an active [vim-fireplace][1] connection to query for things
to highlight. It has been tested and used with:

* [Leiningen][4] REPL (Clojure)
* [Leiningen + Figwheel][5] (Clojurescript)
* [shadow-cljs][6] (Clojurescript)

### Highlighted elements

* Local functions, vars, macros
* Imported (required) functions, vars, macros
* Imported class names + constructors (in clojure)
* Aliased functions, vars, macros (IE things namespaced from `:refer :as`; requires [cider-nrepl][3])

## How?

Install with your favorite method. You'll also need [vim-fireplace][1].
I like [vim-plug][2]:

```vim
Plug 'tpope/vim-fireplace'
Plug 'dhleong/vim-mantel'
```

For full semantic coloring support, [cider-nrepl][3] is recommended.

[1]: https://github.com/tpope/vim-fireplace
[2]: https://github.com/junegunn/vim-plug
[3]: https://github.com/clojure-emacs/cider-nrepl
[4]: https://github.com/technomancy/leiningen
[5]: https://github.com/bhauman/lein-figwheel
[6]: http://shadow-cljs.org/
