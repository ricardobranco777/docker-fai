#!/bin/bash
#
# v1.5.3 by Ricardo Branco
#
# This script runs fai-cd on a clean /srv/fai/config with contains only the desired FAI classes
#
# Public Domain
#

if grep -q XXX /etc/fai/grub.cfg ; then
	echo "ERROR: Please edit /etc/fai/grub.cfg" >&2
	exit 1
fi

if grep -q xxx /etc/fai/grub.cfg ; then
	echo "ERROR: Please edit the hostname in /etc/fai/grub.cfg" >&2
	exit 1
fi

[ -f /etc/fai/nfsroot.conf ] && . /etc/fai/nfsroot.conf
NFSROOT=${NFSROOT:-/srv/fai/nfsroot}
FAI_CONFIGDIR=${FAI_CONFIGDIR:-/srv/fai/config}

if [ $# -gt 0 ] ; then
	for host ; do
		host_classes=$(HOSTNAME="$host" sh $FAI_CONFIGDIR/class/50-host-classes 2>/dev/null)
		if [ -z "$host_classes" ] ; then
			echo "ERROR: Unknown hostname: $host" >&2
			exit 1
		fi
		classes="$classes $host_classes $host"
	done
	classes=$(echo $classes | tr ' ' '\n' | sort -u | tr '\n' ' ')
	classes=$(echo DEFAULT $classes AMD64 GRUB_PC LOCAL_MIRROR LAST)

	mkdir -p /tmp/faiconfig/{basefiles,class,debconf,disk_config,files,hooks,package_config,scripts,tests}
	cd /tmp/faiconfig

	# Copy basefiles
	for class in $classes ; do
		cp $FAI_CONFIGDIR/basefiles/$class.* basefiles/ 2>/dev/null
	done

	# Copy class directory (scripts and *.var)
	cp $FAI_CONFIGDIR/class/[0-9]* class/
	for class in $classes ; do
		cp $FAI_CONFIGDIR/class/$class.* class/ 2>/dev/null
	done

	# Copy these entire directories
	for dir in debconf disk_config hooks tests ; do
		cp -a $FAI_CONFIGDIR/$dir .
	done

	# Copy the files directory
	for class in $classes preinst postinst ; do
		( cd $FAI_CONFIGDIR
		  tar cf - $(find files -type f -regextype egrep -regex ".*/$class(\.(tar(\.(gz|bz2|xz))?|tgz|txz))?$") 2>/dev/null
		) | tar xf - 2>/dev/null
	done

	# Copy the scripts directory
	for class in $classes ; do
		cp -a $FAI_CONFIGDIR/scripts/$class/ scripts/ 2>/dev/null
	done

	# Copy the package_config directory
	for class in $classes ; do
		cp -a $FAI_CONFIGDIR/package_config/$class $FAI_CONFIGDIR/package_config/$class.* package_config/ 2>/dev/null
	done

else
	rm -rf /tmp/faiconfig/
	mkdir /tmp/faiconfig || exit 1
	cp -a $FAI_CONFIGDIR/* /tmp/faiconfig/
fi

cleanup ()
{
	umount $FAI_CONFIGDIR 2>/dev/null
}

# Cleanup on interrupt
trap cleanup HUP INT QUIT TERM

chown -R root.root /tmp/faiconfig /tmp/mirror
chmod -R a+r /tmp/mirror

mount --bind /tmp/faiconfig $FAI_CONFIGDIR

chmod +x $FAI_CONFIGDIR/class/[0-9]* $FAI_CONFIGDIR/hooks/* $FAI_CONFIGDIR/scripts/*/*

# Since Grub 2.0, we must add the --unrestricted option if we use GRUB passwords
GRUB_VERSION=$(chroot $NFSROOT/live/filesystem.dir dpkg-query -W -f '${Version}' grub-pc)
case "$GRUB_VERSION" in
	2.*)
		fgrep -q -- "--unrestricted {" /etc/fai/grub.cfg || \
		sed -i '/^menuentry/s/{/ --unrestricted {/' /etc/fai/grub.cfg ;;
	*)
		sed -i 's/--unrestricted//' /etc/fai/grub.cfg ;;
esac

fai-cd -f -g /etc/fai/grub.cfg -m /tmp/mirror /tmp/fai-full.iso

umount $FAI_CONFIGDIR

