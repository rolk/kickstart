#!/bin/bash
# This file is licensed under the GPL version 3 or later.

# <http://bazaar.launchpad.net/~ubuntu-installer/finish-install/master/files>

# how are we invoked? needed for giving sensible usage description
INVOKER="$0"
INVOKER=${INVOKER/$HOME/\~}

# error message for missing prerequisite
missing () {
  cat 1>&2 <<EOF

Error: Some prerequisites are missing. Install necessary packages with:

  sudo apt-get install wget qemu-kvm qemu-utils

EOF
}

# display usage message
usage () {
  cat 1>&2 <<EOF

Usage:

  $INVOKER [options]

Options:

  --prefix=DIR          Put virtual harddisk in this directory [default=.]

  --version=SUITE       Version of the operating system [default=trusty]

  --arch={i386|x86_64}  Architecture to install [default=native]

  --user=NAME           Username to install [default="user"]

  --passwd=TEXT         Password to use [default=none]. This is only
                        necessary if you want to SSH into the machine.

  --force               Overwrite existing files [default=no]

  --mirror=URL          URL to closest Ubuntu mirror [default=auto]
EOF
}

# error message for invalid option
invalid_arg () {
  cat 1>&2 <<EOF

Error: Unrecognized option: \`$1'
EOF
  usage
}

# default settings
PREFIX=$(pwd)
MIRROR=
VER=trusty
ARCH=$(uname -m)
USERNAME=user
PASSWORD=
FORCE=no

# allow user to customize on command-line
for OPT in "$@"; do
  case "$OPT" in
    --*)
      OPTARG=${OPT#--}
      # OPTARG now contains everything after double dashes
      case "${OPTARG}" in
        prefix=*)
          # remove prefix consisting of everything up to equal sign
          PREFIX=${OPTARG#*=}
          ;;
        mirror=*)
          MIRROR=${OPTARG#*=}
          ;;
        force*)
          FORCE=${OPTARG#*=}
          [ "$FORCE" = "force" ] && FORCE=yes
          ;;
        uninett)
          # undocumented shorthand
          MIRROR=http://ftp.uninett.no/ubuntu
          ;;
        uib)
          # undocumented shorthand
          MIRROR=http://ubuntu.uib.no/archive
          ;;
        user=*)
          USERNAME=${OPTARG#*=}
          ;;
        passwd=*)
          PASSWORD=${OPTARG#*=}
          ;;
        arch=*)
          ARCH=${OPTARG#*=}
          # only accept these architectures
          if [ ! \( "$ARCH" = "i386" -o \
                    "$ARCH" = "x86_64" \) ]; then
              invalid_arg "--arch=$ARCH"
              exit 1
          fi
          ;;
        version=*)
          VER=${OPTARG#*=}
          VER=$(echo $VER | tr "[:upper:]" "[:lower:]")
          ;;
        help)
          usage
          exit 0
          ;;
        *)
          # remove everything *after* the equal sign
          arg=${OPTARG%=*}
          invalid_arg "--$arg"
          exit 1
          ;;
      esac
      ;;
    *)
      invalid_arg "$OPT"
      exit 1
      ;;
  esac
done
# remove all arguments processed by getopts
shift $((OPTIND-1))

# check that all prerequisites are in place before we start
if [ ! \( -x "$(command -v wget)"        -a \
          -x "$(command -v kvm-img)"     -a \
          -x "$(command -v qemu-system-${ARCH})" \) ]; then
  missing
  exit 1
fi

# translate Linux architecture to Ubuntu notation
DEB_ARCH=$ARCH
if [ "$DEB_ARCH" = "x86_64" ]; then DEB_ARCH=amd64; fi

# error handling: bail out if anything goes wrong
set -e

# uppercase first character of version name
DISPLAY="$(echo ${VER:0:1} | tr "[:lower:]" "[:upper:]")${VER:1}"

# check for existing files
if [ "$FORCE" != "yes" ]; then
  if [ -e "$PREFIX/ubuntu-$VER" ]; then
    echo Error: File "$PREFIX/ubuntu-$VER" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/ubuntu-$VER-raw.img" ]; then
    echo Error: File "$PREFIX/ubuntu-$VER-raw.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/ubuntu-$VER-base.img" ]; then
    echo Error: File "$PREFIX/ubuntu-$VER-base.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/ubuntu-$VER.img" ]; then
    echo Error: File "$PREFIX/ubuntu-$VER.img" already exists!
    exit 1
  fi
fi

# download list of mirrors, pick the first
if [ -z "$MIRROR" ]; then
  MIRROR=$(wget -q -O - http://mirrors.ubuntu.com/mirrors.txt | head -n 1)
  MIRROR=$(dirname $(dirname $(dirname $MIRROR)))
fi
echo Using Ubuntu mirror at: $MIRROR

# do everything in this directory
TMPROOT=$(mktemp -t -d ubuntu-$VER.XXXXXX)

# if you want an installation which mounts local disks, then you need the
# one from the hd-media/ directory, not netboot/. The mini.iso in netboot
# will not mount local media, but it will download packages from network
wget -nv -P "$TMPROOT" $MIRROR/ubuntu/dists/$VER/main/installer-$DEB_ARCH/current/images/netboot/netboot.tar.gz
tar zxf "$TMPROOT/netboot.tar.gz" -C "$TMPROOT"

# temporary disk may be in RAM, so delete this file when we no longer need it
rm "$TMPROOT/netboot.tar.gz"

# preseeded configuration to do automated installation
cat > "$TMPROOT/preseed.cfg" <<EOF
# localization
d-i debian-installer/language string en
d-i debian-installer/country string NO

# use the en_DK locale to get sane date format but English messages
d-i debian-installer/locale string en_DK.UTF-8

# optional locales to be generated
d-i localechooser/supported-locales en_US.UTF-8

# disable interactive keymap detection since we have automated inst.
d-i console-setup/ask_detect boolean false
d-i keyboard-configuration/modelcode string pc105
d-i keyboard-configuration/layoutcode string us
d-i keyboard-configuration/variantcode string dvp

# enable network configuration
d-i netcfg/enable boolean true

# interface to use for network installation
d-i netcfg/choose_interface select eth1

# allow waiting some time before DHCP server replies
d-i netcfg/dhcp_timeout string 10

# set hostname to a dummy value so questions are not asked, even if
# the ultimate value for these settings will be delivered by DHCP
d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_domain string unassigned-domain

# disable that annoying WEP key dialog.
d-i netcfg/wireless_wep string

# don't ask for non-free firmware to load network
d-i hw-detect/load_firmware boolean false

# mirror selection
d-i mirror/protocol string http
d-i mirror/country string manual
d-i mirror/http/hostname string ubuntu.uib.no
d-i mirror/http/directory string /archive
d-i mirror/http/proxy string

# suite to install
d-i mirror/suite string $VER
d-i mirror/udeb/suite string $VER
d-i mirror/udeb/components multiselect main,restricted,universe,multiverse

# hardware clock set to UTC
d-i clock-setup/utc boolean true
d-i time/zone string CET

# use NTP to set clock during install
d-i clock-setup/ntp boolean true
d-i clock-setup/ntp-server string ntp.uib.no

# replace the display module of partman with a script that retrieves
# partitioning commands from the tftp server and then does the
# partitioning itself. then disable all the checks that are being
# done towards the parted server afterwards. the display module can
# return an exit code of 100 to signal successful partitioning.
# we must download the post-configure script here, because when
# late_command executes, the wrapper script has already read the names
# of the files in finish-install.d to execute.
# the ttyS0.conf file is overwritten by the 90console script, so
# we cannot modify it directly in the late_command; instead we must
# install it as a hook to be executed at a later stage
d-i preseed/early_command string \
mkdir -p /lib/partman/display.d ; \
echo \#\!/bin/sh > /lib/partman/display.d/00auto ; \
echo . /partition.sh >> /lib/partman/display.d/00auto ; \
echo chmod -x /lib/partman/check.d/\* >> /lib/partman/display.d/00auto ; \
echo PARTMAN_NO_COMMIT=1 >> /lib/partman/display.d/00auto ; \
echo export PARTMAN_NO_COMMIT >> /lib/partman/display.d/00auto ; \
echo exit 100 >> /lib/partman/display.d/00auto ; \
chmod +x /lib/partman/display.d/00auto ; \
mv /postconf.sh /usr/lib/finish-install.d/94postconf ; \
chmod +x /usr/lib/finish-install.d/94postconf

# setting to avoid having partman complain about no changes being made
# (that the server component know of - we do partitioning alongside)
d-i partman/confirm_nochanges boolean true

# use virtual kernel to avoid having too many drivers
d-i base-installer/kernel/override-image string linux-virtual

# account setup; generate md5 hash of password
d-i passwd/root-login boolean false
d-i passwd/user-fullname string Nomen Nascio
d-i passwd/username string $USERNAME
d-i passwd/user-password-crypted password $(mkpasswd -m sha-512 "$PASSWORD")
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false

# which sections of the repositories to pull from
d-i apt-setup/restricted boolean true
d-i apt-setup/universe boolean true
d-i apt-setup/backports boolean true
d-i apt-setup/services-select multiselect security
d-i apt-setup/security_host string security.ubuntu.com
d-i apt-setup/security_path string /ubuntu

# roles
tasksel tasksel/first multiselect minimal

# individual additional packages to install
d-i pkgsel/include string util-linux,xterm

# don't upgrade packages after debootstrap since we pull them from network anyway
d-i pkgsel/upgrade select none

# language packs
d-i pkgsel/language-packs multiselect en

# don't install unattended-upgrades automatically in virtual machine
d-i pkgsel/update-policy select none

# no feedback from development machines
popularity-contest popularity-contest/participate boolean false

# use grub as the boot loader
d-i grub-installer/skip boolean false

# install automatically to MBR since there are no other OSes
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true

# don't be stuck on the boot screen
d-i grub-installer/timeout string 0

# give us the full boot
d-i debian-installer/splash boolean false
d-i debian-installer/quiet boolean false

# additional boot parameters so we can see kernel messages
d-i debian-installer/add-kernel-opts string console=ttyS0

# avoid that last message about the install being complete.
d-i finish-install/reboot_in_progress note

# shutdown when finished, but not reboot into the installed system.
d-i debian-installer/exit/halt boolean false
EOF

# use 'preseed/url=tftp://10.0.2.2/preseed.cfg' as kernel parameter
# if you want to download the preseed file from directory at host
cat > "$TMPROOT/pxelinux.cfg/default" <<EOF
serial 0 115200
console 0
default auto
label auto
kernel ubuntu-installer/$DEB_ARCH/linux
append console=ttyS0,115200n8 initrd=ubuntu-installer/$DEB_ARCH/initrd.gz DEBIAN_FRONTEND=text auto=true priority=critical interface=auto --
EOF

cat > "$TMPROOT/partition.sh" <<EOF
#!/bin/sh
sfdisk -C 8192 -H 128 -S 8 /dev/sda <<___
0,1,0
1,8191,L,*
___
mkfs.ext4 -L harddisk -b 4096 -i 4096 -E stride=128,stripe-width=128 -O ^resize_inode,^huge_file -M / /dev/sda2
tune2fs -o journal_data_writeback -r 25600 /dev/sda2
mkdir /target
mount -t ext4 /dev/sda2 /target
mkdir /target/etc
cat > /target/etc/fstab <<___
proc      /proc proc nodev,noexec,nosuid 0 0
/dev/sda2 /     ext4 defaults,noatime,nodiratime,nouser_xattr,data=writeback,commit=120,errors=remount-ro 0 1
___
EOF

cat > "$TMPROOT/postconf.sh" <<EOF
#!/bin/sh

# automatically login
cat > /target/etc/init/ttyS0.conf <<___
start on stopped rc RUNLEVEL=[2345]
stop on runlevel [!2345]
respawn
exec /sbin/agetty --noclear --autologin $USERNAME ttyS0 115200 xterm
___

# no password for users in sudo group
sed -i 's,\(%sudo\tALL\)=(\(ALL:ALL\)) \(ALL\),\1=(\2) NOPASSWD:\3,' /target/etc/sudoers

# sane command-line prompt
cat > /target/etc/profile.d/prompt.sh <<___
export PS1='\u@\h:\w> '
___

# disable OOM killer
cat >> /target/etc/sysctl.conf <<___

# disable out-of-memory-killer
vm.overcommit_memory=2
vm.overcommit_ratio=150
___

# disable OOM killer in any processes already started
sed -i '/exit 0/d' /target/etc/rc.local
cat >> /target/etc/rc.local <<___

# disable OOM killer for all (and new) processes
if [ \\\$(find /proc/[0-9]* -name oom_score_adj | wc -l) -eq 0 ]; then
for i in /proc/[0-9]*/oom_adj; do echo -ne "-17" > \\\$i; done
else
for i in /proc/[0-9]*/oom_score_adj; do echo -ne "-1000" > \\\$i; done
fi

exit 0
___

# configure alias to host system
echo -e '10.0.2.2\tdom0' >> /target/etc/hosts

# make sure that console change when window resizes
cat > /target/etc/profile.d/serial.sh <<___
if [ \\\$(tty) == "/dev/ttyS0" ]; then
  trap '[ "\\\$(tty)" = "/dev/ttyS0" ] && eval "\\\$(resize)"' DEBUG
fi
___

# clear the disk
/target/sbin/fstrim -v /target
EOF

# you can get a listing of the files on the initial disk with the command
# zcat ubuntu-installer/$DEB_ARCH/initrd.gz | cpio -ivt

pushd "$TMPROOT"
gzip -d ubuntu-installer/$DEB_ARCH/initrd.gz
echo -e preseed.cfg\\npartition.sh\\npostconf.sh |\
  cpio -oA -F ubuntu-installer/$DEB_ARCH/initrd -H newc -R root:root
gzip ubuntu-installer/$DEB_ARCH/initrd
popd

# you can add files to the disk with
# echo preseed.cfg | cpio -c -o >> initrd.img
  
# create an installation disk; we only need around 1.3G for the installation,
# later to be shrinked down to 230M, but we want to format the disk to
# potentially hold more. On ext3 creating a large file with zeros is inexpensive
dd of=$PREFIX/ubuntu-$VER-raw.img bs=4G seek=1 count=0

# use '-boot once=d' and '-drive file=$TMPROOT/mini.iso,index=1,media=cdrom'
# if you are booting the mini.iso image
qemu-system-${ARCH} \
  -name "Ubuntu $DISPLAY" \
  -enable-kvm \
  -m 1G \
  -boot once=n \
  -drive file=$PREFIX/ubuntu-$VER-raw.img,if=none,id=hd0,discard=unmap,media=disk,format=raw,cache=unsafe \
  -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0 \
  -netdev user,id=hostnet0,hostname=ubuntu-$VER,tftp=$TMPROOT,bootfile=pxelinux.0 \
  -device virtio-net-pci,romfile=pxe-virtio.rom,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot

# compact installation disk
kvm-img convert \
  -c \
  -f raw -O qcow2 \
  $PREFIX/ubuntu-$VER-raw.img \
  $PREFIX/ubuntu-$VER-base.img

rm $PREFIX/ubuntu-$VER-raw.img

# create an overlay to store further changes on
kvm-img create \
  -b $PREFIX/ubuntu-$VER-base.img \
  -f qcow2 \
  $PREFIX/ubuntu-$VER.img

# <http://alexeytorkhov.blogspot.no/2009/09/mounting-raw-and-qcow2-vm-disk-images.html>
# you can mount this disk image with
# sudo modprobe nbd max_part=63
# sudo qemu-nbd -c /dev/nbd0 ubuntu-$VER.img
# sudo mount /dev/nbd0p2 /mnt
# sudo umount /mnt
# sudo qemu-nbd -d /dev/nbd0

# script to boot regular installation
cat > $PREFIX/ubuntu-$VER <<EOF
#!/bin/sh
qemu-system-${ARCH} \
  -name "Ubuntu $DISPLAY" \
  -enable-kvm \
  -m 1G \
  -boot order=c \
  -drive file=$(dirname \$0)/ubuntu-$VER.img,if=none,id=hd0,discard=unmap,media=disk,cache=writeback \
  -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0 \
  -netdev user,id=hostnet0,hostname=ubuntu-$VER -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot
EOF
chmod +x $PREFIX/ubuntu-$VER

# clean up temporary directory
rm -rf "$TMPROOT"
