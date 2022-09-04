# Havarti

## "It just gets better with time!"

#### Havarti is a Hybrid VCS that works just as well distributed as it does centralized.

When you take the vowels out of Havarti, you are left with `hvrt` (the name of
the tool). We could probably some sort of acronym, like "**H**ybrid **V**CS \<somthing> \<something>". Let me know if you think of something clever for the last two
letters.

Some features that set it apart from other VCSs:
* It can run distributed or centralized (something no other VCS offers out of the box).
* It supports tracking explicit file renames and file copies (unlike git, hg, fossil, etc.)
* It is a single binary, easy to install with no external dependencies (unlike git)
* Cross platform (git's support for windows is an
  afterthought, which is why it gets installed with MSYS2/Cygwin)
* It is backed by a SQL database (sqlite as the default)
* It can be backed by different DB backends (sqlite or postgres, unlike fossil
  which only supports sqlite)
* It can handle files of any size (unlike fossil, which can only
  handle files ~1GB large)
* It can retrieve only metadata without file data (making local repos vastly
  smaller, and supporting a more centralized model), and grab file data lazily
  from an external source (which  works well with extremely large monorepos).
* It can checkout only parts of a source tree (ala SVN)
* It can grab shallow clones to make local repos even smaller (historical
  commits, both data and metadata, are assumed to be available upstream)

Some things it doesn't do:
* It doesn't add issues, wiki, etc. like fossil does (for as awesome as this
  all is, the above list a lot to deal with already)
* There are no plans to support bi-directional bridges from/to git, fossil, or anything else
  at the moment. Although there likely be a git importer, and there will definitely
  be a patch exporter.

## Why this and why now?

I like fossil a lot, but it is lacking several key things that matter to me:
* Explicit renames (this may not matter to Torvalds, but this matters for code
  archeology, which many devs need to deal with)
* Support of any file size (git supports this, but it lacks explicit file
  renames and other features which matter to me)

Once I decided to go down this path I also realized that the system could be
made to support multiple RDBMS backends, since, hey, we're starting from
scratch anyway. This would also make creating systems like
Github/Gitlab/Bitbucket much easier, or at least potentially cleaner.
