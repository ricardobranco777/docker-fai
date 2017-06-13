#!/bin/bash
#
# v1.10.3 by Ricardo Branco
#
# This script creates a mirror of .deb packages for inclusion in FAI ISO's and makes it suitable for Trusted Builds
#
# Public Domain
#

if [ $# -lt 1 ] ; then
	echo "Usage: ${0##*/} HOSTNAME..." >&2
	exit 1
fi

MIRROR="/tmp/mirror"
CACHE="/var/cache/apt-cacher-ng"
PROXY="http://127.0.0.1:9999"

[ -f /etc/fai/nfsroot.conf ] && . /etc/fai/nfsroot.conf

NFSROOT=${NFSROOT:-/srv/fai/nfsroot}
if [ -f "$NFSROOT/live/filesystem.dir/.THIS_IS_THE_FAI_NFSROOT" ] ; then
	NFSROOT="$NFSROOT/live/filesystem.dir"
elif [ ! -f "$NFSROOT/.THIS_IS_THE_FAI_NFSROOT" ] ; then
	echo "ERROR: You must run \"fai-setup -vl\" to set up the NFSROOT" >&2
	exit 1
fi

FAI_CONFIGDIR=${FAI_CONFIGDIR:-/srv/fai/config}

for host ; do
	host_classes=$(HOSTNAME="$host" sh $FAI_CONFIGDIR/class/50-host-classes 2>/dev/null)
	if [ -z "$host_classes" ] ; then
		echo "ERROR: Unknown hostname: $host" >&2
		exit 1
	fi
	classes="$classes $host_classes"
done
if [ -n "$classes" ] ; then
	classes=$(echo $classes | tr ' ' '\n' | sort -u | tr '\n' ' ')
	classes=$(echo DEFAULT $classes AMD64 GRUB_PC _FAISETUP | tr ' ' ,)
fi

case $(echo $classes | egrep -ow '(DEBIAN_[78]|UBUNTU_1[46])') in
	DEBIAN_7)
		distro="debian"
		codename="wheezy" ;;
	DEBIAN_8)
		distro="debian"
		codename="jessie" ;;
	UBUNTU_14)
		distro="ubuntu"
		codename="trusty" ;;
	UBUNTU_16)
		distro="ubuntu"
		codename="xenial" ;;
	*)
		echo "Unknown Operating System" >&2
		exit 1 ;;
esac

# Create /etc/fai/faimirror/apt/sources.list

mkdir -p /etc/fai/faimirror/apt

if [ $distro = "debian" ] ; then
	cat > /etc/fai/faimirror/apt/sources.list <<- EOF
		deb $PROXY/${REPO:-ftp.us.debian.org}/debian $codename main contrib non-free
		deb $PROXY/${REPO:-ftp.us.debian.org}/debian $codename-updates main contrib non-free
		deb $PROXY/security.debian.org $codename/updates main contrib non-free
		deb $PROXY/${REPO:-ftp.us.debian.org}/debian $codename-backports main contrib non-free
		deb $PROXY/fai-project.org/download $codename koeln
	EOF
	sed -ri -e "s%^(FAI_DEBOOTSTRAP)=.*%\1=\"$codename http://${REPO:-ftp.us.debian.org}/debian\"%" /etc/fai/faimirror/nfsroot.conf
elif [ $distro = "ubuntu" ] ; then
	cat > /etc/fai/faimirror/apt/sources.list <<- EOF
		deb $PROXY/${REPO:-archive.ubuntu.com}/ubuntu $codename main restricted universe multiverse
		deb $PROXY/${REPO:-archive.ubuntu.com}/ubuntu $codename-updates main restricted universe multiverse
		deb $PROXY/${REPO:-archive.ubuntu.com}/ubuntu $codename-backports main restricted universe multiverse
		deb $PROXY/security.ubuntu.com/ubuntu $codename-security main restricted universe multiverse
		deb $PROXY/archive.canonical.com/ubuntu $codename partner
		deb $PROXY/fai-project.org/download jessie koeln
	EOF
	sed -ri -e "s%^(FAI_DEBOOTSTRAP)=.*%\1=\"$codename http://${REPO:-archive.ubuntu.com}/ubuntu\"%" /etc/fai/faimirror/nfsroot.conf
fi

if echo $classes | grep -qw 'DOCKER' ; then
	echo "deb [arch=amd64] https://download.docker.com/linux/$distro $codename edge" >> /etc/fai/faimirror/apt/sources.list
	fingerprints+=("9DC858229FC7DD38854AE2D88D81803C0EBFCD88")
fi

if echo $classes | grep -qw 'JAVA_[678]' ; then
	echo "deb $PROXY/ppa.launchpad.net/webupd8team/java/ubuntu $codename main" >> /etc/fai/faimirror/apt/sources.list
	fingerprints+=("7B2C3B0889BF5709A105D03AC2518248EEA14886")
fi

