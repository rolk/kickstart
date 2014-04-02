#!/bin/bash
# This file is licensed under the GPL version 3 or later.

# <http://ktaraghi.blogspot.no/2012/09/automated-installation-of-centos-6x-and.html>
# <http://blog.crazytje.be/create-a-kickstart-netinstall-with-centos/>
# <http://www.deepshiftlabs.com/dev_blog/?p=1571&lang=en-us>
# <https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/5/html/Installation_Guide/s1-kickstart2-options.html>
# <https://access.redhat.com/site/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Installation_Guide/s1-kickstart2-options.html>

# how are we invoked? needed for giving sensible usage description
INVOKER="$0"
INVOKER=${INVOKER/$HOME/\~}

# error message for missing prerequisite
missing () {
  cat 1>&2 <<EOF

Error: Some prerequisites are missing. Install necessary packages with:

  sudo apt-get install wget qemu dosfstools fusefat fuseiso python-pykickstart

EOF
}

# display usage message
usage () {
  cat 1>&2 <<EOF

Usage:

  $INVOKER [options]

Options:

  --prefix=DIR          Put virtual harddisk in this directory [default=.]

  --version=X.Y         Version of the operating system [default=5.10]

  --arch={i386|x86_64}  Architecture to install [default=native]

  --user=NAME           Username to install [default="user"]

  --passwd=TEXT         Password to use [default=none]. This is only
                        necessary if you want to SSH into the machine.

  --force               Overwrite existing files [default=no]

  --mirror=URL          URL to closest CentOS mirror [default=auto]

  --epel=URL            URL to closest EPEL mirror [default=auto]

The kickstart script will attempt to find the closest mirror automatically.

To override this, get a mirror link from the URL
<http://mirror.centos.org/centos/5/isos/x86_64/> and remove three path
components in the entry from that list; e.g. if the link is
http://ftp.uninett.no/pub/Linux/centos/5.10/isos/x86_64/, specify
--mirror=http://ftp.uninett.no/pub/Linux/centos

For the EPEL link, specify the link that is given at the webpage
<https://mirrors.fedoraproject.org/publiclist/EPEL/>, e.g.
give --epel=http://ftp.uninett.no/linux/epel (Many CentOS mirrors
are also EPEL mirrors).

EOF
}

