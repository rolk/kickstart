#!/bin/bash
# This file is licensed under the GPL version 3 or later.

# <http://doc.opensuse.org/projects/YaST/openSUSE11.3/autoinstall/createprofile.scripts.html>
# <http://en.opensuse.org/SDB:Linuxrc>
# <http://www.novell.com/coolsolutions/assets/autoinst.xml>
# <http://users.suse.com/~ug/autoyast_doc/configuration.html#init.scripts>
# <http://lists.opensuse.org/opensuse-autoinstall/2012-08/msg00033.html>
# <http://www.softpanorama.org/Commercial_linuxes/Suse/Yast/sample_autoinst_file.shtml>

# how are we invoked? needed for giving sensible usage description
INVOKER="$0"
INVOKER=${INVOKER/$HOME/\~}

# error message for missing prerequisite
missing () {
  cat 1>&2 <<EOF

Error: Prerequisite $1 is missing. Install necessary packages with:

  sudo apt-get install wget qemu-kvm qemu-utils

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
VER=13.1
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
          MIRROR=http://ftp.uninett.no/opensuse
          ;;
        uib)
          # undocumented shorthand
          MIRROR=http://opensuse.uib.no
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
for cmd in wget qemu-img qemu-system-${ARCH} dd date; do
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

# check for existing files
if [ "$FORCE" != "yes" ]; then
  if [ -e "$PREFIX/opensuse-$VER" ]; then
    echo Error: File "$PREFIX/opensuse-$VER" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/opensuse-$VER-raw.img" ]; then
    echo Error: File "$PREFIX/opensuse-$VER-raw.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/opensuse-$VER-base.img" ]; then
    echo Error: File "$PREFIX/opensuse-$VER-base.img" already exists!
    exit 1
  fi
  if [ -e "$PREFIX/opensuse-$VER.img" ]; then
    echo Error: File "$PREFIX/opensuse-$VER.img" already exists!
    exit 1
  fi
fi

# download list of mirrors, pick the first
if [ -z "$MIRROR" ]; then
  MIRROR=http://download.opensuse.org
fi
echo Using OpenSuSE mirror at: $MIRROR

# do everything in this directory
TMPROOT=$(mktemp -t -d suse-$VER.XXXXXX)

# download installation image
wget -nv -P "$TMPROOT" $MIRROR/distribution/$VER/repo/oss/boot/$ARCH/loader/initrd
wget -nv -P "$TMPROOT" $MIRROR/distribution/$VER/repo/oss/boot/$ARCH/loader/linux
wget -nv -P "$TMPROOT" $MIRROR/distribution/$VER/iso/openSUSE-$VER-NET-$ARCH.iso

