# Havarti

[![Build](https://github.com/hvrt-vcs/hvrt/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/hvrt-vcs/hvrt/actions/workflows/build.yml)
[![Test](https://github.com/hvrt-vcs/hvrt/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/hvrt-vcs/hvrt/actions/workflows/test.yml)
[![codecov](https://codecov.io/github/hvrt-vcs/hvrt/branch/master/graph/badge.svg?token=37ZZ9RJUUY)](https://codecov.io/github/hvrt-vcs/hvrt)

The primary repo for this project is currently hosted on
[Github](https://github.com/hvrt-vcs/hvrt). Issues and pull requests can be
created there.

### WIP:

I have opened up havarti publicly in an incomplete, non-working state.
I am starting a new job and thought it best to avoid any potential conficts
of interest by allowing this work to be done out in the open. Consequently,
Havarti will have lots of rough edges for a while, and I apologize. You are
welcome to contribute to get it to a usable state if Havarti's goals align
with your own.

## What do you do when you take a snapshot? You say "Cheese!"

#### Havarti is a Hybrid VCS that works both distributed and/or centralized.

`git` is (as of this writing) the reigning champion of version control systems.
It was originally created to meet the needs of the
completely distributed development model of the Linux kernel. It is a hairy
problem to tackle, and it accomplishes the goal admirably. However, the projects I
work on, both professionally and personally, are not like the Linux kernel, and although `git` comes close to
meeting my needs and preferences, it isn't exactly what I want. I've looked into
others VCS tools like `hg`, `fossil`, and `svn`, and these do not completely match what
I'm looking for either. So I started work on Havarti. It is my own small VCS to
meet my preferences and needs (I don't expect it to become widely used like
`git`) . If other people find it useful, great! However, if I'm the only one who
ever uses it, that's ok too; I'd still develop it anyway, just for personal
experience if nothing else.

When you [disemvowel](https://en.m.wiktionary.org/wiki/disemvowel) the word Havarti, you are left with `hvrt` (the name of
the tool). We could probably treat it as an acronym, like "**H**ybrid **V**CS
\<something\> \<something\>". Let me know if you think of something clever for
the last two letters. Regardless, read below to learn some of Havarti's
features/goals, roughly in order of priority:

* Track explicit file renames _and_ file copies.
* Multi-parent file copying (for merging multiple files into one file).
* Single binary, easy to install with no external dependencies.
* Cross platform (Windows, Mac, Linux, and more)
* Backed by a single SQLite database file; adding support for other SQL DBs should be straighforward.
* Handle files of nearly any size.
* [WIP] Safe (i.e. history preserving) alternatives to Git style rebase, squash,
  and cherry-pick.
* [WIP] Discourages, but allows, unsafe (i.e. forgetful) Git style rebase, squash,
  and cherry-pick.
* [WIP] Run either distributed or centralized or a combination of the two. Features below make this possible.
* [WIP] Sparse cloning (i.e. retrieve only metadata without file data, and grab file data lazily
  from an external source/upstream, which works well with large centralized monorepos).
* [WIP] Narrow cloning (i.e. retrieve/checkout only parts of a source tree
  which is also good for large monorepos).
* [WIP] Shallow cloning to make local repos even smaller (historical
  commits, both data and metadata, can be retrieved from upstream only when
  needed).

Here is quick comparison of Havarti to Git, Fossil, Mercurial, and Subversion.
Havarti's features were chosen primarily because they matter to me. Maybe you
value similar features:

| Feature                                     | Havarti | Git | Fossil | Mercurial | Subversion |
|:--------------------------------------------|:--------|:----|:-------|:----------|:-----------|
| **Explicit File Renames**                   | ✔️      | ❌¹  | ❔      | ✔️        | ✔️         |
| **Explicit File Copies**                    | ✔️      | ❌¹  | ❔      | ✔️        | ✔️         |
| **Single Binary**                           | ✔️      | ❌   | ✔️     | ❌         | ❌          |
| **Native Cross Platform**                   | ✔️      | ❕²  | ✔️     | ✔️        | ✔️         |
| **Commit offline (i.e. distributed)**       | ✔️      | ✔️  | ✔️     | ✔️        | ❌          |
| **Centralized model**                       | ✔️      | ❕³  | ❌      | ❕⁴        | ✔️         |
| **Autosync with upstream (configurable)**   | ✔️      | ❌   | ✔️     | ❌         | ✔️⁵        |
| [**Shallow clone**][7]⁷                     | ✔️      | ✔️  | ❔      | ✔️        | ✔️⁵        |
| [**Partial clone**][7]⁷                     | ✔️      | ✔️  | ❌      | ❌⁴        | ✔️⁵        |
| **Narrow clone/checkout**                   | ✔️      | ❌   | ❌      | ❌⁴        | ✔️⁵        |
| **Any file size**                           | ✔️      | ✔️  | ❌      | ✔️        | ✔️         |
| **History rewriting abilities** ⁶           | ✔️      | ✔️  | ❌      | ✔️        | ❌          |
| **Discourage unsafe operations** ⁶          | ✔️      | ❌   | ✔️     | ❌         | ✔️⁵        |
| **Serve content as static website**         | ✔️      | ❌   | ✔️     | ❌         | ❌          |
| **Bidirectional bridge to git**             | ❌       | ✔️  | ❌      | ✔️        | ✔️         |
| **Local webapp issue tracker, forum, etc.** | ❌       | ❌   | ✔️     | ❌         | ❌          |

#### Footnotes:

1. Lazily calculated heuristically from tree snapshots. Can be wrong depending
  on CLI flags passed to `git blame` and/or amount of file changes between commits.
2. Windows support via a Posix compatibility layer. Comes bundled with many indirect dependency programs like `bash`, `perl`, and `curl`.
3. Via shallow clones, partial clones, and extensions.
4. Via extensions.
5. All centralized VCS tools have this behavior by design.
6. Havarti doesn't arbitrarily handicap users. But it doesn't encourage them to do unsafe things either.
7. https://github.blog/2020-12-21-get-up-to-speed-with-partial-clone-and-shallow-clone/

[7]: https://github.blog/2020-12-21-get-up-to-speed-with-partial-clone-and-shallow-clone/
