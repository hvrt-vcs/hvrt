# Squash

## Reasoning

I would prefer to implement a safer version of squash for Havarti.
I have a few ways to approach this,
but I think only one really makes sense at this point.

## Solutions

### Solution #1

Create a new merge type named `squash`.
Up to now, the merge types are `regular`, `cherrypick`, and `revert`.
With the addition of `squash`,
I think this may round out the needed types.
With `squash` merges, all previous merges are ignored for merge conflicts.
In git parlance, it is like choosing `theirs` as a merge strategy.

Why have all the different merge types?
The idea is that by flagging the type,
it should be trivial to detect if a merge conflict happened.
The type will tell us *how* the merge should be applied.
For example, a revert merge is completely different than a regular merge.
By applying the merge strategy again,
we can know whether a conflict happened.
If it did and it doesn't match the data in the merge commit,
we can know that manual intervention happened.
Also, if it merges without a conflict,
but the merge commit is different than that result,
we can know that the user made additional edits before committing all changes.

In other words, we get a lot more information from our commits
by encoding how the commits were merged together.
It is more than simple metadata.

Now back to squashes.
A squash basically just,
as the name implies,
"squashes" the previous commit(s) by pretty much forgetting them.
Remember, in git each commit is just a snapshot of the state of the files.
Havarti will do the same, but with one important addition:
copies and renames must be tracked.
Thus the history must be traversed to add these to the squash.
Well, it would need to be traversed for an "unsafe" (i.e. history forgetful) squash.
However, for a safe squash, it will just have a squash merge commit
and the UI (CLI or GUI) should by default not show the squash branch.
It should require an explicit request of the UI to show this.
However, the copies and renames can still be retrieved via traversal of
the commit tree.

I'm still not sure about this approach.
I'll need to keep thinking on it.
