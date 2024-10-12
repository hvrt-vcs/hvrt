# Repo Data Structures

Havarti differs somewhat from git and other version control systems.
We will describe its data structures here.

General data structure notes:

- Hash algorithms are flexible in Havarti.
  For example, Havarti is not tied down to a single algorithm like git is (i.e. sha1).
  The algorithm name is, along with the digest value,
  part of the lookup key for a data type.
  This is what makes it possible to swap algorithms at any time,
  even within the same repo.
  The algorithm name is also used in the hash for parent types.
- Hash ID - a UTF-8 string of the form `<data type>:<hash algorithm>:<hex digest>`.
  This is cast to bytes to calculate for composite types like trees and commits.

## Main data types

### Commit

This is the format of a `git` commit object in a `git` repo,
as taken from this [URL](https://wyag.thb.lt/#orgfe2859f):

```gitcommit
tree 29ff16c9c14e2652b22f8b78bb08a5a07930c147
parent 206941306e8a8af65b66eaaaea388a7ae24d49a0
author Thibault Polge <thibault@thb.lt> 1527025023 +0200
committer Thibault Polge <thibault@thb.lt> 1527025044 +0200
gpgsig -----BEGIN PGP SIGNATURE-----

 iQIzBAABCAAdFiEExwXquOM8bWb4Q2zVGxM2FxoLkGQFAlsEjZQACgkQGxM2FxoL
 kGQdcBAAqPP+ln4nGDd2gETXjvOpOxLzIMEw4A9gU6CzWzm+oB8mEIKyaH0UFIPh
 rNUZ1j7/ZGFNeBDtT55LPdPIQw4KKlcf6kC8MPWP3qSu3xHqx12C5zyai2duFZUU
 wqOt9iCFCscFQYqKs3xsHI+ncQb+PGjVZA8+jPw7nrPIkeSXQV2aZb1E68wa2YIL
 3eYgTUKz34cB6tAq9YwHnZpyPx8UJCZGkshpJmgtZ3mCbtQaO17LoihnqPn4UOMr
 V75R/7FjSuPLS8NaZF4wfi52btXMSxO/u7GuoJkzJscP3p4qtwe6Rl9dc1XC8P7k
 NIbGZ5Yg5cEPcfmhgXFOhQZkD0yxcJqBUcoFpnp2vu5XJl2E5I/quIyVxUXi6O6c
 /obspcvace4wy8uO0bdVhc4nJ+Rla4InVSJaUaBeiHTW8kReSFYyMmDCzLjGIu1q
 doU61OM3Zv1ptsLu3gUE6GU27iWYj2RWN3e3HE4Sbd89IFwLXNdSuM0ifDLZk7AQ
 WBhRhipCCgZhkj9g2NEk7jRVslti1NdN5zoQLaJNqSwO1MtxTmJ15Ksk3QP6kfLB
 Q52UWybBzpaP9HEd4XnR+HuQ4k2K0ns2KgNImsNvIyFwbpMUyUWLMPimaV1DWUXo
 5SBjDB/V/W2JBFR+XKHFJeFwYhj7DD/ocsGr4ZMx/lgc8rjIBkI=
 =lgTX
 -----END PGP SIGNATURE-----

Create first draft
```

With small variations, `hvrt` could use a similar format for hashing.

Here is a possible variation for `hvrt`:

```hvrtcommit
tree sha1:29ff16c9c14e2652b22f8b78bb08a5a07930c147
parent sha1:206941306e8a8af65b66eaaaea388a7ae24d49a0 regular
author Thibault Polge <thibault@thb.lt> 1527025023 +0200
committer Thibault Polge <thibault@thb.lt> 1527025044 +0200
gpgsig -----BEGIN PGP SIGNATURE-----

 iQIzBAABCAAdFiEExwXquOM8bWb4Q2zVGxM2FxoLkGQFAlsEjZQACgkQGxM2FxoL
 kGQdcBAAqPP+ln4nGDd2gETXjvOpOxLzIMEw4A9gU6CzWzm+oB8mEIKyaH0UFIPh
 rNUZ1j7/ZGFNeBDtT55LPdPIQw4KKlcf6kC8MPWP3qSu3xHqx12C5zyai2duFZUU
 wqOt9iCFCscFQYqKs3xsHI+ncQb+PGjVZA8+jPw7nrPIkeSXQV2aZb1E68wa2YIL
 3eYgTUKz34cB6tAq9YwHnZpyPx8UJCZGkshpJmgtZ3mCbtQaO17LoihnqPn4UOMr
 V75R/7FjSuPLS8NaZF4wfi52btXMSxO/u7GuoJkzJscP3p4qtwe6Rl9dc1XC8P7k
 NIbGZ5Yg5cEPcfmhgXFOhQZkD0yxcJqBUcoFpnp2vu5XJl2E5I/quIyVxUXi6O6c
 /obspcvace4wy8uO0bdVhc4nJ+Rla4InVSJaUaBeiHTW8kReSFYyMmDCzLjGIu1q
 doU61OM3Zv1ptsLu3gUE6GU27iWYj2RWN3e3HE4Sbd89IFwLXNdSuM0ifDLZk7AQ
 WBhRhipCCgZhkj9g2NEk7jRVslti1NdN5zoQLaJNqSwO1MtxTmJ15Ksk3QP6kfLB
 Q52UWybBzpaP9HEd4XnR+HuQ4k2K0ns2KgNImsNvIyFwbpMUyUWLMPimaV1DWUXo
 5SBjDB/V/W2JBFR+XKHFJeFwYhj7DD/ocsGr4ZMx/lgc8rjIBkI=
 =lgTX
 -----END PGP SIGNATURE-----

Create first draft
```

- Differences:
  - Although part of the hash bytes,
    these same values are persisted in the DB in tables.
  - Hashes are explicitly prepended with the hash algo.
  - The parent hash is trailed by its merge type.
    - Parent commits have a type in `hvrt`,
      one of `regular`, `cherrypick`, `revert`, or `squash`.
    - `regular` means the common merge style that git does.
      - The first parent should always be `regular`.
        However, it kind of doesn't matter
        because the type of the first parent is ignored
        when it comes time to apply subsequent merge operation(s).
    - `cherrypick` uses the same algorithm described for [`git cherry-pick`](https://git-scm.com/docs/git-cherry-pick),
      except the cherrypicked commit is explicitly tracked as a parent.
    - `revert` uses the same algorithm described in [`git revert`](https://git-scm.com/docs/git-revert),
      except the reverted commit is explicitly tracked as a parent.
    - `squash` style merge parents have not been fully defined yet.
      There are two options.
      First option, it forgets/overwrites any changes
      from any preceding merge parents.
      Second option, it behaves like `git merge --squash`,
      which isn't really very different from a `regular` merge.
      The one big difference in the second style
      would be that it wouldn't show in the UI by default.
      Maybe that is enough.
      Perhaps this second style should be renamed `silent` or something.
      I don't know.
      Requires more thought.
      - In the case of the first behavior described above,
        havarti will automatically elide
        the preceding merge parents between the initial parent and the `squash` parent.
        - The user can disable eliding
          if they care to record all parents for some reason.
          In this circumstance, the user will need to deal with any merge conflicts
          in intermediate merges
          even though the resolved changes will get thrown away
          once the `squash` parent is applied.
          - I don't know.
            Maybe this shouldn't be allowed.
            It is kind of silly.
            What value does it have?
            Maybe there can just be a flag to fail if this eliding would happen.
    - "But what about rebase?" you say.
      [Rebasing is just a series of `cherrypick` operations 🍒](https://stackoverflow.com/a/11837630/1733321).
    - In any UI, only `regular` merges are shown by default.
      This is to keep the UI uncluttered,
      like in git.
      However, if the user explicitly requests,
      merges of types other than `regular` can display.
      This is the main advantage over git:
      all merge style operations are tracked,
      but not all are shown by default.
      This is usually the reason given to delete history in git:
      "It clutters the history to do true merges. We just rebase and/or squash everything."
      With Havarti you can have your cake and eat it too: clean looking history
      *and* all the data to know where things originally came from.
    - It should be noted
      that all the forgetful git style operations can still be done in Havarti.
      You just have an alternative to those as well,
      Hopefully one you will choose.

### Tree

R list of paths, file ids, and blob ids. Paths cannot/should not be
repeated within the same tree. Blobs are just file contents, so those can be
repeated if file contents match. A tree hash is calculated by hashing the
path, file id, and blob id for each entry divided by a newline character (i.e.
`\n`). The values in each line are delimited by tab characters (i.e. `\t`).

- Should these be sorted or something? What is the ordering here?

### File id

<!--
FIXME: File ID is no longer a thing.
Remove this section and clarify.
Renames and copies are just tracked in commits by pointing to tree ids.
This also makes it possible to copy entire trees with a single directive.
-->

Reference to give provenance to paths; another way to say this is: a
file id tracks its parents file ids which allows us to explicitly know about
copies and renames.

### Blob

The raw binary data within a file.
Havarti doesn't care about file contents.
If blobs differ at the byte level, they are different blobs.
Blobs are referred to by their hash value, since this should not clash.

### Chunk

A chunk is a part of a blob.
This is mostly an implementation detail
to overcome the fact that most SQL DBs (including SQLite and PostgreSQL)
have limits on the size of a binary blob row type.
Although this limit is large (several GiB at the extreme end),
this still isn't ideal
as blobs cannot be streamed from the databases without some trickery.
By dividing blob data into chunks,
we can use nearly identical logic on all DBs
and overcome the streaming limitation of SQL DBs by taking small chunks at a time.

- Within a SQL DB, a blob is a list of ordered chunks.
  Thus, it is possible
  for chunks to be shared across multiple blobs.
- Is it worth making chunks a canonical part of the hash calculation and merkle tree?
  This may create a weird situation where blob contents may match,
  but their hashes differ because they were chunked differently at different times.
  Perhaps there is a way to do this
  that isn't merely hashing chunk references to generate the blob hash.

### Annotation

Annotations make modifications to commits after the initial commit.
They are included in hash calculations for the current commit,
but do not change previous commit hash calculations,
thus they are non destructive in nature.
They can change header data, not blob or tree data.
One can think of annotations as non-destructively layering new headers
on top of old headers.
For example, if a commit authorship was incorrectly attributed to a dev,
an annotation could layer this change on top of the original commit
without destroying the original author data
that goes into checking merkle tree integrity.

- Open question: which annotation "wins" in a merge situation with annotations
  in both branches?
  - Probably the one from the commit with the latest timestamp.

### Hash ID

A UTF-8 string of the form `<data type>:<hash algorithm>:<hex digest>`.
This is cast to bytes to calculate for composite types like trees.
