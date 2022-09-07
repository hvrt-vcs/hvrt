# Havarti

## "It just gets better with time!" - Ethan, probably

#### Havarti is a Hybrid VCS that works just as well distributed as it does centralized.

The distributed VCS revolution (lead primarily by `git`) has been a boon to
programmers everywhere and has made VCS software take cryptographic confirmable
code backups and management as a critical core feature: any new VCS cannot hope
to succeed without it.

`git` was developed to meet the needs of the completely distributed development
of the Linux kernel. However, not all software projects are the Linux kernel.
Different workflows are required by different groups and companies. Hybrid
solutions are the most ideal to address these. In essence, being able to work
completely distributed, or completely centralized, and everything in between.
Few, if any, open-source version control systems has done this successfully.
Havarti aims to change that.

When you take the vowels out of Havarti, you are left with `hvrt` (the name of
the tool). We could probably treat it as an acronym, like "**H**ybrid **V**CS
\<something\> \<something\>". Let me know if you think of something clever for
the last two letters. Regardless, read below to learn why Havarti is special
and interesting compared to other VCSs and if it might meet your needs:

* It supports tracking explicit file renames _and_ file copies.
* It is a single binary, easy to install with no external dependencies.
* Cross platform (Windows, Mac, Linux, *BSD, and more)
* It can run either distributed or centralized or a combination of the two.
* It is backed by a SQL database (sqlite), so most operations are _fast_.
* It can handle files of any size.
* It can retrieve only metadata without file data, and grab file data lazily
  from an external source (which works well with large centralized monorepos).
* It can retrieve/checkout only parts of a source tree (also good for large
  monorepos).
* It can grab shallow clones to make local repos even smaller (historical
  commits, both data and metadata, can be retrieved from upstream as only
  when needed).

Some things it doesn't do:
* It doesn't add issues, wiki, forum, etc. like `fossil` does (for as awesome as
  this all is, the above list a lot to deal with already). Hopefully someone
  will come along and fork gitea and make it work for Havarti, so then you only
  need to download _two_ binaries, instead of just one :)
* There are no plans to support bi-directional bridges from/to `git`, `fossil`,
  or anything else at the moment. This will probably change with
  time/popularity. However there will likely be a `git` importer, and there will
  definitely be a patch exporter/importer.

## Why this and why now?

I like `fossil` and `git` (and others) a lot, but they lack several key
things that matter to me:
* Explicit renames and copy tracking
  - I'm not sure if `fossil` supports this. Regardless, it lacks other features
    listed below (and not listed below), so even if it had this feature, it
    wouldn't be enough to push me over the edge to use it full time.
  - `git` does this heuristically and can miss renames if file content changes
    drastically in the same commit where the rename happened, or if a squash
    causes the commit with the rename to be combined with other commits that
    make so many changes to the renamed file that the rename cannot be detected
    anymore post-squash.
  - Story time: at a previous job I was working on a Ruby on Rails app that
    had been around for several years before I started maintaining it. So that
    the app wouldn't break when we made potentially breaking changes, I
    versioned API endpoints by copying them (e.g. `v3` -> `v4`) and then
    modified the code from there. This seemed Ok at first until I needed to
    run `git blame` to figure out why a certain piece of code did things the
    way it did. Sadly, no history was kept of the copy. Luckily, I hadn't yet
    pushed upstream so I was able to rewrite my history before pushing. I
    ended up using a trick that I had found online; basically, branch, rename
    the files, then immediately merge the branch. Now both the old and new
    files would show up in `git blame`. This worked ok, although it was
    klunky. Also, it worked because it was a small company with only a few
    developers and no one questioned my weird commit tree structure.
  - At larger companies, it isn't uncommon for feature branches
    to get completely squashed down to one commit to make dev history
    "cleaner". However, this introduces the problem that our nifty little
    diamond merge trick from the previous bullet point doesn't work anymore.
    Even on VCSs that support renames I don't know of any that support tracking
    copies, even though this is a useful feature under certain circumstances
    like the one I experienced. And it is no harder to track copies than it is
    to track renames, so you might as well do both if you're going to do one.
  - `hg` supposedly supports renames, but, again, it has other problems that
    are a turn off to me.
* Support of any file size
    - I have worked at a pinball game company in the past. Many of our workflows
      came from the video game industry. Handling big files well in a VCS is a
      prerequisite, which is why lots of places use Perforce or Plastic, both of
      which support large files pretty well. We used `git` and `git-lfs` and it
      was a pain at the time. It's probably gotten easier since then.
    - `git` can handle large files locally, since they are just dumped directly
      to disk in the repo (so whatever limits the file system supports, `git`
      supports). However, without a centralizing feature, this becomes harder to
      use. There are third party tools for this (like `git-lfs` and `scalar`
      from Microsoft), but really, `git` wasn't built for this.
    - `fossil` only supports files up to the size of a sqlite blob, which is
      around 2GB. Realistically it is far less than that with
      performance degrading with really large blobs (since memory needs to be
      allocated for the whole blob and then the entire thing must be completely
      read into memory all at once). `hvrt` instead divides the files into much
      smaller chunks and streams them into memory as needed. The chunk size is
      configurable when initially creating or later repacking the database.
    - `hg` supports this in the same way `git` does: locally and remotely via
      extensions.
