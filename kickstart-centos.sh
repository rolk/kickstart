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

Error: Prerequisite $1 is missing. Install necessary packages with:

  sudo apt-get install wget qemu python-pykickstart

EOF
  exit 1
}

# error message for too old QEmu version
qemuver () {
   cat 1>&2 <<EOF

Error: Expecting QEmu version >= 1.5 (current = $1.$2). Consider:

   sudo add-apt-repository cloud-archive:icehouse
   sudo apt-get update
   sudo apt-get upgrade qemu

EOF
  exit 2
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

# default settings
PREFIX=$(pwd)
MIRROR=
EPEL=
VER=5.10
ARCH=$(uname -m)
USERNAME=user
PASSWORD=
FORCE=no
KERNELORG=http://www.kernel.org
SYSLINUX=syslinux-6.02

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
          MIRROR=http://ftp.uninett.no/pub/linux/centos
          EPEL=http://ftp.uninett.no/linux/epel
          KERNELORG=http://linux-kernel.uio.no
          ;;
        uib)
          # undocumented shorthand
          MIRROR=http://fedora.uib.no/centos
          EPEL=http://fedora.uib.no/epel
          KERNELORG=http://linux-kernel.uio.no
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
for cmd in wget ksvalidator dd qemu-img qemu-system-${ARCH}; do
  if [ ! -x "$(command -v $cmd)" ]; then
    missing $cmd
  fi
done

# check version of QEmu
read qemu_major qemu_minor < <(
  qemu-system-${ARCH} -version |
  sed -n "s/^.*version \([0-9]\)\.\([0-9]\).*$/\1 \2/p")

if [ $qemu_major -eq 1 -a $qemu_minor -lt 5 ]; then
  qemuver $qemu_major $qemu_minor
fi

# error handling: bail out if anything goes wrong
set -e

# some places (mirror urls notably) need only major version
MAJOR=$(echo $VER | cut -f 1 -d.)

# check for existing files
if [ "$FORCE" != "yes" ]; then
  if [ -e "$PREFIX/centos-$VER" ]; then
    echo Error: File "$PREFIX/centos-$VER" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/centos-$VER-raw.img" ]; then
    echo Error: File "$PREFIX/centos-$VER-raw.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/centos-$VER-base.img" ]; then
    echo Error: File "$PREFIX/centos-$VER-base.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/centos-$VER.img" ]; then
    echo Error: File "$PREFIX/centos-$VER.img" already exists!
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
else
  # check if we have to use beta/
  if ! wget -q -O /dev/null $EPEL/$MAJOR/$ARCH/repodata/repomd.xml; then
    if wget -q -O /dev/null $EPEL/beta/$MAJOR/$ARCH/repodata/repomd.xml; then
      EPEL=$EPEL/beta
    else
      EPEL=""
    fi
  fi
fi
echo Using EPEL mirror at: $EPEL

# do everything in this directory
TMPROOT=$(mktemp -t -d centos-${VER/./_}.XXXXXX)

# download the kernel and initial ramdisk for network booting
wget -nv -P "$TMPROOT" $MIRROR/$VER/os/$ARCH/images/pxeboot/vmlinuz
wget -nv -P "$TMPROOT" $MIRROR/$VER/os/$ARCH/images/pxeboot/initrd.img
wget -nv -P "$TMPROOT" $KERNELORG/pub/linux/utils/boot/syslinux/$SYSLINUX.tar.xz

# get the boot file from the disk image
tar xf "$TMPROOT/$SYSLINUX.tar.xz" -C "$TMPROOT" $SYSLINUX/bios/core/pxelinux.0 --strip-components=3
tar xf "$TMPROOT/$SYSLINUX.tar.xz" -C "$TMPROOT" $SYSLINUX/bios/com32/elflink/ldlinux/ldlinux.c32 --strip-components=5

# kickstart file also goes in root directory of TFTP server
cat > $TMPROOT/ks.cfg <<EOF
# don't use graphical install
#text
cmdline

# start the installation process
install

# installation media
#cdrom
# use network install
url --url=$MIRROR/$VER/os/$ARCH

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
bootloader --location=mbr --driveorder=$([ $MAJOR -le 5 ] && echo vda || echo sda)

# clear the Master Boot Record
zerombr

# this directive clears all volumes on the sda hard drive. If it hasn’t been used
# before, --initlabel initializes that drive. sda is used instead of vda since we
# are using the virtio-SCSI driver in kvm
clearpart --all --drives=$([ $MAJOR -le 5 ] && echo vda || echo sda) --initlabel

# use one partition for system and data (and no swap)
part /boot --fstype=ext3 --size=96
part / --fstype=ext3 --size=1 --grow --label=centos_$VER

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
$([ $MAJOR -le 6 ] && echo mingetty)
epel-release
# needed for resize program used to set console size
xterm
# needed to clear the virtual disk efficiently
$([ $MAJOR -le 5 ] && echo zerofree || echo util-linux-ng)
# if you want to switch to GUI mode, you have to install the following packages
#@ basic-desktop
#@ desktop-platform
#@ x11
#@ fonts
$([ $MAJOR -ge 6 ] && echo %end)

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

