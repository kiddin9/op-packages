# shellcheck shell=sh
#
# gitbackup -- push without a clone (spec "Как коммит попадает в
# репозиторий без клона (G05, G06)"). This is the trick the whole package
# exists to prove: `git commit-tree` only ever needs the PARENT COMMIT
# object to exist in the local object database -- never its tree, never
# its blobs.
#
# Ticket 07's own V10 check (done before any of this was written, both
# against this repo's git 2.51 on the dev host and consistent with git
# 2.50.1 on the owlab 25.12.4 stand): a parent SHA that is not in the local
# object database AT ALL makes `commit-tree -p <sha>` hard-fail with
# "fatal: <sha> is not a valid object" -- so fetching that one commit
# object (gb_fetch_meta below) is mandatory, not an optional optimization.
# Once just the commit object exists locally, `commit-tree` happily builds
# a new tree/commit on top of it, and `git push` negotiates and sends only
# the objects the far end is actually missing -- proven with a single
# hand-copied commit object and zero blobs, `git fsck --full` clean on the
# receiving bare repository afterward.
#
# Every function here reads GB_URL from the environment rather than taking
# it as an argument -- the same convention visibility.sh/auth.sh use for
# config context the CLI already resolved once (gb_validate_config) -- so a
# caller only ever names what actually varies per call: a branch, a tree, a
# directory. gb_build_tree additionally reads GB_PREFIX and GB_PARENT this
# same way (see its own comment) for the same reason.
#
# Sourced, never executed: nothing here runs at load time. Depends on
# lib.sh (gb_log) already being sourced by the caller, same convention as
# every other module in this directory.

# gb_remote_head <branch>
#
# Prints <branch>'s current tip SHA on GB_URL and returns 0; prints nothing
# and returns 0 when the branch does not exist yet (a device's first ever
# backup) -- verified live: `git ls-remote <a-reachable-repo>
# refs/heads/<no-such-branch>` exits 0 with empty output, not an error, as
# long as the repository itself was reachable. Prints nothing and returns 1
# when `git ls-remote` itself failed (network unreachable, host key
# refused, authentication rejected -- git folds all of these into one
# nonzero exit and a "fatal: ..." message); turning that into the shared
# exit-3 (network/auth) contract is the caller's job, not this module's,
# same division of responsibility gb_visibility_ok's 0/3/4 already uses.
gb_remote_head() {
	_gb_branch="$1"
	_gb_out=$(git ls-remote "${GB_URL:?gb_remote_head: GB_URL is not set}" \
		"refs/heads/$_gb_branch" 2>&1)
	_gb_rc=$?
	if [ "$_gb_rc" -ne 0 ]; then
		gb_log err "gb_remote_head: git ls-remote $GB_URL refs/heads/$_gb_branch failed: $_gb_out"
		return 1
	fi
	printf '%s\n' "$_gb_out" | awk 'NR==1 {print $1}'
	return 0
}

