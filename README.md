# Havarti

## "It just gets better with time!"

#### Havarti is a Hybrid VCS that works just as well distributed as it does centralized.

When you take the vowels out of Havarti, you are left with `hvrt` (the name of
the tool). We could probably treat it like sort of acronym, like "**H**ybrid **V**CS
\<something\> \<something\>". Let me know if you think of something clever for
the last two letters.

Some features that make it interesting compared other VCSs:
* It can run either distributed or centralized.
* It supports tracking explicit file renames _and_ file copies.
* It is a single binary, easy to install with no external dependencies.
* Cross platform (Windows, Mac, Linux, *BSD, and more)
* It is backed by a SQL database (sqlite as the default)
* It can be backed by different DB backends (sqlite or postgres)
* It can handle files of any size.
* It can retrieve only metadata without file data (making local repos vastly
  smaller, and supporting a more centralized model), and grab file data lazily
  from an external source (which  works well with extremely large monorepos).
* It can retrieve/checkout only parts of a source tree.
* It can grab shallow clones to make local repos even smaller (historical
  commits, both data and metadata, are assumed to be available upstream).

Some things it doesn't do:
* It doesn't add issues, wiki, forum, etc. like fossil does (for as awesome as
  this all is, the above list a lot to deal with already)
* There are no plans to support bi-directional bridges from/to git, fossil, or anything else
  at the moment. Although there likely be a git importer, and there will definitely
  be a patch exporter.

## Why this and why now?

I like fossil a lot, but it is lacking several key things that matter to me:
* Explicit renames (git does this heuristically and can miss renames if files
  change drastically from one commit to the next, or if a squash causes the commit
  with the rename to be lost).
* Support of any file size (fossil only supports files up to the size of a
  sqlite blob, which is around 1GB).

Once I decided to go down this path I also realized that the system could be
made to support multiple RDBMS backends, since, hey, we're starting from
scratch anyway. This would also make creating systems like
Github/Gitlab/Bitbucket much easier, or at least potentially cleaner.
