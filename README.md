# Havarti

## What do you do when you take a snapshot? You say "Cheese!"

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
* Cross platform (Windows, Mac, Linux, and more)
* It can run either distributed or centralized or a combination of the two.
* It is backed by a SQL database (sqlite), so most operations are _fast_.
* It can handle files of any size.
* It can retrieve only metadata without file data, and grab file data lazily
  from an external source (which works well with large centralized monorepos).
* It can grab narrow clones (i.e. retrieve/checkout only parts of a source tree
  which is also good for large monorepos).
* It can grab shallow clones to make local repos even smaller (historical
  commits, both data and metadata, can be retrieved from upstream only when
  needed).

Here is quick comparison of Havarti to Git, Fossil, Mercurial, and Subversion.
Havarti's features were chosen primarily because they matter to me. Maybe value
similar features:

| Feature                                   | Havarti | Git    | Fossil | Mercurial | Subversion |
|:------------------------------------------|:--------|:-------|:-------|:----------|:-----------|
| **Explicit File Renames**                 | ✔️       | ❌[1][] | ❔      | ✔️         | ✔️          |
| **Explicit File Copies**                  | ✔️       | ❌[1][] | ❔      | ✔️         | ✔️          |
| **Single Binary**                         | ✔️       | ❌      | ✔️      | ❌         | ❌          |
| **Native Cross Platform**                 | ✔️       | ❕[2][] | ✔️      | ✔️         | ✔️          |
| **Commit offline (i.e. distributed)**     | ✔️       | ✔️      | ✔️      | ✔️         | ❌          |
| **Centralized model**                     | ✔️       | ❕[3][] | ❌      | ❕[4][]    | ✔️          |
| **Autosync with upstream (configurable)** | ✔️       | ❌      | ✔️      | ❌         | ✔️[5][]     |
| [**Shallow clone**][9]                    | ✔️       | ✔️      | ❔      | ✔️         | ✔️[5][]     |
| [**Partial clone**][9]                    | ✔️       | ✔️      | ❌      | ❌[4][]    | ✔️[5][]     |
| **Narrow clone/checkout**                 | ✔️       | ❌      | ❌      | ❌[4][]    | ✔️[5][]     |
| **Any file size**                         | ✔️       | ✔️      | ❌      | ✔️         | ✔️          |
| **History rewriting abilities** [6][]     | ✔️       | ✔️      | ❌      | ✔️         | ❌          |
| **Serve static content as a website**     | ✔️       | ❌      | ✔️      | ❌         | ❌          |
| **Bidirectional bridge to git**           | ❌       | ✔️      | ❌      | ✔️         | ✔️          |
| **Builtin issue tracker, etc.**           | ❌       | ❌      | ✔️      | ❌         | ❌          |

[1]: # "Lazily calculated heuristically from tree snapshots. Slower than eagerly calculating. Can be wrong depending on CLI flags passed to `git blame` or level of change between diffs."
[2]: # "Windows support via a Posix compatibility layer."
[3]: # "Possible with shallow clones, partial clones, and extensions."
[4]: # "Available via extensions."
[5]: # "Not just SVN, but All centralized VCSs support this behavior since they don't clone, they checkout."
[6]: # "Disallowing users to do dangerous things also makes it impossible for them to do clever things. Don't arbitrarily handicap users."

[9]: https://github.blog/2020-12-21-get-up-to-speed-with-partial-clone-and-shallow-clone/

Some things it doesn't do:
* It doesn't add issues, wiki, forum, etc. like `fossil` does (for as awesome as
  this all is, the above list a lot to deal with already). Hopefully someone
  will come along and fork gitea and make it work for Havarti instead of (or
  along with) git, so then you only need to download _two_ binaries, instead of
  just one :)
* There are no immediate plans to support bi-directional bridges from/to `git`,
  `fossil`, or anything else at the moment. This will probably change with
  time/popularity. However there will likely be a `git` importer, and there will
  definitely be a patch exporter/importer.
* It doesn't make rewriting history easy (like `git rebase`), although it does
  make it possible (unlike `fossil`).

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
    difficult to use in environments where installing large runtimes (python),
    package dependencies, and extensions is just not feasible (this happens
    surprisingly often with in-house development at non-software companies).
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
    is, it is limiting for extending the system to other backends. A SQL
    database just seems cleaner to me, since many databases support the SQL
    standard so porting should be relatively easy; since sqlite works basically
    everywhere, it fits the bill quite well for local repo storage on clients,
    even in a more centralized model.