# gb_fetch_meta <branch> <repodir> [depth]
#
# Prepares <repodir> as a scratch, non-bare git repository (created empty
# the first time; reused as-is on a retry, spec step 14) and fetches only
# <branch>'s tip -- commit and trees, never blobs, when the remote
# understands partial clone (`--filter=blob:none`).
#
# <depth> defaults to 1 -- this function's original, and still by far its
# most common, shape: `run`'s own "just the tip" need, every call site in
# usr/sbin/gitbackup. An explicit empty string ("") skips `--depth`
# entirely and fetches the branch's whole history instead, which is what
# restore.sh needs to reach an arbitrary past commit (ticket 18: this
# parameter is what let restore.sh's own near-identical
# init/remote-add/fetch sequence for exactly that one case go away, instead
# of staying a second, hand-maintained copy of this same function that
# differed from it only in this one flag).
#
# Not `--filter=tree:0`, even though that measures smaller in the spec's
# own table (12 KiB flat vs. 644 KiB for openwrt/luci -- "Проверенные
# факты 25.12.4"): the very next thing usr/sbin/gitbackup's run does with
# this fetch is read one specific blob out of it (the old manifest.json,
# for the unchanged-since-last-time comparison), and `blob:none` leaves
# every tree in place so that blob can be fetched lazily by path -- a
# `git cat-file -p <parent>:<prefix>/manifest.json` -- instead of a second,
# bespoke transfer. Confirmed live (this repo's own git, promisor remote
# behavior): after a `--filter=blob:none` fetch against a repository with
# `uploadpack.allowFilter` on, the fetched pack carries zero blobs, and the
# very next `cat-file -p <path>` transparently pulls in exactly the one
# blob asked for and no more (object count went from 8 with blobs already
# present to a lazy on-demand fetch of 1 when they were not).
#
# A remote that does not support the filter extension at all -- confirmed
# live against a plain local-path remote, which never speaks the partial-
# clone protocol extension regardless of git version -- degrades on its
# own to an ordinary `--depth=1` (git's own message: "warning: filtering
# not recognized by server, ignoring"). Either way this is still only
# <branch>'s single tip commit, on this device's own branch -- never
# history, never another device's branch -- so "no clone, ever" holds
# regardless of what the remote can do.
#
# Fetched through a NAMED remote ("origin"), configured once and reused on
# the one retry spec step 14 allows, rather than the anonymous-URL form
# (`git fetch <url> <branch>`) gb_remote_head/gb_commit_push use -- an
# anonymous partial-clone fetch turned out to leave the resulting promisor
# pack in a state where a LATER operation needing one of its still-missing
# objects could not resolve where to lazily fetch it from again (confirmed
# live: an anonymous fetch's own "remote" bookkeeping is the URL string
# itself, which git's shorthand-remote-name rule rejects outright for a
# plain filesystem path -- "warning: promisor remote name cannot begin
# with '/'" -- and the lazy re-fetch a later `write-tree` needs then fails
# outright, not just warns). A named remote sidesteps this by construction
# and is not a behavior change for a real https/ssh URL, which was never
# affected by the rejected-shorthand rule to begin with.
#
# Returns 0 on success; 1 if the repository could not be initialized or the
# fetch itself failed (network/auth -- again the caller's exit-3 to assign,
# same convention as gb_remote_head).
gb_fetch_meta() {
	_gb_branch="$1"
	_gb_repodir="$2"
	_gb_depth="${3-1}"

	if [ ! -d "$_gb_repodir/.git" ]; then
		git init -q "$_gb_repodir" 2>/dev/null ||
			{ gb_log err "gb_fetch_meta: git init $_gb_repodir failed"; return 1; }
	fi

	git --git-dir="$_gb_repodir/.git" remote get-url origin >/dev/null 2>&1 ||
		git --git-dir="$_gb_repodir/.git" remote add origin \
			"${GB_URL:?gb_fetch_meta: GB_URL is not set}" 2>/dev/null

	_gb_depth_opt=''
	[ -n "$_gb_depth" ] && _gb_depth_opt="--depth=$_gb_depth"
	# shellcheck disable=SC2086  # intentional: expands to zero or exactly one token, never unquoted user input
	_gb_out=$(git --git-dir="$_gb_repodir/.git" fetch $_gb_depth_opt --filter=blob:none \
		origin "$_gb_branch" 2>&1)
	_gb_rc=$?
	if [ "$_gb_rc" -ne 0 ]; then
		gb_log err "gb_fetch_meta: git fetch $GB_URL $_gb_branch failed: $_gb_out"
		return 1
	fi
	return 0
}

