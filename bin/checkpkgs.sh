#!/bin/bash
#
# v1.9.4 by Ricardo Branco
#
# This script validates a mirror of Debian/Ubuntu packages
#
# Public Domain
#

# Exit on error
set -e

#
# Validate arguments
#
if [ $# -ne 1 ] ; then
	echo "Usage: ${0##*/} MIRROR" >&2
	exit 1
fi

MIRROR=$(readlink -f "$1")
cd "$MIRROR"

hashes=$(mktemp)
trap "/bin/rm -f $hashes $hashes.sha1 $hashes.sha256" ERR HUP INT QUIT TERM EXIT

#
# Detect web proxy on the local network
#
detect_proxy ()
{
	local proxy_server proxy_user proxy_pass

	# Use WPAD protocol to detect web proxy
	proxy_server=$(wget --timeout=3 -q -O- http://wpad/wpad.dat | sed -ne 's/.*PROXY \(.*\)";.*$/\1/p')

	[ -z "$proxy_server" ] && return

	# Ask for Proxy username & password
	read -p 'Proxy Username: ' proxy_user
	read -s -p 'Proxy Password: ' proxy_pass
	echo > /dev/tty

	# Construct environment variables
	http_proxy="http://${proxy_user}:${proxy_pass}@${proxy_server}/"
	https_proxy="https://${proxy_user}:${proxy_pass}@${proxy_server}/"
	export http_proxy https_proxy

	# Wget proxy options
	PROXY_OPTIONS="-e use_proxy=on"
}

#
# Download public keys
#
download_pubkeys ()
{
	# Add FAI fingerprint
	fingerprints=("B11EE3273F6B2DEB528C93DA2BF8D9FE074BCDE4")

	echo
	echo "CHECKPKGS: Trying to detect a web proxy in the local network..."
	echo
	detect_proxy
	echo
	echo "CHECKPKGS: Downloading public keys..."
	echo

	# Add Docker fingerprint
	[ -d "$MIRROR/download.docker.com/" ] && \
		fingerprints+=("9DC858229FC7DD38854AE2D88D81803C0EBFCD88")

	# Add Google fingerprints
	if [ -d "$MIRROR/dl.google.com/linux/chrome" ] ; then
		fingerprints+=("4CCA1EAF950CEE4AB83976DCA040830F7FAC5991")
		fingerprints+=("EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796")
	fi

	# Add ppa:webupd8team/java fingerprint
	[ -d "$MIRROR/ppa.launchpad.net/webupd8team/java" ] && \
		fingerprints+=("7B2C3B0889BF5709A105D03AC2518248EEA14886")

	# Add MongoDB repo fingerprint
	[ -d "$MIRROR/repo.mongodb.org/" ] && \
		fingerprints+=("42F3E95A2C4F08279C4960ADD68FA50FEA312927")

	for fingerprint in ${fingerprints[@]} ; do
		gpg --no-default-keyring --keyring trustedkeys.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $fingerprint
	done

	# Install Debian & Ubuntu keyrings
	for os in debian ubuntu ; do
		# XXX: ubuntu-archive-keyring is not available on Debian 7
		gpg --keyring /usr/share/keyrings/$os-archive-keyring.gpg --export | \
			gpg --no-default-keyring --keyring trustedkeys.gpg --import
	done

	# Import already installed keys
	apt-key exportall | gpg --no-default-keyring --keyring trustedkeys.gpg --import

	unset http_proxy https_proxy
}

#
# Check Release files with their respective Release.gpg and InRelease files (GPG signed)
#
check_release ()
{
	echo
	echo "CHECKPKGS: Checking Release & InRelease files with GPG"
	echo
	for f in $(find . -type f -name Release -o -name InRelease | sort) ; do
		echo "Checking ${f#./}"
		case "$f" in
			*/Release)
				gpg="$f.gpg" ;;
			*/InRelease)
				gpg="" ;;
		esac
		gpgv --keyring trustedkeys.gpg $gpg "$f"
		echo
	done
	echo
	echo "CHECKPGS: Release files are ok"
	echo
}

# Helper function to check SHA-256 (if available), otherwise check for SHA-1
_check_sha ()
{
	while read hash file ; do
		# Only output checksums of existing files...
		if [ -f "$file" ] ; then
			echo "$hash  $MIRROR/$file"
		fi
	done | sort -k2 | uniq | sed -re 's%//+%/%g' -e 's%/\./%/%g' > $hashes

	cat $hashes | awk 'length($1) == 64 { print $0 }' > $hashes.sha256

	cat $hashes | awk '{ print $2 }' | uniq | \
	while read f ; do
		grep -q "  $f$" $hashes.sha256 || \
		egrep "^[a-f0-9]{40}  $f$" $hashes || true
	done > $hashes.sha1

	echo "CHECKPKGS: Checking SHA-256"
	echo
	sha256sum -c $hashes.sha256

	if [ -s $hashes.sha1 ] ; then
		echo
		echo "CHECKPKGS: Checking SHA-1"
		echo
		sha1sum -c $hashes.sha1
	fi
}

#
# Extract checksums of existing Packages* files from Release files
#
check_packages ()
{
	echo
	echo "CHECKPKGS: Checking Packages.* files..."
	echo
	find . -type f -name Release -o -name InRelease | \
	while read f ; do
		dir=${f%/*}
		# Extract SHA checksums from Release files
		egrep -v '[/ ]Release$' "$f" | gawk -v dir="$dir" '$1 ~ /^[a-f0-9]{40,}$/ { print $1, dir "/" $3; }'
	done | _check_sha

	echo
	echo "CHECKPKGS: Packages files are ok"
	echo
}

#
# Extract checksums of Debian packages from Packages files
#
check_debpkgs ()
{
	echo
	echo "CHECKPKGS: Checking packages..."
	echo

	find . -type f -name Packages | \
	while read f ; do
		dir=$(echo "$f" | sed -e 's%/dists/.*%/%' -e 's%/Packages$%/%')
		# Extract SHA checksums from Packages for every package
		awk -v dir="$dir" '{ if ($0 ~ /^Filename:/) s = $2; else if ($0 ~ /^(SHA256|SHA1): /) print $2, dir "/" s }' "$f"
	done | _check_sha

	echo
	echo "CHECKPKGS: All packages are ok"
	echo
}

download_pubkeys
check_release
check_packages
check_debpkgs

echo
echo "CHECKPKGS: Searching for packages with no SHA checksum: "
find . -name \*.deb | \
while read f ; do
	f="$MIRROR/${f#./}"
	fgrep -q "$f" $hashes || echo "$f"
done
echo