* Support for centralized workflows
  - Although `fossil` has default behaviors that support centralized
    workflows (like autosyncing and pushing all branches publicly upstream by
    default) which I prefer and think are awesome, it is still clearly a
    distributed VCS in its data model and logic and has no provision for
    working with truly centralized repos.
  - `hg` supports centralized repos via extensions created for (and by)
    FaceBook/Meta. However hg is not a single binary and is
    difficult to use in environments where installing large runtimes,
    package dependencies, and extensions is just not feasible (this happens
    surprisingly often with in house development non-software companies).
  - `git` is slowly growing support for this as large contributors like
    Microsoft develop extensions for it, but, like `hg`, this isn't how it was
    originally developed to work and it only works via extensions, work arounds,
    and (sometimes nasty) hacks. Given that Linus Torvalds designed `git` and
    uses `git` for distributed Kernel development, it's distributed focus is
    unlikely to ever change either. Case in point, none of the tools to support
    these features have ever been brought into mainline `git`. My guess is that
    they never will be.
* Support for multiple SQL backends
  - This makes the above centralized workflows easier to implement and scale.
  - `fossil` was created by the author of sqlite in order to support the
    development of sqlite. I doubt he has any interest in supporting any other
    SQL backends.
  - `git` and `hg` are "piles of files" systems. It seems unlikely this will
    change for some reason. For as interesting as this style of data management
    is, it is limiting for extending the system. A "real" database just seems
    cleaner to me; since sqlite works basically everywhere, it fits the bill
    quite well for local repo storage, even in a more centralized model.

#### Ideas for future features (no promises that these will ever happen)
* file pinning
  - This is probably pretty similar to something like `git-lfs`. Basically, for
    particularly large files, make it possible to pin a particular version/blob
    hash and not pull updates by default. This is especially useful for game
    studios where users don't need to pull updates for assets they don't care
    about at a given point in time.
* binary deltas for storage and transmission
  - Adding this will make file pinning far more appealing, since users will
    actually want to store their files in the repo as opposed to "out-of-band"
    storage on S3 or whatever. Also it will be lighter to pull updates on large
    binary files when one decides to do so.
* Support more SQL databases than just sqlite, postgres is the first planned
  after sqlite, but given that the database uses pretty much only strings and
  blobs, it should work on nearly any SQL db. This would also make creating
  systems like Github/Gitlab/Bitbucket much easier, or at least potentially
  cleaner.
* Add support for storing blobs (which is the bulk of data, by byte percentage)
  outside the main SQL database (for example, on disk or in S3 style object
  storage). Then the upstream database can be much smaller and lighter, since
  the "foreign key" is just a cryptographic hash that points somewhere else.
* Add support for clients to stream blobs from somewhere other than directly
  from the upstream repo (for example, just let the upstream repo return a map
  of presigned S3 urls for the client to retrieve directly, thus freeing up more
  resources on the upstream VCS servers and opening up bandwidth). Clients could
  potentially also retrieve hashed blobs from a read-only network mounted file
  share in "piles of files" fashion.
* Possibly add support for locking. This would be pretty simplistic. Basically,
  just add a commit that says (via internal data structures): "so-and-so locked
  files x, y, and z", then if anyone, including the user who locked them, tries
  to commit modified versions of those files, the VCS will refuse (although they
  could do the changes in a separate branch where the files weren't locked,
  based on this model, so perhaps more thought is needed). Changes to locked
  files could be committed at the same time as an unlock call on the same files,
  so once the user wants to commit their changes, they just run `hvrt unlock
  <files> && hvrt commit <same files>`. Locking and unlocking would be like
  renaming and copying: it would be staged for the next commit.
  - Since adding authentication and authorization is beyond the scope of all
    this, technically **anyone** could unlock the file. However their name would
    show up on the commit, leaving a paper trail. In an environment where it
    matters (and repo owners are worried about contributors spoofing committer
    and author metadata), they could just sign their commits with PGP (or
    something) to prove who actually made or approved the commit. "Won't
    lock/unlock support junk up the commit history?" Yes and no. If a commit
    only contains locking or unlocking changes with nothing else in them, a UI
    could just collapse/hide them. On the other hand, some files should perhaps
    rarely or **never** be unlocked. Having metadata tracked regarding locking
    allows filtering on that so that reviewers can make sure special files
    aren't fiddled with, ever. Server side, the VCS could reject commits
    changing these files based on a blacklist and/or whitelist. The upstream VCS
    could also reject locking/unlocking via other mechanisms. For example,
    systems like Github and Gitlab associate SSH keys with certain accounts, not
    to main plain old credentials for simple HTTPS pushing/pulling. If certain
    accounts haven't been authorized to do locking/unlocking, those commits
    could be bounced in a pre-receive hook.