if echo $classes | grep -qw 'CHROME' ; then
	echo "deb [arch=amd64] $PROXY/dl.google.com/linux/chrome/deb/ stable main" >> /etc/fai/faimirror/apt/sources.list
	fingerprints+=("4CCA1EAF950CEE4AB83976DCA040830F7FAC5991")
	fingerprints+=("EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796")
fi

if echo $classes | grep -qw 'MONGODB' ; then
	if [ $distro = "debian" ] ; then
		mongo_dist="main"
	elif [ $distro = "ubuntu" ] ; then
		mongo_dist="multiverse"
	fi
	echo "deb $PROXY/repo.mongodb.org/apt/$distro $codename/mongodb-org/3.2 $mongo_dist" >> /etc/fai/faimirror/apt/sources.list
	fingerprints+=("42F3E95A2C4F08279C4960ADD68FA50FEA312927")
fi

for fingerprint in ${fingerprints[@]} ; do
	gpg --no-default-keyring --keyring /etc/apt/trusted.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $fingerprint
done

# Start with a clean cache
rm -rf $CACHE/*

# Tell fai-mirror that we want to include base packages too
rm -f $NFSROOT/var/tmp/base-pkgs.lis

# Include packages in nfsroot
# XXX Only applies when the same OS is on nfsroot
if [[ $(md5sum /etc/os-release | awk '{ print $1 }') = $(md5sum $NFSROOT/etc/os-release | awk '{ print $1 }') ]] ; then
	chroot $NFSROOT/ dpkg -l | \
	awk '$1 ~ /^[hi]i$/ { print $2 ~ /^fai-/ ? $2 "=" $3 : $2 }' | \
	grep -v -e '^linux-image-' | \
	xargs echo -e 'PACKAGES aptitude\n' > $FAI_CONFIGDIR/package_config/_FAISETUP
fi

# Run fai-mirror
rm -rf $MIRROR
mkdir -p $MIRROR || exit 1
if [ -n "$classes" ] ; then
	fai-mirror -vBC /etc/fai/faimirror -c "$classes" $MIRROR || exit 1
else
	fai-mirror -vBC /etc/fai/faimirror $MIRROR || exit 1
fi

rm -f $FAI_CONFIGDIR/packages/_FAISETUP

# We work with what's left on apt-cacher-ng's cache
rm -rf $MIRROR
mkdir -p $MIRROR || exit 1

# Copy the Ubuntu / Debian trees

cd $CACHE

for dir in *.ubuntu.com archive.canonical.com *.debian.net *.debian.org ; do
	if [ -d "$dir" ] ; then
		mkdir $MIRROR/$dir
		cp -r $dir $MIRROR
	fi
done

if [ -d debrep ] ; then
	mkdir -p $MIRROR/cdn.debian.net/debian
	cp -r debrep/* $MIRROR/cdn.debian.net/debian
fi

if [ -d uburep ] ; then
	mkdir -p $MIRROR/archive.ubuntu.com/ubuntu
	cp -r uburep/* $MIRROR/archive.ubuntu.com/ubuntu
fi

# Copy the FAI, Docker, Google and PPA directories
for d in fai-project.org download.docker.com ppa.launchpad.net dl.google.com repo.mongodb.org ; do
	[ ! -d $CACHE/$d ] && continue
	cp -r $CACHE/$d $MIRROR
done

# Delete .head files
find $MIRROR -name \*.head -exec rm -f {} +

# Check for AptByHash scheme:
# https://wiki.ubuntu.com/AptByHash

find $MIRROR -type f -regextype egrep -regex '.*/by-hash/SHA(256|512)/[a-f0-9]+$' | \
while read f ; do
	type=$(file -b "$f")
	if [[ $type =~ ^gzip\ compressed\ data ]] ; then
		suffix=".gz"
	elif [[ $type =~ ^XZ\ compressed\ data ]] ; then
		suffix=".xz"
	elif [[ $type =~ ^bzip2\ compressed\ data ]] ; then
		suffix=".bz2"
	elif [[ $type =~ ^LZ4\ compressed\ data ]] ; then
		suffix=".lz4"
	elif [[ $type =~ ^(UTF-8\ Unicode|ASCII)\ text ]] ; then
		suffix=""
	else
		echo "ERROR: Unknown file type: $f" >&2
		break
	fi
	mv -f "$f" ${f%/by-hash/*}/Packages${suffix}
	rmdir -p ${f%/by-hash/*}/by-hash/* 2>/dev/null || true
done

# Decompress Packages.(gz|xz|bz2|lz4) files, if present
find $MIRROR -regextype egrep -regex '.*/Packages.(gz|xz|bz2|lz4)$' | \
while read f ; do
	case "$f" in
		*.gz)
			command="gzip"
			suffix=".gz" ;;
		*.xz)
			command="xz"
			suffix=".xz" ;;
		*.bz2)
			command="bzip2"
			suffix=".bz2" ;;
		*.lz4)
			command="lz4"
			suffix=".lz4" ;;
	esac
	[[ -f ${f%$suffix} ]] && continue
	$command -dc "$f" > "${f%$suffix}"
done
