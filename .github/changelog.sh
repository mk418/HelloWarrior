#!/usr/bin/env bash
#
# Generate CHANGELOG.md for a release tag, with commit trailers filtered out.
#
# Why this exists: the BigWigs packager builds its changelog by piping the raw
# body of every commit in the tag range (`git log --pretty=format:%B`) into the
# release notes, stripping only `git-svn-id:` and revert lines. Trailers like
# Co-Authored-By therefore get published verbatim to the GitHub Release and to
# CurseForge. There is no filter for them in .pkgmeta, and the only override
# point the packager offers is `manual-changelog` -- a file it uses instead of
# generating its own. So we generate that file here, one step ahead of it.
#
# The output deliberately mirrors the packager's own format, so releases made
# before and after this script look the same. If the file is missing the
# packager just falls back to generating its own, so a failure here degrades to
# the old behaviour rather than breaking the release.
#
# Usage: changelog.sh <tag> [output-file]

set -euo pipefail

tag="${1:?usage: changelog.sh <tag> [output-file]}"
out="${2:-CHANGELOG.md}"

# Title of the changelog. Matches `package-as` in .pkgmeta, which is what the
# packager uses for its own heading.
project="HelloWarrior"
repo_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-mk418/HelloWarrior}"

# The tag before this one, if any. Its absence (first release) is not an error.
previous=$(git describe --tags --abbrev=0 "${tag}^" 2>/dev/null || true)
if [ -n "$previous" ]; then
	range="${previous}..${tag}"
	links="[Full Changelog](${repo_url}/compare/${previous}...${tag}) [Previous Releases](${repo_url}/releases)"
else
	range="$tag"
	links="[Full Changelog](${repo_url}/commits/${tag})"
fi

# UTC, matching the packager's `TZ='' printf '%(%Y-%m-%d)T'`. Without the
# override this lands a day out for any release tagged late in the evening.
date=$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y-%m-%d "$tag")

{
	echo "# ${project}"
	echo
	echo "## [${tag}](${repo_url}/tree/${tag}) (${date})"
	echo "$links"
	echo
} > "$out"

# The same transform the packager applies, plus the trailer filter. Written in
# perl rather than sed because the packager's underscore-escaping pass uses a
# GNU-only branch/label construct that BSD sed rejects, which makes it
# untestable on a Mac; perl behaves identically in both places.
git log "$range" --pretty=format:"###%B" | perl -ne '
	BEGIN {
		# Standard git trailers. Anything matching is dropped from the body;
		# the commits themselves keep them.
		$trailer = qr/^(?:Co-authored-by|Signed-off-by|Co-committed-by|Reviewed-by
		               |Acked-by|Tested-by|Helped-by|Reported-by|Suggested-by)
		               :\s/xi;
	}
	chomp;
	next if /$trailer/;

	$_ = "    " . $_;      # indent every line
	s/^ *$//;              # whitespace-only lines become empty
	s/^    ###/- /;        # commit separator becomes a list bullet
	$_ .= "  ";            # markdown hard line break

	# Escape underscores so markdown does not read them as emphasis, leaving
	# anything inside a backtick span alone.
	my ($rest, $esc) = ($_, "");
	while (length $rest) {
		if    ($rest =~ s/^(`[^`]*`)//) { $esc .= $1 }      # inline code
		elsif ($rest =~ s/^([^`_]+)//)  { $esc .= $1 }      # ordinary text
		elsif ($rest =~ s/^_//)         { $esc .= "\\_" }   # bare underscore
		else  { $rest =~ s/^(.)//; $esc .= $1 }             # unmatched backtick
	}
	$_ = $esc;

	s/\[ci skip\]//g;
	s/\[skip ci\]//g;

	next if /git-svn-id:/;
	next if /^\s*This reverts commit [0-9a-f]{40}\.\s*$/;
	next if /^\s*$/;

	print "$_\n";
' >> "$out"