### Design ideas
* Branches
  - In the same vein as `fossil`, branches should be "global" by default (i.e.
    they are marked as global, global branches are pushed/pulled at every sync
    as a matter of policy, autosync is turned on by default, and autosync is
    triggered by creating a global branch). Although it should be possible to
    create local only branches, that needs to be something the user flags
    specifically at creation time. In the same vein of `fossil`'s ethos of
    "don't forget things", global branches should never be deletable, however
    they should be hidable (so as to not junk up the interface once branches are
    no longer relevant to current development). In any interfaces, hiding a
    branch should cause it to appear as a single commit (or some other symbol)
    without any information displayed next to it; clicking/selecting it should
    expand the branch and its information in some way. The only branch that
    should never be hidable is the `trunk` branch. Since `hvrt` is just backed
    by a SQL database, if a user truly needs to delete something globally, they
    can just do that via some SQL. Lastly, "local" branches should be upgradable
    to global branches if so desired, or can be deleted (the only type of
    branches that can be truly deleted). Any commits/blobs on a local branch
    that have not ever been pushed globally should be deleted as well; deletion
    of local branches and commits should require some sort of `--force` flag to
    make it clear that one should not do this. Local branches are also hidable
    and hiding should be considered the default workflow.
  - I don't think a rebase command, even for local branches, is a good idea. I
    agree with the creator of fossil: [rebase is an anti-pattern that is better
    avoided](https://fossil-scm.org/home/doc/trunk/www/rebaseharm.md). One thing
    I've learned over the years is that the easy way to do things should be the
    right way to do things. Making rebasing easy encourages doing things the
    wrong way. If someone wants to do things the wrong way, they will need to do
    it by subverting the system. For example, by exporting one or many patches
    of that branch and then applying the patch(es) in a globally accessible
    branch. Although it is possible, it is ugly and difficult to do things this
    way, and it should be, because rebasing is almost always the wrong way to do
    it. Not being able to rebase should also [encourage better commit
    messages](https://xkcd.com/1296/), even if it is only by a little, since a
    developer knows that they can't easily squash or rebase crummy commit
    messages to make them disappear. If other people want to wrap tools around
    `hvrt` to make a rebase command, they are free to do so (since, again, it is
    just exporting and applying patches across a range of commits, so the
    functionality is completely possible given the core functionality of the
    tool), but it won't ever be part of the tool proper.
* Commit message annotations
  - `fossil` supports this. Basically, the original commit message and metadata
    remains unchanged and is used for the hash calculation, but annotations are
    just edits layered on top; they are extra data (like an edit button on an
    online post that still lets you see the state of the post prior to the
    edit). This removes some of the need to do squashing and rebasing; any
    mistakes in code can be clarified in updated commit messages. Other metadata
    like author and committer can also be annotated (again, leaving the original
    commit metadata unmolested, since it is required to be unchanged for proper
    cryptographic hashing).
* Since we are using golang, there is a unified interface for connecting to
  different SQL databases. We'll probably still need to deal with DB specific
  syntax and idiosyncracies, but that's fine: we just need to write tests that
  are backend agnostic (i.e. they are only looking at the data that comes out
  of the DB, and only use features common to all DBs, such as foreign key
  constraints).
* Since PostgreSQL is most similar to Sqlite, we will aim for that as our second
  backend.
* File renames can be tracked by using a file id (FID). This can be thought of
  like an inode, kind of. FIDs have a source FID (or a parent, if you want). If
  a file is renamed or copied from an existing FID, then the FID it was renamed
  or copied from is its source FID. If an FID was created without a source FID,
  then it's source FID is just null. The FID is pseudorandom: it is a hash
  derived from several values: (1) the file path relative to the root of the
  repo preceded by (2) the hash of the parent commit(s). These two values should
  be enough to ensure uniqueness and reproducibility. The same FID is referred
  to forever until and if the file is deleted or renamed; a copied file does not
  affect it's source FID. If the file at the same path is recreated in the next
  commit, it receives a new FID (which should be unique since it is derived from
  a unique commit hash, even if the path that is added to the hash is the same
  as before), and it's source FIDs should either be null (if it is created ex
  nihilo) or the FIDs of whatever it was copied from; it should NOT have the
  source FID of the file at the same path that was previously deleted. Automatic
  Rename detection can, and should, be used at commit time (like `git`, but
  detected at commit time instead of after the fact, ad hoc).
    - With all this in mind, there is no real difference between a rename and a
      copy: if a file is copied AND renamed in the same commit, the system sees
      them equally. The system sees them both as derived copies. So a rename is
      really just a single copy combined with the deletion of the source in the
      same commit. However, the new file can be completely rewritten and still
      point back to its source, unlike `git`, which requires two commits to do the
      same thing (assuming those two commits don't get squashed together
      somehow, which is a common workflow in `git`).
    - All of this makes it trivially fast and easy to ask about the full history
      of a file (e.g. blame/annotate), even across renames/copies.
    - A file can have more than one source FID. For example, when merging two
      files together, this can be useful.
      - The tool for copying multiple files together should be called
        `hvrt cp-cat <source 1> [<source 2> ...] <destination>` and should, by
        default, concatenate the contents of the source file(s) to the
        destination file (although the concatenation behavior can be turned off
        with a flag).