### Design ideas

Most design choices are based on a single rule/commandment: "Thou shalt not throw away
data". Most issues I have with `git` are that useful data gets thrown away
easily. Usually this is justified with the idea that it creates "clean history".
I'm not sure that is good enough justification. Some examples of git playing
loose and fast with it's history: branches aren't synchronized by default,
renames and copies aren't explicitly tracked, rebasing/squashing is done all the time
because the default tools make it easy, and so on). It is better to layer extra
data on top of what exists, or add metadata to hide data that is rarely needed.
Metadata is incredibly small, and therefore, cheap. Layering extra metadata or
hiding the a small amount of metadata costs little space, and no computation
time if you do not reference or use it.

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
* Don't allow rebasing
  - I don't think a rebase command, even for local branches, is a good idea. I
    agree with the creator of fossil: [rebase is an anti-pattern that is better
    avoided](https://fossil-scm.org/home/doc/trunk/www/rebaseharm.md). One thing
    I've learned over the years is that the easy way to do things should be the
    right way to do things. Making rebasing easy encourages doing things the
    wrong way. If someone wants to do things the wrong way, they will need to do
    it by subverting the system. For example, by exporting one or many patches
    or snapshots of that branch and then applying the patch(es) in a separate
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
  - We should probably clearly define rebase. Really, when people talk about
    rebasing in `git`, they are talking about 3 separate concepts (these muddle
    concepts are combined in `git` mostly because commands are named after
    implementation, not any sort of logical model a user can make. Again, `git`
    is thin on abstractions):
      1. `squash` commits for a "clean" history. Usually done in a feature
        branch before merging into a parent branch. Done with `git merge --squash` or
        `git rebase -i`.
        - Alternative: just use the `bundle` concept described below. You lose
          no history and you gain the clean visual display of a `git` squash.
      2. `replay` commits from a source branch on top of a destination branch.
        Done using `git rebase <upstream>` where the current branch is replayed
        on top of `<upstream>`.
          - Alternative: `replay`s are just merges with lost history, so just
            use a real merge. The UI should make it easy to hide merged branches
            and bundles, thus getting the "clean history" so many git fanboys
            rave about when singing the praises of rewriting history with
            `rebase`.
      3. `reorder` commits from a source branch into an unnamed destination
        branch, then move the named pointer from the source branch to the
        destination branch. Done with `git rebase -i`.
          - Alternative: Suggesting a good alternative is hard since `reorder`
            should simply not be done; the opportunity to royally mess things up
            is not offset by any of the perceived benefits of "logically"
            reordering history (the internet is filled with stories of people
            using `git rebase -i` to completely mess up their history, either
            immediately, or much later down the line when they have already
            garbage collected the original commits and now they have introduced
            subtle bugs because they messed with history order). If possible,
            just `bundle` sets of changes. If it is just some commit messages or
            other metadata that need changing, use commit amendments. If those
            are not enough, it can be done via out of order cherry-picks to a
            new branch (cherry-pick sources are tracked in the repo, so it is
            clear what the original source is), or, if the user is feeling like
            subverting the system, can be done by scripting the copying of
            snapshots or patches, then manually reapplying them on top of the
            current state of the repo (which is really all that `git rebase -i`
            is doing anyway, since it forgets where the cherry-picks came from
            after committing the changes; a cherry-pick in `git` is just a
            regular commit). If a user is worried about tracked cherry-picks
            junking up the history, the connections can be hidden in the UI just
            like merged branches and bundles can be. Just because we have the
            metadata, doesn't mean we need to show it all the time in a UI. In
            fact, we should probably default to **not** showing it other than
            perhaps displaying cherry-pick commits, merge commits, and bundles
            with different shapes and/or colors for their node in the graph. We
            just add a legend to help users know what each shape/color means.
            Probably prefer shapes over colors to support color blind users.
          - Perhaps a `hvrt unsafe` command could be added that can be used on
            local branches for things like `reorder` and `squash` (`replay`,
            again, is a terrible idea; just merge the branch and hide merged
            branches in the UI; or use in-order cherry-picking). Something like
            `hvrt push --force` should not exist; if someone needs to forcefully
            rewrite public (i.e. already pushed) history, they need to have
            direct access (e.g. ssh interactive shell) to the machine where the
            upstream repo lives, not just generic `push` access. Remember, we
            have no identity or authentication systems, in the same way `git`
            does not have them, so if a person has remote `push` access, they
            can do _anything_ that is possible via the tools. Thus, the tools
            should make it impossible to remotely rewrite history. Either that,
            or we nest it under `unsafe` (e.g. `hvrt unsafe push --force`).
          - At the end of the day, a VCS is meant to empower the user to work in
            whatever way they prefer. Unlike `fossil`, perhaps we should allow
            unsafe operations. However, unlike `git`, we will clearly mark
            unsafe operations as such; just because old commits are hidden
            somewhere in the "reflog" after a rebase or squash in `git`, doesn't
            mean the average user has any clue where to find this stuff or how
            to back it out. With the improved data structures and tracked
            metadata of `hvrt`, the need for unsafe operations should be
            severely diminished. `git` throws away lots of metadata (e.g.
            renames and cherry pick sources); it makes rebase more appealing.
            For example, the difference between a `reorder` and a cherry-pick is
            identical in `git`: you are recreating commits and forgetting where
            they came from. If you have bundles and tracked cherry-picks, the
            distinction becomes more pronounced and it makes it more worthwhile
            to use the better tools to do the job. In other words, don't
            disallow doing it the "wrong" way, make doing it the "right" way so
            much better that almost no one wants to do it the "wrong" way. Also,
            flag the "wrong" way as, well, being wrong (under the `unsafe`
            subcommand).
          - The `unsafe` subcommand should just set an unsafe flag and then
            delegate to the underlying command set. Basically, it should act
            like a `--force` flag on all commands. However, because of how it is
            invoked, it should dissuade people from using it. When they post
            online "I used `hvrt unsafe <blah>` and then things broke!" Then
            people will respond "The word 'unsafe' was literally in the command.
            Why were you using an unsafe command if you didn't know what you
            were doing?" Basically, this goes back to allow unsafe operations,
            but dissuade people from using them.
  - Ideas on features that can replace rebasing:
    - Have the concept of a "bundle". A bundle is a pointer to a series of
      commits (much like using rebase to squash commits). In any UIs (textual or
      graphical), bundles are shown in lieu of a series of commits. Bundles can
      have their own metadata, such as a message, author, and date. There can
      also be annotations to bundle metadata, just like there can be with commit
      metadata. By default, merged branches should be flagged as bundles. This
      merged-branch-defaults-to-bundle feature should be overridable via
      configuration. For operations like "bisect" bundles should, by default, be
      treated as a singular unit. That is the multiple individual underlying
      commits should be treated as a single logical commit. There should be a
      flag to override this default behavior and to run bisect against all
      underlying commits. A commit can only ever be part of one bundle. A given
      bundle cannot be a child of another bundle. Should bundles be
      soft-deletable?
    - Perhaps differentiate between "conflicted" merge commits and
      "nonconflicted" merge commits. "nonconflicted" should, for all intents and
      purposes, be ignored in history views. Or should be visually flagged as
      uninteresting, perhaps with a special color or shape. "conflicted" merge
      commits should be visually flagged as such. In this way, reviewers can
      know whether a merge needs inspection or not. This could simply be
      metadata; if a merge is automatically done with no human intervention,
      then it is flagged as "nonconflicted"; if it required any human
      interaction at all, it is considered "conflicted". This is not a piece of
      metadata that should be annotatable via official tools, and it should be
      calculated in a commit's hash.
* Annotations for commit (and bundle) messages
  - `fossil` supports this. Basically, the original commit message and metadata
    remains unchanged and is used for the hash calculation, but annotations are
    just edits layered on top; they are extra data (like an edit button on an
    online post that still lets you see the state of the post prior to the
    edit). This removes some of the need to do squashing and rebasing; any
    mistakes in code can be clarified in updated commit messages. Other metadata
    like author and committer can also be annotated (again, leaving the original
    commit metadata unmolested, since it is required to be unchanged for proper
    cryptographic hashing).
* Have hooks like `git`, but be truly cross platform.
  - So on *nix, just look at the executable flag (just as `git` does). But on
    Windows, look for files of the same name, but with an known file extension
    found in `PATHEXT` envar (e.g. `.COM`, `.EXE`, `.BAT`, `.CMD`, etc.). This
    will put it worlds ahead of "git for Windows" where one needs to have a full
    posix compatibility layer to do hooks on Windows (I should know, I have had
    to do it before).
  - Or maybe just store the scripts/executables as blobs in the local repo? They
    shouldn't clash with anything (again cryptographic hashes shouldn't collide)
    and there could just be a pointer to them in the database, and when a branch
    is checked out on disk those get unpacked as well.