# preseeded configuration to do automated installation
cat > "$TMPROOT/autoinst.xml" <<EOF
<?xml version="1.0"?>
<!DOCTYPE profile>
<profile xmlns="http://www.suse.com/1.0/yast2ns"
         xmlns:config="http://www.suse.com/1.0/configns">
  <bootloader>
    <global>
      <gfxmenu>none</gfxmenu><!-- don't use graphical menu -->
      <os_prober>false</os_prober><!-- probe for foreign OSes -->
      <terminal>serial</terminal>
      <timeout config:type="integer">0</timeout>
    </global>
  </bootloader>
  <deploy_image>
    <image_installation config:type="boolean">false</image_installation>
  </deploy_image>
  <general>
    <mode>
      <confirm config:type="boolean">false</confirm>
	  <final_halt config:type="boolean">true</final_halt><!-- after second stage -->
    </mode>
  </general>
  <login_settings>
    <autologin_user>$USERNAME</autologin_user>
  </login_settings>
  <networking>
    <dhcp_options>
      <dhclient_client_id/>
      <dhclient_hostname_option>AUTO</dhclient_hostname_option>
    </dhcp_options>
    <dns>
      <dhcp_hostname config:type="boolean">true</dhcp_hostname>
      <domain>$DOMAIN</domain>
      <hostname>$HOSTNAME</hostname>
      <resolv_conf_policy>auto</resolv_conf_policy>
      <write_hostname config:type="boolean">false</write_hostname>
    </dns>
    <interfaces config:type="list">
      <interface>
        <bootproto>dhcp4</bootproto>
        <device>eth0</device>
        <name>Ethernet Network Card</name>
        <startmode>auto</startmode>
      </interface>
      <interface>
        <broadcast>127.255.255.255</broadcast>
        <device>lo</device>
        <firewall>no</firewall>
        <ipaddr>127.0.0.1</ipaddr>
        <netmask>255.0.0.0</netmask>
        <network>127.0.0.0</network>
        <prefixlen>8</prefixlen>
        <startmode>auto</startmode>
        <usercontrol>no</usercontrol>
      </interface>
    </interfaces>
    <ipv6 config:type="boolean">false</ipv6>
  </networking>
  <partitioning config:type="list">
    <drive>
      <device>/dev/sda</device>
      <initialize config:type="boolean">true</initialize>
      <partitions config:type="list">
        <partition>
          <create config:type="boolean">true</create>
          <crypt_fs config:type="boolean">false</crypt_fs>
          <filesystem config:type="symbol">ext4</filesystem>
          <format config:type="boolean">true</format>
          <fstopt>noatime,data=writeback,noacl</fstopt>
          <label>openSUSE_$VER</label>
          <loop_fs config:type="boolean">false</loop_fs>
          <mount>/</mount>
          <mountby config:type="symbol">device</mountby>
          <partition_id config:type="integer">131</partition_id><!-- 0x83 -->
          <partition_nr config:type="integer">1</partition_nr>
          <resize config:type="boolean">false</resize>
          <size>auto</size>
        </partition>
      </partitions>
    </drive>
  </partitioning>
  <scripts>
    <init-scripts config:type="list">
      <script>
        <source>
<![CDATA[
# activate serial console when booting
sed -i 's/^\(GRUB_CMDLINE_LINUX\)="\(.*\)"$/\1="console=ttyS0,115200n8 \2"/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

# use real terminal instead of vt102
sed -i 's,^\(ExecStart=-/sbin/agetty\) .*$,\1 --noclear --autologin $USERNAME %I 115200 xterm,' /usr/lib/systemd/system/serial-getty@.service

# prevent systemd-vconsole-setup to garble the remote terminal on initialization
sed -i 's,^\(CONSOLE_SCREENMAP\)="\(.*\)",\1="",' /etc/sysconfig/console

if [ -f /lib/systemd/systemd-vconsole-setup ]; then
  mv /lib/systemd/systemd-vconsole-setup /lib/systemd/systemd-vconsole-setup.orig
  ln -s /bin/true /lib/systemd/systemd-vconsole-setup
fi

if [ -f /usr/lib/systemd/systemd-vconsole-setup ]; then
  mv /usr/lib/systemd/systemd-vconsole-setup /usr/lib/systemd/systemd-vconsole-setup.orig
  ln -s /bin/true /usr/lib/systemd/systemd-vconsole-setup
fi

# disable OOM killer
cat >> /etc/sysctl.conf <<___

# disable out-of-memory-killer
vm.overcommit_memory=2
vm.overcommit_ratio=150
___

# setup sudo access for this user
echo '$USERNAME ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# configure alias to host system
echo -e '10.0.2.2\thost' >> /etc/hosts

# trim away temporarily used blocks in the installation
/sbin/fstrim -v /
]]>
        </source>
      </script>
    </init-scripts>
  </scripts>
  <software>
    <packages config:type="list">
      <package>autoyast2</package>
      <package>crda</package>
      <!--package>cryptsetup-mkinitrd</package-->
      <!--package>grub2-branding-openSUSE</package-->
      <package>kexec-tools</package>
      <package>libnl-1_1</package>
      <!--package>libxslt-tools</package-->
      <package>libxslt1</package>
      <package>wireless-regdb</package>
      <package>xterm</package><!-- for resize utility -->
      <package>yast2-schema</package>
      <package>yast2-trans-en_US</package>
      <!--package>zypper-aptitude</package-->
    </packages>
    <patterns config:type="list">
      <pattern>base</pattern>
      <pattern>enhanced_base</pattern>
      <pattern>sw_management</pattern>
      <pattern>yast2_install_wf</pattern>
    </patterns>
  </software>
  <timezone>
    <hwclock>UTC</hwclock>
    <timezone>$(date +%Z)</timezone>
  </timezone>
  <users config:type="list">
    <user>
      <encrypted config:type="boolean">true</encrypted>
      <user_password>$(echo $PASSWORD | mkpasswd --method=sha-512 --stdin)</user_password>
      <username>root</username>
    </user>
    <user>
      <encrypted config:type="boolean">true</encrypted>
      <user_password>$(echo $PASSWORD | mkpasswd --method=sha-512 --stdin)</user_password>
      <username>$USERNAME</username>
	  <fullname>$FULLNAME</fullname>
    </user>
  </users>