# RHEL7 uses GRUB2, which can be configured with /etc/default/grub
if [ $(echo $MAJOR) -le 6 ] ; then
  # don't wait to select OS in bootloader
  sed -i 's,\(timeout\)=\(.*\),\1=0,' /boot/grub/grub.conf

  # only probe for serial terminal upon boot
  sed -i 's,\(terminal --timeout\)=\(.*\) serial console,\1=0 serial,' /boot/grub/grub.conf

  # specify kernel parameters; later versions let us use the --append option
  # to the bootloader command with quotation
  sed -i 's,^\(\tkernel.*\),\1 clocksource=kvm-clock clocksource_failover=acpi_pm,' /boot/grub/grub.conf

else

  # don't wait to select OS in bootloader
  sed -i 's,\(GRUB_TIMEOUT\)=\(.*\),\1=0,' /etc/default/grub

  # only probe for serial terminal upon boot
  sed -i 's,\(GRUB_TERMINAL\)=\".*\",\1=\"serial\",' /etc/default/grub

  # specify kernel parameters; later versions let us use the --append option
  # to the bootloader command with quotation
  sed -i 's,\(GRUB_CMDLINE_LINUX\)=\"\(.*\)\",\1="\2 clocksource=kvm-clock clocksource_failover=acpi_pm",' /etc/default/grub

  /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
fi

# autologin on the virtual terminal; CentOS 7 uses systemd, CentOS 6 uses
# Upstart which has /etc/init/serial.conf, CentOS 5 uses SYSV with /etc/inittab
if test -d /etc/systemd/system/getty.target.wants ; then
  ln -s /usr/lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@ttyS0.service
  mkdir -p /etc/systemd/system/getty@ttyS0.service.d/
  cat > /etc/systemd/system/getty@ttyS0.service.d/autologin.conf <<___
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear --autologin $USERNAME %I 115200 xterm
___
else
  if test -f /etc/init/serial.conf ; then
    sed -i 's,exec /sbin/agetty /dev/\\\$DEV \\\$SPEED vt100-nav,exec /sbin/mingetty --noclear --autologin $USERNAME \\\$DEV,' /etc/init/serial.conf;
  else
    # make sure Kudzu has run so it doesn't overwrite /etc/inittab afterwards
    /sbin/kudzu -s -q
    sed -i 's,/sbin/agetty \(ttyS[0-9]\).*,/sbin/mingetty --noclear --autologin $USERNAME \1,' /etc/inittab;
  fi
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
vm.oom-kill=0
___

# configure alias to host system
echo -e '10.0.2.2\tdom0' >> /etc/hosts

## make sure that console change when window resizes
#cat > /etc/profile.d/serial.sh <<___
#if [ \\\$(tty) == "/dev/ttyS0" ]; then
#  trap '[ "\\\$(tty)" = "/dev/ttyS0" ] && eval "\\\$(resize)"' DEBUG
#fi
#___

# correct for bug in nash builtin stabilized
#sed -i 's,\(emit \"stabilized --hash --interval\) \([0-9]*\) \(/proc/scsi/scsi\),\1 1 \3,' /sbin/mkinitrd

# RHEL5 needs to run zerofree before the partitions are mounted read-write;
# later versions have fstrim, which can be run from rc.local instead
if [ $(echo $MAJOR) -le 5 ] ; then
  # zero out unused blocks before the filesystem is mounted
  # notice the quoting of newlines necessary for the sed script
  # to be correct output from the post-install script
  sed -i '/^\# Remount the root filesystem read-write\./i\\\

\#FIRSTBOOT_START\#\\
\# clear unused filesystem blocks\\
action "Sparsify /dev/sda1" /usr/sbin/zerofree /dev/sda1\\
action "Sparsify /dev/sda2" /usr/sbin/zerofree /dev/sda2\\
\#FIRSTBOOT_END\#\\
' /etc/rc.d/rc.sysinit
fi

# do this one the first boot; the section is removed afterwards
/bin/cat >> /etc/rc.d/rc.local <<___
#FIRSTBOOT_START#
# clean up after our initialization
$([ $MAJOR -le 5 ] && echo /bin/sed -i '/^\#FIRSTBOOT_START\#/,/^\#FIRSTBOOT_END\#/d' /etc/rc.d/rc.sysinit)
$([ $MAJOR -ge 6 ] && echo /sbin/fstrim -v /boot )
$([ $MAJOR -ge 6 ] && echo /sbin/fstrim -v / )
# return to console for disk compaction
/bin/sed -i '/^\#FIRSTBOOT_START\#/,/^\#FIRSTBOOT_END\#/d' /etc/rc.d/rc.local ; /sbin/shutdown -h now
#FIRSTBOOT_END#
___
chmod +x /etc/rc.d/rc.local
$([ $MAJOR -ge 6 ] && echo %end)
EOF