# gb_build_tree <repodir> <treedir> [extra_file] [extra_gitpath]
#
# Hashes and stages every regular file and symlink under <treedir> into a
# scratch index, rooted at GB_PREFIX (environment, not an argument -- see
# this file's header), writes a tree object from that index into <repodir>
# and prints its SHA on stdout. <treedir> holds this run's own collected
# backup set (collect.sh's outdir) with no prefix baked into it on disk --
# the prefix only ever exists inside the git tree this function builds, not
# on the filesystem gb_collect wrote to.
#
# [extra_file]/[extra_gitpath] (ticket 22) stage exactly one additional
# regular file at a git path given VERBATIM, bypassing GB_PREFIX entirely --
# the one thing usr/sbin/gitbackup needs this for is a device branch's own
# README.md, which has to sit at the BRANCH ROOT (a sibling of
# "devices/<id>") for GitHub to render it when a human opens that branch
# from a phone; a copy staged under GB_PREFIX would never be seen there.
# Both empty (the two-argument form every other call site, including every
# existing test, still uses) skips this step entirely -- behavior is
# unchanged. Mode is always 100644: nothing that calls this today needs an
# executable or a symlink at the extra path.
#
# When GB_PARENT (also environment: the SHA gb_remote_head returned, empty
# for a brand-new branch) is set, the index is first seeded from that
# commit's FULL tree (`git read-tree`), and GB_PREFIX's own old subtree is
# then cleared (`git rm --cached`) before <treedir>'s fresh content is
# staged over it. This is what spec step 11 calls out for a branch shared
# by several devices (gitbackup.origin.branch with no `{device}`):
# everything outside GB_PREFIX survives untouched, and its blobs are never
# fetched -- gb_fetch_meta only ever asked for trees, and read-tree alone
# needs no blobs either, confirmed live. Clearing GB_PREFIX before restaging
# it (rather than only adding paths <treedir> happens to still have) is
# what makes a path this device stopped backing up actually disappear from
# the pushed tree instead of lingering forever; on the shipped default (a
# branch of "device/{device}" per device) GB_PARENT's tree only ever
# contained this same GB_PREFIX to begin with, so the clear+restage is a
# no-op in effect there, not a special case this function has to detect.
#
# Only three modes ever reach the index -- git stores no others: 100644,
# 100755 (an executable regular file, `[ -x ]`), 120000 (symlink). A
# symlink's blob is hashed from the raw target STRING via --stdin, never
# from the path: `git hash-object <symlink-path>` opens the path and so
# follows the link, and fails outright ("could not open ... No such file or
# directory") for the dangling symlinks this backup set is full of
# (/etc/resolv.conf and friends) -- confirmed live, and confirmed live that
# `printf '%s' <target> | git hash-object --stdin` reproduces exactly the
# blob SHA `git add` itself would have stored for that same symlink.
#
# Returns 0 and prints the tree SHA on success; 1 (nothing printed) if any
# git plumbing step failed.
gb_build_tree() {
	_gb_repodir="$1"
	_gb_treedir="$2"
	_gb_extra_file="${3:-}"
	_gb_extra_gitpath="${4:-}"
	_gb_prefix="${GB_PREFIX:?gb_build_tree: GB_PREFIX is not set}"
	_gb_gitdir="$_gb_repodir/.git"
	_gb_idx="$_gb_repodir/gitio-index.$$"
	rm -f "$_gb_idx"

	if [ -n "${GB_PARENT:-}" ]; then
		GIT_DIR="$_gb_gitdir" GIT_INDEX_FILE="$_gb_idx" git read-tree "$GB_PARENT" 2>/dev/null || {
			gb_log err "gb_build_tree: git read-tree $GB_PARENT failed"
			rm -f "$_gb_idx"
			return 1
		}
		GIT_DIR="$_gb_gitdir" GIT_INDEX_FILE="$_gb_idx" \
			git rm -r --cached --ignore-unmatch -q -- "$_gb_prefix" >/dev/null 2>&1
	fi

	# The loop body runs on the read side of a pipe (a subshell, POSIX sh) --
	# same technique collect.sh's own _gb_collect_files relies on -- but
	# every git call inside it addresses $_gb_idx as a real file via
	# GIT_INDEX_FILE, which survives the subshell boundary; only a shell
	# variable set in there would not.
	( cd "$_gb_treedir" && find . \( -type f -o -type l \) ) | while IFS= read -r _gb_rel; do
		_gb_rel="${_gb_rel#./}"
		_gb_full="$_gb_treedir/$_gb_rel"
		_gb_gitpath="$_gb_prefix/$_gb_rel"

		if [ -L "$_gb_full" ]; then
			_gb_target=$(readlink "$_gb_full") || continue
			_gb_oid=$(printf '%s' "$_gb_target" | GIT_DIR="$_gb_gitdir" git hash-object -w --stdin) || continue
			_gb_mode=120000
		else
			_gb_oid=$(GIT_DIR="$_gb_gitdir" git hash-object -w "$_gb_full") || continue
			if [ -x "$_gb_full" ]; then _gb_mode=100755; else _gb_mode=100644; fi
		fi

		GIT_DIR="$_gb_gitdir" GIT_INDEX_FILE="$_gb_idx" \
			git update-index --add --cacheinfo "$_gb_mode,$_gb_oid,$_gb_gitpath" 2>/dev/null
	done

	if [ -n "$_gb_extra_file" ] && [ -n "$_gb_extra_gitpath" ] && [ -f "$_gb_extra_file" ]; then
		_gb_extra_oid=$(GIT_DIR="$_gb_gitdir" git hash-object -w "$_gb_extra_file" 2>/dev/null)
		if [ -n "$_gb_extra_oid" ]; then
			GIT_DIR="$_gb_gitdir" GIT_INDEX_FILE="$_gb_idx" \
				git update-index --add --cacheinfo "100644,$_gb_extra_oid,$_gb_extra_gitpath" 2>/dev/null
		fi
	fi

	_gb_tree=$(GIT_DIR="$_gb_gitdir" GIT_INDEX_FILE="$_gb_idx" git write-tree 2>/dev/null)
	_gb_rc=$?
	rm -f "$_gb_idx"
	if [ "$_gb_rc" -ne 0 ] || [ -z "$_gb_tree" ]; then
		gb_log err 'gb_build_tree: git write-tree failed'
		return 1
	fi
	printf '%s\n' "$_gb_tree"
	return 0
}

