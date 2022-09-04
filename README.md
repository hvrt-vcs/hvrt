# yadv is Yet Another Distributed VCS

It has some important features that set it apart from other DVCSs:
* It supports explicit renames and file copies (unlike git, hg, fossil, etc.)
* It is a single binary, easy to install with no external dependencies (like
  fossil, unlike git)
* Cross platform (fossil supports this, but git support for windows is an
  afterthought, which is why it gets installed with MSYS2/Cygwin)
* It is backed by a "true" database (like fossil)
* It can be backed by different DB backends (sqlite or postgres, unlike fossil
  which only supports sqlite)
* It can handle files of any size (like git and unlike fossil, which can only
  handle files ~1GB large)
* It can retrieve only metadata without file data (making local repos vastly
  smaller), and grab file data lazily from an external source (this is much
  more SVN like, and works well with extremely large monorepos).
* It can checkout only parts of a source tree (ala SVN)
* It can grab shallow clones to make local repos even smaller. (maybe, we'll
  see on this one)

Some things it doesn't do:
* It doesn't add issues, wiki, etc. like fossil does (for as awesome as this
  all is, the above list a lot to deal with already)
* There are no plans to support bridges from/to git, fossil, or anything else
  at the moment. Although there may be a git importer, and there will definitly
  be a patch exporter.

## Why this and why now?

I like fossil a lot, but it is lacking several key things that matter to me:
* Explicit renames (this may not matter to Torvalds, but this matters for code
  archeology, which many devs need to deal with)
* Support of any file size (git supports this, but it lacks explicit file
  renames and other features which matter to me)

Once I decided to go down this path I also realized that the system could be
made to support multiple RDBMS backends, since, hey, we're starting from
scratch anyway. This would also make creating systems like Github much easier,
or at least potentially cleaner.