* Ala `fossil`, allow for multiple checkouts per repo to be easy.
  - This way a user can have multiple directories with different branches
    checked out at the same time, make workflows a bit easier.
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
* The command set should be modeled heavily on `fossil`.
  - Only a few places where fossil doesn't include the functionality that we do
    or is confusing should there be much difference.
  - Official command reference: https://fossil-scm.org/home/help

#### Ideas for future features (no promises that these will ever happen)
  * file pinning
    - Make it possible to pin a particular file version/blob hash and not pull
      updates for it by default. This is especially useful for game studios where
      users don't always need to pull updates for large binary blob assets.
    - Pinning should be possible on either file paths, FIDs, or both (see design
      below to understand what FIDs are). Invoking as `hvrt pin <spec>` will work
      with paths or FIDs and will try to do the right thing (look for an file path
      and if that can't be found, look for an FID starting with that value). This
      is only a problem if the user has file paths that are formated like FIDs
      within the directory they are invoking the tool from. To be explicit, they
      can pass a `--fid` or `-i` flag to ensure the spec is treated as a FID, or
      `--path` or `-p` to ensure it is treated as a path.
  * binary deltas for storage and transmission
    - Adding this will make file pinning far more appealing, since users will
      actually want to store their files in the repo as opposed to "out-of-band"
      storage on S3 or whatever. Also it will be lighter to push/pull updates on
      large binary files when one decides to do so.
  * Support SQL databases other than just sqlite. postgres is the first planned
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
  * Much like `fossil`, make it possible to serve files directly from a repo.
    Unlike `fossil`, don't make it use some bespoke wiki format (that seems very
    limiting in the long run). Just allow a repo to serve static files from a
    particular branch under a particular directory (kind of like Github or
    Gitlab). It is interesting that this can be set up in `fossil` with a two
    line CGI script. Being able to push content to a repo and have it show up
    dynamically is a useful feature in a VCS. It is up to the user to create
    those files by hand (e.g. writing html files by hand) or by using static
    site generators like Jekyll or Hugo. Some examples:
      - Keep generated docs under `./docs/html` in the trunk branch and serve
        those files as a static site.
      - Have a branch called `website` and serve files directly from the root
        of the repo.
      - Serve the docs on a per tag basis, so `v1.0`, `v2.0` could be exposed at
        the URL path level and just work. This would probably need to be an
        option in `hvrt` to serve all tags or serve all branches or something.
        Need to explore this idea further.
  * Some command line examples/ideas for potential static site serving CLI:
    - Allow serving multiple branches from multiple site roots. These flags can
      be mixed and repeated.
    - `hvrt serve --version trunk '/www' '/'`: Serve the "www" directory in the
      trunk branch to the root of the website.
    - `hvrt serve --multiple-versions trunk,dev,stable '/docs/html' '/docs'`:
      Serve the "docs/html" directory of each branch under the "docs" path of
      the site. For example, for the `trunk` branch, it serves "docs/html" to
      "docs/trunk", for the `dev` branch it serves to "docs/dev", and so on.
    - `hvrt serve --regex-versions '[0-9]\.[0-9]\.[0-9]' '/docs/html' '/docs/versioned'`:
      Serve the "docs/html" directory of each version that matches a simple a
      semantic version regex under the "docs/versioned" path of the site.
      Same nesting version behavior as `--multiple-versions`.
    - `hvrt serve --unversioned '/releases'`: serve unversioned files in the
      repo under the "releases" path of the site.
    - Should also include things like flags for `--port`, `--hostname`, and so on.
    - These can be "layered". Should it error if some paths are ambiguous? Or
      just go by a simple rule, like "What ever is specified last is the top
      layer"? I'm leaning towards the latter.
