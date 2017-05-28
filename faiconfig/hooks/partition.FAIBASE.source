
# Remove FAI device from $disklist
fai_dev=$(mount | awk '$3 == "/lib/live/mount/medium" { print $1; exit }' | sed -e 's%^/dev/%%' -e 's/[0-9]*$//')
disklist=$(echo $disklist | sed "s/${fai_dev} *//")
unset fai_dev

# Include RAID1 or LVM class if we find more than one disk

# Skip if already set
if echo $classes | egrep -qw '(NO)?(RAID1|RAID1_CRYPT|LVM)' ; then
	return 0
fi

n=0
for disk in $disklist ; do
	# Skip non-*ATA devices
	if [[ $(udevadm info -q property -n $disk | sed -rne 's/^ID_BUS=//p') == "ata" ]] ; then
		let n++
	fi
done

if [ $n -gt 1 ] ; then
	classes="$classes RAID1"
fi

unset n