# gb_commit_push <repodir> <tree> <parent> <msgfile> <branch>
#
# Creates one commit from <tree> and <msgfile> -- parented on <parent>, or
# a root commit when <parent> is empty (a brand-new branch) -- and pushes
# it straight to <branch> on GB_URL: `git push <sha>:refs/heads/<branch>`,
# which is what lets git figure out and send only the objects the remote
# does not already have, without this side ever holding a checkout of
# anything (spec step 12/13).
#
# Prints the new commit's SHA on stdout and returns 0 on success. On
# failure prints nothing and returns:
#   1  `commit-tree` itself failed (a bad tree/parent SHA -- a bug on this
#      side, not a remote problem)
#   2  the push was rejected because the branch moved (spec step 14:
#      "Отказ non-fast-forward -> повтор с шага 8 один раз, дальше exit 1").
#      Matched against git's own literal wording for BOTH of the two ways
#      it phrases this same situation -- confirmed live, forcing the race
#      two different ways: "(non-fast-forward)" when the branch diverged
#      from a history this side never fetched, "(fetch first)" when this
#      side's own remote-tracking view is simply stale (the far more
#      common shape in practice: this side fetched the parent once, then
#      someone else pushed before this side's own push landed). Both are
#      "the branch moved under us, re-fetch and retry" to this package.
#      The caller owns the one retry; this function only reports which
#      kind of failure happened.
#   3  any other push failure (auth rejected, network gone mid-run) -- the
#      caller's exit 3, same convention as gb_remote_head/gb_fetch_meta.
gb_commit_push() {
	_gb_repodir="$1"
	_gb_tree="$2"
	_gb_parent="$3"
	_gb_msgfile="$4"
	_gb_branch="$5"
	_gb_gitdir="$_gb_repodir/.git"

	# GIT_AUTHOR_*/GIT_COMMITTER_* set explicitly, not left to git's own
	# fallback chain (user.name/user.email, then a guessed
	# username@hostname): found live on the owlab stand -- a freshly
	# booted router has no ~/.gitconfig and no [user] section anywhere,
	# and commit-tree refuses outright ("Author identity unknown ...
	# Please tell me who you are") rather than guess. A dev machine's own
	# global gitconfig had been masking this in every host-side test up to
	# that point. One fixed bot identity for every device's every commit --
	# the commit body's own Device: field is what actually identifies
	# which router pushed it, this is not trying to be a person.
	if [ -n "$_gb_parent" ]; then
		_gb_commit=$(GIT_AUTHOR_NAME=gitbackup GIT_AUTHOR_EMAIL=gitbackup@localhost \
			GIT_COMMITTER_NAME=gitbackup GIT_COMMITTER_EMAIL=gitbackup@localhost \
			git --git-dir="$_gb_gitdir" commit-tree "$_gb_tree" -p "$_gb_parent" -F "$_gb_msgfile" 2>&1)
	else
		_gb_commit=$(GIT_AUTHOR_NAME=gitbackup GIT_AUTHOR_EMAIL=gitbackup@localhost \
			GIT_COMMITTER_NAME=gitbackup GIT_COMMITTER_EMAIL=gitbackup@localhost \
			git --git-dir="$_gb_gitdir" commit-tree "$_gb_tree" -F "$_gb_msgfile" 2>&1)
	fi
	_gb_rc=$?
	if [ "$_gb_rc" -ne 0 ]; then
		gb_log err "gb_commit_push: commit-tree failed: $_gb_commit"
		return 1
	fi

	_gb_push_out=$(git --git-dir="$_gb_gitdir" push "${GB_URL:?gb_commit_push: GB_URL is not set}" \
		"$_gb_commit:refs/heads/$_gb_branch" 2>&1)
	_gb_rc=$?
	if [ "$_gb_rc" -eq 0 ]; then
		printf '%s\n' "$_gb_commit"
		return 0
	fi

	case "$_gb_push_out" in
		*'non-fast-forward'* | *'fetch first'*)
			gb_log notice "gb_commit_push: $_gb_branch was rejected, the branch moved: $_gb_push_out"
			return 2
			;;
		*)
			gb_log err "gb_commit_push: push to $_gb_branch on $GB_URL failed: $_gb_push_out"
			return 3
			;;
	esac
}