# check input file
#    yum install pykickstart
#    ksvalidator -v RHEL6 ks.cfg

# check that we haven't made any errors in the above ks.cfg file
if [ $(ksvalidator -l | grep -c RHEL$MAJOR) -gt 0 ] ; then
  ksvalidator -v RHEL$MAJOR $TMPROOT/ks.cfg
fi

# decompress the initial ram disk, add the kickstart and then compress again
# note: must use -9, or the image become so large it cannot be loaded!
pushd "$TMPROOT"
if [ $MAJOR -le 5 ] ; then
  COMPRESSOR="gzip"
  COMP_OPT=""
else
  COMPRESSOR="xz"
  COMP_OPT="--format=lzma -9"
fi
$COMPRESSOR -d -S .img -f initrd.img
echo ks.cfg | cpio -oA -F initrd -H newc -R root:root
$COMPRESSOR $COMP_OPT -S .img initrd
popd

# boot file
mkdir -p "$TMPROOT/pxelinux.cfg"
cat > "$TMPROOT/pxelinux.cfg/default" <<EOF
serial 0 115200
console 0
default auto
label auto
kernel vmlinuz
append $([ $MAJOR -lt 7 ] && echo serial) ks=file:/ks.cfg console=ttyS0 initrd=/initrd.img
EOF

# create an installation disk; we only need around 1.3G for the installation,
# later to be shrinked down to 300M, but we want to format the disk to
# potentially hold more. On ext3 creating a large file with zeros is inexpensive
# unlink old file first to avoid seeking through a potentially large file
rm -f "$PREFIX/centos-$VER-raw.img"
dd of=$PREFIX/centos-$VER-raw.img bs=4G seek=1 count=0

# boot with command-line option; we use no-reboot so that we don't
# start the VM once more with the same init settings as the first time
# RHEL7 will die with some obscure firewall config error if not given
# enough memory in setup process
qemu-system-${ARCH} \
  -name "CentOS" \
  -enable-kvm \
  -m $([ $MAJOR -ge 7 ] && echo 2G || echo 1G)\
  -boot once=n \
  -drive file=$PREFIX/centos-$VER-raw.img,$([ $MAJOR -le 5 ] && echo if=virtio,index=0 || echo if=none,id=hd0,discard=unmap),media=disk,format=raw,cache=unsafe \
  $([ $MAJOR -ge 6 ] && echo -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0) \
  -netdev user,id=hostnet0,hostname=centos$MAJOR,tftp=$TMPROOT,bootfile=pxelinux.0 \
  -device virtio-net-pci,romfile=pxe-virtio.rom,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot

# boot once more to do first time initialization (which is
# setup to halt automatically)
qemu-system-${ARCH} \
  -name "CentOS" \
  -enable-kvm \
  -m 1G \
  -boot order=c \
  -device virtio-scsi-pci \
  -drive file=$PREFIX/centos-$VER-raw.img,$([ $MAJOR -le 5 ] && echo if=virtio,index=0 || echo if=none,id=hd0,discard=unmap),media=disk,format=raw,cache=unsafe \
  $([ $MAJOR -ge 6 ] && echo -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0) \
  -netdev user,id=hostnet0,hostname=centos$MAJOR -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot

# compact installation disk
qemu-img convert \
  -c \
  -f raw -O qcow2 \
  $PREFIX/centos-$VER-raw.img \
  $PREFIX/centos-$VER-base.img

rm $PREFIX/centos-$VER-raw.img

# create an overlay to store further changes on
qemu-img create \
  -b $PREFIX/centos-$VER-base.img \
  -f qcow2 \
  $PREFIX/centos-$VER.img
  
# boot regular installation
cat > $PREFIX/centos-$VER << EOF
#!/bin/sh
exec qemu-system-${ARCH} \
  -name "CentOS" \
  -enable-kvm \
  -m 1G \
  -boot order=c \
  -drive file=\$(dirname \$0)/centos-$VER.img,$([ $MAJOR -le 5 ] && echo if=virtio,index=0 || echo if=none,id=hd0,discard=unmap),media=disk,cache=writeback \
  $([ $MAJOR -ge 6 ] && echo -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0) \
  -netdev user,id=hostnet0,hostname=centos$MAJOR -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot
EOF
chmod +x $PREFIX/centos-$VER

# clean up temporary directory
rm $TMPROOT/vmlinuz $TMPROOT/initrd.img $TMPROOT/ks.cfg
rm $TMPROOT/pxelinux.0 $TMPROOT/ldlinux.c32 $TMPROOT/$SYSLINUX.tar.xz
rm -rf $TMPROOT/pxelinux.cfg
rmdir $TMPROOT

# use scp to 10.0.2.2 to get/put files to host