# error message for invalid option
invalid_arg () {
  cat 1>&2 <<EOF

Error: Unrecognized option: \`$1'
EOF
  usage
}

# check that all prerequisites are in place before we start
if [ ! \( -x "$(command -v wget)"        -a \
          -x "$(command -v ksvalidator)" -a \
          -x "$(command -v mkdosfs)"     -a \
          -x "$(command -v fusefat)"     -a \
          -x "$(command -v fuseiso)"     -a \
          -x "$(command -v kvm-img)"     -a \
          -x "$(command -v kvm)" \) ]; then
  missing
  exit 1
fi

# default settings
PREFIX=$(pwd)
MIRROR=
EPEL=
MAJOR=5
MINOR=10
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
        epel=*)
          EPEL=${OPTARG#*=}
          ;;
        force*)
          FORCE=${OPTARG#*=}
          [ "$FORCE" = "force" ] && FORCE=yes
          ;;
        uninett)
          # undocumented shorthand
          MIRROR=http://ftp.uninett.no/pub/Linux/centos
          EPEL=http://ftp.uninett.no/linux/epel
          ;;
        uib)
          # undocumented shorthand
          MIRROR=http://centos.uib.no
          EPEL=http://fedora.uib.no/epel
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
          MAJOR=$(echo $VER | cut -f 1 -d.)
          MINOR=$(echo $VER | cut -f 2 -d.)
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

# error handling: bail out if anything goes wrong
set -e

# check for existing files
if [ "$FORCE" != "yes" ]; then
  if [ -e "$PREFIX/CentOS-$MAJOR.$MINOR" ]; then
    echo Error: File "$PREFIX/CentOS-$MAJOR.$MINOR" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/CentOS-$MAJOR.$MINOR-raw.img" ]; then
    echo Error: File "$PREFIX/CentOS-$MAJOR.$MINOR-raw.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/CentOS-$MAJOR.$MINOR-base.img" ]; then
    echo Error: File "$PREFIX/CentOS-$MAJOR.$MINOR-base.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/CentOS-$MAJOR.$MINOR.img" ]; then
    echo Error: File "$PREFIX/CentOS-$MAJOR.$MINOR.img" already exists!
    exit 1
  fi
fi

# download list of mirrors, pick the first
if [ -z "$MIRROR" ]; then
  MIRROR=$(wget -q -O - http://mirrorlist.centos.org/?release=$MAJOR\&arch=$ARCH\&repo=os | grep -v ^# | head -n 1)
  MIRROR=$(dirname $(dirname $(dirname $MIRROR)))
fi
echo Using CentOS mirror at: $MIRROR

if [ -z "$EPEL" ]; then
  EPEL=$(wget -q -O - http://mirrors.fedoraproject.org/mirrorlist?repo=epel-$MAJOR\&arch=$ARCH | grep -v ^# | head -n 1)
  EPEL=$(dirname $(dirname $EPEL))
fi
echo Using EPEL mirror at: $EPEL

# do everything in this directory
TMPROOT=$(mktemp -t -d centos-${MAJOR}_${MINOR}.XXXXXX)

# download the network installation iso; this is comparable in size
# to many packages, so we just do it every time
wget -nv -P "$TMPROOT" $MIRROR/$MAJOR.$MINOR/isos/$ARCH/CentOS-$MAJOR.$MINOR-$ARCH-netinstall.iso

# write first to a file on disk, since fusefat in seemingly unstable
# when taking input from pipe (?)
cat > $TMPROOT/ks.cfg <<EOF
# don't use graphical install
#text
cmdline

# start the installation process
install

# installation media
#cdrom
# use network install
url --url=$MIRROR/$MAJOR.$MINOR/os/$ARCH

# extra repositories
repo --name=epel --baseurl=$EPEL/$MAJOR/$ARCH
repo --name=updates --baseurl=$MIRROR/$MAJOR/updates/$ARCH

# get network info from DHCP server;
# hostname will be received in the same query.
network --device eth0 --bootproto dhcp

# setup language and keyboard
lang en_US.UTF-8
keyboard us
# Fedora 18 onwards
#keyboard --xlayouts='us (dvp)'

# disable direct root login
rootpw *

# setup firewall and open ssh port 22
firewall --enabled

# sets up the Shadow Password Suite (--enableshadow) and the SHA 512 bit
# encryption algorithm for password encryption (--passalgo=sha512)
authconfig --enableshadow --passalgo=sha512

# selinux directive can be set to --enforcing, --permissive, or --disabled
selinux --disabled

# setup timezone
timezone --utc Etc/CET

# default bootloader is GRUB. it should normally be installed on the MBR.
# you can include a --driveorder switch to specify the drive with the bootloader
# and an --append switch to specify commands for the kernel.
bootloader --location=mbr --driveorder=vda

# clear the Master Boot Record
zerombr

# this directive clears all volumes on the sda hard drive. If it hasn’t been used
# before, --initlabel initializes that drive. vda is used instead of sda since we
# are using the virtio driver in kvm
clearpart --all --drives=vda --initlabel

# use one partition for system and data (and no swap)
part /boot --fstype=ext3 --size=64
part / --fstype=ext3 --size=1 --grow --label=CentOS_$MAJOR.$MINOR

# if we have a console machine only
#skipx

# reboot machine
reboot

# skip answers to the First Boot process
firstboot --disable

# actual package install section; dependencies will be resolved automatically
%packages
@ Base
#@ Development Tools
mingetty
wget
epel-release
# needed for resize program used to set console size
xterm
# needed to clear the virtual disk efficiently
zerofree
# if you want to switch to GUI mode, you have to install the following packages
#@ basic-desktop
#@ desktop-platform
#@ x11
#@ fonts

%post
# lock the root account for login, we'll use sudo; later versions of Kickstart
# have a --lock argument to rootpw which can do this
passwd -l root

# adding a user, in this case "scott"
useradd -m $USERNAME

# set password for user "scott", if given
test -z '$PASSWORD' || (echo '$PASSWORD' | passwd --stdin $USERNAME)

# expire the password and force the user to enter the new password after first
#passwd -e $USERNAME
chage -M -1 $USERNAME

# setup sudo access for this user
echo '$USERNAME ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# turn on the GUI mode, if you want to
#sed -i 's/id:3:initdefault:/id:5:initdefault:/g' /etc/inittab

# don't wait to select OS in bootloader
sed -i 's,\(timeout\)=\(.*\),\1=0,' /boot/grub/grub.conf

# only probe for serial terminal upon boot
sed -i 's,\(terminal --timeout\)=\(.*\) serial console,\1=0 serial,' /boot/grub/grub.conf

# specify kernel parameters; leter versions let us use the --append option
# to the bootloader command with quotation
sed -i 's,^\(\tkernel.*\),\1 clocksource=kvm-clock clocksource_failover=acpi_pm,' /boot/grub/grub.conf

# autologin on the virtual terminal; Upstart has /etc/init/serial.conf,
# SYSV has /etc/inittab
if test -f /etc/init/serial.conf ; then
  sed -i 's,exec /sbin/agetty /dev/\\\$DEV \\\$SPEED vt100-nav,exec /sbin/mingetty --noclear --autologin $USERNAME \\\$DEV,' /etc/init/serial.conf;
else
  # make sure Kudzu has run so it doesn't overwrite /etc/inittab afterwards
  /sbin/kudzu -s -q
  sed -i 's,/sbin/agetty \(ttyS[0-9]\).*,/sbin/mingetty --noclear --autologin $USERNAME \1,' /etc/inittab;
fi

# sane command-line prompt
cat > /etc/profile.d/prompt.sh <<___
export PS1='\u@\h:\w> '
___

# disable OOM killer
cat >> /etc/sysctl.conf <<___

# disable out-of-memory-killer
vm.overcommit_memory=2
vm.overcommit_ratio=150
___

# disable OOM killer in any processes already started
cat >> /etc/rc.local <<___

# disable OOM killer for all (and new) processes
if [ \\\$(find /proc/[0-9]* -name oom_score_adj | wc -l) -eq 0 ]; then
for i in /proc/[0-9]*/oom_adj; do echo -ne "-17" > \\\$i; done
else
for i in /proc/[0-9]*/oom_score_adj; do echo -ne "-1000" > \\\$i; done
fi
___

# configure alias to host system
echo -e '10.0.2.2\tdom0' >> /etc/hosts

# make sure that console change when window resizes
cat > /etc/profile.d/serial.sh <<___
if [ \\\$(tty) == "/dev/ttyS0" ]; then
  trap '[ "\\\$(tty)" = "/dev/ttyS0" ] && eval "\\\$(resize)"' DEBUG
fi
___

# correct for bug in nash builtin stabilized
#sed -i 's,\(emit \"stabilized --hash --interval\) \([0-9]*\) \(/proc/scsi/scsi\),\1 1 \3,' /sbin/mkinitrd

# zero out unused blocks before the filesystem is mounted
# notice the quoting of newlines necessary for the sed script
# to be correct output from the post-install script
sed -i '/^\# Remount the root filesystem read-write\./i\\\

\#FIRSTBOOT_START\#\\
\# clear unused filesystem blocks\\
action "Sparsify /dev/vda1" /usr/sbin/zerofree /dev/vda1\\
action "Sparsify /dev/vda2" /usr/sbin/zerofree /dev/vda2\\
\#FIRSTBOOT_END\#\\
' /etc/rc.d/rc.sysinit

# do this one the first boot; the section is removed afterwards
/bin/cat >> /etc/rc.local <<___
#FIRSTBOOT_START#
# clean up after our initialization
/bin/sed -i '/^\#FIRSTBOOT_START\#/,/^\#FIRSTBOOT_END\#/d' /etc/rc.d/rc.sysinit
/bin/sed -i '/^\#FIRSTBOOT_START\#/,/^\#FIRSTBOOT_END\#/d' /etc/rc.local
# return to console for disk compaction
/sbin/shutdown -h now
#FIRSTBOOT_END#
___
EOF

# check input file
#    yum install pykickstart
#    ksvalidator -v RHEL6 ks.cfg

# check that we haven't made any errors in the above ks.cfg file
ksvalidator -v RHEL$MAJOR $TMPROOT/ks.cfg

### Preparing the floppy disk

# create a virtual floppy disk (1.44M)
dd if=/dev/zero of=$TMPROOT/ks.img bs=4096 count=360

# format the disk
mkdosfs -F 12 -v $TMPROOT/ks.img 1440

# private mount-point
mkdir -p $TMPROOT/floppy

# mount a vfat diskette image to the floppy drive
#mount CentOS-$MAJOR-$MINOR-ks.img ~/mnt -o loop,sync,dirsync,uid=$(id -u $(whoami)),gid=$(id -g $(whoami))
fusefat $TMPROOT/ks.img $TMPROOT/floppy -o direct_io,rw+,uid=$(id -u $(whoami)),gid=$(id -g $(whoami))

# copy the Kickstart configuration file to the floppy
cp $TMPROOT/ks.cfg $TMPROOT/floppy/ks.cfg

# unload disk image
fusermount -u $TMPROOT/floppy

### Doing the installation

# mount the installation cdrom to be available to host also
#sudo mount -o loop,ro CentOS-$MAJOR.$MINOR-$ARCH-netinstall.iso /media/cdrom
mkdir -p $TMPROOT/cdrom
fuseiso -n $TMPROOT/CentOS-$MAJOR.$MINOR-$ARCH-netinstall.iso $TMPROOT/cdrom

# create an installation disk; we only need around 1.3G for the installation,
# later to be shrinked down to 300M, but we want to format the disk to
# potentially hold more. On ext3 creating a large file with zeros is inexpensive
kvm-img create \
  -f raw \
  -o size=4G \
  $PREFIX/CentOS-$MAJOR.$MINOR-raw.img

# boot with command-line option; we use no-reboot so that we don't
# start the VM once more with the same init settings as the first time
kvm \
  -name "CentOS" \
  -enable-kvm \
  -m 1G \
  -boot once=d \
  -drive file=$PREFIX/CentOS-$MAJOR.$MINOR-raw.img,if=virtio,index=0,media=disk,format=raw,cache=unsafe \
  -drive file=$TMPROOT/CentOS-$MAJOR.$MINOR-$ARCH-netinstall.iso,index=1,media=cdrom \
  -fda $TMPROOT/ks.img \
  -netdev user,id=hostnet0,hostname=centos$MAJOR -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -kernel $TMPROOT/cdrom/isolinux/vmlinuz \
  -initrd $TMPROOT/cdrom/isolinux/initrd.img \
  -append "serial ks=hd:fd0:/ks.cfg console=ttyS0" \
  -no-reboot

# we don't need installation media anymore
fusermount -u $TMPROOT/cdrom

# boot once more to do first time initialization (which is
# setup to halt automatically)
kvm \
  -name "CentOS" \
  -enable-kvm \
  -m 1G \
  -boot order=c \
  -drive file=$PREFIX/CentOS-$MAJOR.$MINOR-raw.img,if=virtio,index=0,media=disk,format=raw,cache=unsafe \
  -netdev user,id=hostnet0,hostname=centos$MAJOR -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot

# compact installation disk
kvm-img convert \
  -c \
  -f raw -O qcow2 \
  $PREFIX/CentOS-$MAJOR.$MINOR-raw.img \
  $PREFIX/CentOS-$MAJOR.$MINOR-base.img

rm $PREFIX/CentOS-$MAJOR.$MINOR-raw.img

# create an overlay to store further changes on
kvm-img create \
  -b $PREFIX/CentOS-$MAJOR.$MINOR-base.img \
  -f qcow2 \
  $PREFIX/CentOS-$MAJOR.$MINOR.img
  
# boot regular installation
cat > $PREFIX/CentOS-$MAJOR.$MINOR << EOF
#!/bin/sh
exec kvm \
  -name "CentOS" \
  -enable-kvm \
  -m 1G \
  -boot order=c \
  -drive file=\$(dirname \$0)/CentOS-$MAJOR.$MINOR.img,if=virtio,index=0,media=disk,cache=writeback \
  -netdev user,id=hostnet0,hostname=centos$MAJOR -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot
EOF
chmod +x $PREFIX/CentOS-$MAJOR.$MINOR

# clean up temporary directory
rm $TMPROOT/CentOS-$MAJOR.$MINOR-$ARCH-netinstall.iso
rm $TMPROOT/ks.cfg
rm $TMPROOT/ks.img
rmdir $TMPROOT/floppy
rmdir $TMPROOT/cdrom
rmdir $TMPROOT

# use scp to 10.0.2.2 to get/put files to host
