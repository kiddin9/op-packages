# shellcheck shell=sh
#
# gitbackup -- push without a clone: gb_remote_head, gb_fetch_meta,
# gb_build_tree, gb_commit_push.
#
# `git commit-tree -p <parent>` needs the parent commit object locally or
# fails "not a valid object" -- hence gb_fetch_meta's blobless shallow fetch.
# Reads GB_URL, GB_PREFIX, GB_PARENT as resolved by the CLI. Needs lib.sh.

# gb_remote_head <branch> -- tip SHA, or nothing (rc 0) for a new branch.
# Returns 1 when ls-remote fails; mapping to exit 3 is the caller's.
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

# gb_fetch_meta <branch> <repodir> [depth] -- depth "" = full history.
# blob:none, not tree:0: trees stay so one blob can be lazily fetched by path.
# Named remote: an anonymous-URL partial fetch breaks later lazy fetches
# ("promisor remote name cannot begin with '/'").
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

# gb_build_tree <repodir> <treedir> [extra_file] [extra_gitpath] -- prints the
# tree SHA. With GB_PARENT, the parent tree is seeded and GB_PREFIX cleared:
# other devices on a shared branch survive, dropped paths disappear.
# Symlinks are hashed from the target string; hashing the path would follow
# the link and fail on dangling ones.
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

# gb_commit_push <repodir> <tree> <parent> <msgfile> <branch> -- prints the
# new SHA. Returns 1 commit-tree failed, 2 branch moved (caller retries once),
# 3 other push failure.
gb_commit_push() {
	_gb_repodir="$1"
	_gb_tree="$2"
	_gb_parent="$3"
	_gb_msgfile="$4"
	_gb_branch="$5"
	_gb_gitdir="$_gb_repodir/.git"

	# Routers have no user.name/email and commit-tree refuses to guess.
	_gb_commit=$(GIT_AUTHOR_NAME=gitbackup GIT_AUTHOR_EMAIL=gitbackup@localhost \
		GIT_COMMITTER_NAME=gitbackup GIT_COMMITTER_EMAIL=gitbackup@localhost \
		git --git-dir="$_gb_gitdir" commit-tree "$_gb_tree" ${_gb_parent:+-p "$_gb_parent"} -F "$_gb_msgfile" 2>&1)
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
