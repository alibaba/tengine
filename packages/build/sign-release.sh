#!/bin/sh
#
# GPG signing for the release artifacts.
#
#     packages/build/sign-release.sh rpms   <dir>        sign every rpm in dir
#     packages/build/sign-release.sh detach <file>...    write <file>.asc
#     packages/build/sign-release.sh pubkey <file>       export the public key
#
# The private key comes from the environment, never from a file in the tree:
#
#     GPG_PRIVATE_KEY   ASCII-armoured private key       (required)
#     GPG_PASSPHRASE    passphrase for that key          (optional)
#     GPG_KEY_ID        which key to use, if the keyring holds several
#
# WITHOUT GPG_PRIVATE_KEY EVERY SUBCOMMAND IS A NO-OP that exits 0 after saying
# so. A fork building its own packages has no access to the release key and
# must not fail because of it -- the packages are simply unsigned, exactly as
# they were before signing existed.
#
# Why each format is treated differently:
#
#   * rpm carries the signature inside the package header, so `rpmsign
#     --addsign` rewrites the file. It has to run BEFORE any checksum is taken.
#   * deb has no equivalent in current practice: dpkg-sig is deprecated and
#     Debian's trust model signs the repository's Release file, which needs a
#     repository. Until there is one, the checksum signature below is the only
#     thing covering the deb packages.
#   * apk is signed during the build by abuild with its own RSA key, not GPG --
#     see TENGINE_APK_PRIVKEY in build.sh.
#

set -eu

die() { printf '%s: error: %s\n' "${0##*/}" "$*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

[ $# -ge 1 ] || die "no subcommand; see --help"
case "$1" in
    -h|--help) sed -n '3,/^$/p' "$0" | sed -e 's/^#\{1,2\} \{0,1\}//'; exit 0 ;;
esac
cmd=$1
shift

if [ -z "${GPG_PRIVATE_KEY:-}" ]; then
    info "GPG_PRIVATE_KEY is not set; skipping $cmd (artifacts stay unsigned)"
    exit 0
fi

command -v gpg >/dev/null || die "gpg not found"

# A private GNUPGHOME per run: the default one may be shared with whatever else
# the runner does, and the key must not outlive this process.
GNUPGHOME=$(mktemp -d)
export GNUPGHOME
chmod 700 "$GNUPGHOME"
cleanup() { rm -rf "$GNUPGHOME"; }
trap cleanup EXIT INT TERM

printf '%s\n' "$GPG_PRIVATE_KEY" | gpg --batch --quiet --import \
    || die "cannot import GPG_PRIVATE_KEY"

# Resolve the key to sign with. With GPG_KEY_ID the caller has already decided;
# otherwise take the first secret key in the fresh keyring, which is the one
# just imported.
if [ -n "${GPG_KEY_ID:-}" ]; then
    key_id=$GPG_KEY_ID
else
    key_id=$(gpg --batch --list-secret-keys --with-colons \
        | awk -F: '$1 == "sec" { print $5; exit }')
    [ -n "$key_id" ] || die "no secret key in the imported material"
fi
info "signing as $key_id"

# --pinentry-mode loopback is what lets a passphrase be supplied without a tty.
# The passphrase reaches gpg through a file rather than the command line, which
# would be visible in the process list.
pass_args=""
if [ -n "${GPG_PASSPHRASE:-}" ]; then
    pass_file="$GNUPGHOME/pp"
    printf '%s' "$GPG_PASSPHRASE" > "$pass_file"
    chmod 600 "$pass_file"
    pass_args="--pinentry-mode loopback --passphrase-file $pass_file"
fi

case "$cmd" in
    rpms)
        [ $# -eq 1 ] || die "rpms takes exactly one directory"
        dir=$1
        [ -d "$dir" ] || die "$dir does not exist"
        command -v rpmsign >/dev/null || die "rpmsign not found (install rpm)"

        # rpm shells out to gpg through this template. Spelling it out is what
        # allows the loopback pinentry above; the stock template assumes an
        # interactive agent.
        sign_cmd="%{__gpg} gpg --batch --no-verbose --no-armor $pass_args \
-u %{_gpg_name} -sbo %{__signature_filename} %{__plaintext_filename}"

        # The list goes through a file rather than a pipe so the counter below
        # survives -- a `find | while` puts the loop in a subshell. It lands in
        # GNUPGHOME only to be swept up by the same trap.
        count=0
        find "$dir" -name '*.rpm' -print > "$GNUPGHOME/rpms"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            rpmsign --addsign \
                --define "_gpg_name $key_id" \
                --define "__gpg_sign_cmd $sign_cmd" \
                "$f" >/dev/null
            count=$((count + 1))
        done < "$GNUPGHOME/rpms"
        info "signed $count rpm packages in $dir"
        ;;

    detach)
        [ $# -ge 1 ] || die "detach takes at least one file"
        for f in "$@"; do
            [ -f "$f" ] || die "$f does not exist"
            rm -f "$f.asc"
            # shellcheck disable=SC2086 # pass_args is deliberately word-split
            gpg --batch --quiet --yes $pass_args \
                --local-user "$key_id" \
                --armor --detach-sign --output "$f.asc" "$f" \
                || die "cannot sign $f"
            info "wrote $f.asc"
        done
        ;;

    pubkey)
        [ $# -eq 1 ] || die "pubkey takes exactly one output file"
        gpg --batch --quiet --armor --export "$key_id" > "$1" \
            || die "cannot export the public key"
        [ -s "$1" ] || die "exported public key is empty"
        info "wrote $1"
        ;;

    *)
        die "unknown subcommand '$cmd'; expected rpms|detach|pubkey"
        ;;
esac