</profile>
EOF

# create an installation disk; we only need around 1.3G for the installation,
# later to be shrinked down to 230M, but we want to format the disk to
# potentially hold more. On ext3 creating a large file with zeros is inexpensive
# unlink old file first to avoid seeking through a potentially large file
rm -f "$PREFIX/opensuse-$VER-raw.img"
dd of=$PREFIX/opensuse-$VER-raw.img bs=4G seek=1 count=0

# use '-boot once=d' and '-drive file=$TMPROOT/mini.iso,index=1,media=cdrom'
# if you are booting the mini.iso image
qemu-system-${ARCH} \
  -name "OpenSuSE $VER" \
  -enable-kvm \
  -m 1G \
  -boot order=c,once=d \
  -drive file=./opensuse-$VER-raw.img,if=none,id=hd0,discard=unmap,media=disk,format=raw,cache=unsafe \
  -drive file="$TMPROOT/openSUSE-$VER-NET-$ARCH.iso",if=none,id=cd0,media=cdrom \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-cd,drive=cd0 \
  -device scsi-hd,drive=hd0 \
  -netdev user,id=hostnet0,hostname=opensuse-$VER,tftp=$TMPROOT,bootfile= \
  -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -kernel "$TMPROOT/linux" \
  -initrd "$TMPROOT/initrd" \
  -append "root=/dev/ram0 install=$MIRROR/distribution/$VER/repo/oss autoyast=tftp://10.0.2.2/autoinst.xml console=ttyS0" \
  -no-reboot

# boot once more to do first time initialization (which is
# setup to halt automatically)
qemu-system-${ARCH} \
  -name "OpenSuSE $VER" \
  -enable-kvm \
  -m 1G \
  -boot order=c \
  -device virtio-scsi-pci \
  -drive file=$PREFIX/opensuse-$VER-raw.img,if=none,id=hd0,discard=unmap,media=disk,format=raw,cache=unsafe \
  -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0 \
  -netdev user,id=hostnet0,hostname=opensuse-$VER -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot

# compact installation disk
qemu-img convert \
  -c \
  -f raw -O qcow2 \
  $PREFIX/opensuse-$VER-raw.img \
  $PREFIX/opensuse-$VER-base.img

rm $PREFIX/opensuse-$VER-raw.img

# create an overlay to store further changes on
qemu-img create \
  -b $PREFIX/opensuse-$VER-base.img \
  -f qcow2 \
  $PREFIX/opensuse-$VER.img

# script to boot regular installation
cat > $PREFIX/opensuse-$VER <<EOF
#!/bin/sh
qemu-system-${ARCH} \
  -name "OpenSuSE $VER" \
  -enable-kvm \
  -m 1G \
  -boot order=c \
  -drive file=$(dirname \$0)/opensuse-$VER.img,if=none,id=hd0,discard=unmap,media=disk,cache=writeback \
  -device virtio-scsi-pci,id=scsi -device scsi-hd,drive=hd0 \
  -netdev user,id=hostnet0,hostname=opensuse-$VER -device virtio-net-pci,romfile=,netdev=hostnet0 \
  -nographic -vga none \
  -balloon virtio \
  -no-reboot
EOF
chmod +x $PREFIX/opensuse-$VER

# clean up temporary directory
rm -rf "$TMPROOT"
