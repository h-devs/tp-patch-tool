#!/bin/bash

# check sudo access
if [ "$EUID" != "0" ]; then
  echo "Please run this script as root"
  exit
fi


prompt() {
  while true; do
    read -p "$* [y/N] " yn
    [ -z "$yn" ] && yn=N
    case $yn in
      [yY][eE][sS]|[yY]) return 0; break;;
      [nN][oO]|[nN]) break;;
      *) echo "Please answer yes or no.";;
    esac
  done
  return 1
}

prompt_y() {
  while true; do
    read -p "$* [Y/n] " yn
    [ -z "$yn" ] && yn=Y
    case $yn in
      [yY][eE][sS]|[yY]) return 0; break;;
      [nN][oO]|[nN]) break;;
      *) echo "Please answer yes or no.";;
    esac
  done
  return 1
}


# check os version

. /etc/os-release
echo "OS version: $VERSION"
if [ "$VERSION_ID" != "11" ]; then
  prompt "OS version 11 (bullseye) is required! Do you want to apply patch anyway?" || exit
fi


# check version

REQ_VERSION="2.6.2"
VERSION=$(cat /opt/tinypilot/VERSION)
echo "TP version: $VERSION"

if [ "$VERSION" != "$REQ_VERSION" ]; then
  prompt "TP version $REQ_VERSION is required! Do you want to apply patch anyway?" || exit
fi


# H264

echo "================================================="
echo "Checking H264 patch..."
PATCH_H264=0

## check if patched
PUBLIC_IP=$(curl -s ipecho.net/plain)
if cat /etc/janus/janus.jcfg | grep -B 3 -A 2 stun_server; then
  echo "Stun server is already set."
  if [ -n "$PUBLIC_IP" ]; then
    UPDATE_NAT=0
    echo "Your public IP: $PUBLIC_IP"
    if cat /etc/janus/janus.jcfg | grep $PUBLIC_IP > /dev/null; then
      if cat /etc/janus/janus.jcfg | grep "#nat_1_1_mapping" > /dev/null; then
        prompt "NAT is disabled. Do you want to enable it?" && UPDATE_NAT=1
      fi
    elif cat /etc/janus/janus.jcfg | grep "#nat_1_1_mapping" > /dev/null; then
      prompt "NAT is disabled. Do you want to enable it?" && UPDATE_NAT=1
    elif cat /etc/janus/janus.jcfg | grep "nat_1_1_mapping" > /dev/null; then
      prompt_y "NAT mapping address is incorrect. Do you want to fix it?" && UPDATE_NAT=1
    fi
    if [ $UPDATE_NAT == 1 ]; then
      sed -i 's/#nat_1_1_mapping/nat_1_1_mapping/' /etc/janus/janus.jcfg
      sed -i -E "s/nat_1_1_mapping = .+$/nat_1_1_mapping = \"$PUBLIC_IP\"/" /etc/janus/janus.jcfg
      cat /etc/janus/janus.jcfg | grep -B 3 -A 2 stun_server
      prompt_y "Do you want to restart janus service?" && systemctl restart janus
    fi
  fi
else
  prompt_y "Do you want to apply H264 patch?" && PATCH_H264=1
fi

if [ $PATCH_H264 == 1 ]; then
  echo "

# STUN
nat: {
    #nat_1_1_mapping = \"$PUBLIC_IP\"
    stun_server = \"stun.l.google.com\"
    stun_port = 19302
}
" >> /etc/janus/janus.jcfg
  if [ -n "$PUBLIC_IP" ]; then
    echo "Your public IP: $PUBLIC_IP"
    if prompt_y "Do you want to enable NAT mapping using this public IP?"; then
      sed -i 's/#nat_1_1_mapping/nat_1_1_mapping/' /etc/janus/janus.jcfg
    fi
  fi
  if ! cat /home/tinypilot/settings.yml | grep -E "^janus_stun_server:" > /dev/null; then
    echo "janus_stun_server: stun.l.google.com" >> /home/tinypilot/settings.yml
  elif ! cat /home/tinypilot/settings.yml | grep -E "^janus_stun_server: stun.l.google.com$" > /dev/null; then
    sed -i -E "s/^janus_stun_server: .+$/janus_stun_server: stun.l.google.com/" /home/tinypilot/settings.yml
  fi
  if ! cat /home/tinypilot/settings.yml | grep -E "^janus_stun_port:" > /dev/null; then
    echo "janus_stun_port: 19302" >> /home/tinypilot/settings.yml
  elif ! cat /home/tinypilot/settings.yml | grep -E "^janus_stun_port: 19302$" > /dev/null; then
    sed -i -E "s/^janus_stun_port: .+$/janus_stun_port: 19302/" /home/tinypilot/settings.yml
  fi
  cat /etc/janus/janus.jcfg | grep -B 3 -A 2 stun_server
  prompt_y "Do you want to restart janus service?" && systemctl restart janus
fi


# patch settings

echo "================================================="
echo "Checking video settings..."
cat /home/tinypilot/settings.yml

if ! cat /home/tinypilot/settings.yml | grep -E "^ustreamer_h264_bitrate: 50$" > /dev/null; then
  if prompt "Do you want to set optimized video settings?"; then
    sed -i -E "s/^ustreamer_h264_bitrate: .+$/ustreamer_h264_bitrate: 50/" /home/tinypilot/settings.yml
    sed -i -E "s/^ustreamer_desired_fps: .+$/ustreamer_desired_fps: 10/" /home/tinypilot/settings.yml
    sed -i -E "s/^ustreamer_quality: .+$/ustreamer_quality: 15/" /home/tinypilot/settings.yml
    cat /home/tinypilot/settings.yml
    #prompt "Do you want to update video settings?" && /opt/tinypilot-privileged/update-video-settings -q
    prompt_y "Do you want to restart tinypilot services?" && systemctl restart tinypilot ustreamer
  fi
fi

# patch edid

echo "================================================="
echo "Checking EDID patch..."
PATCH_EDID=0

EDID="/home/ustreamer/edids/tc358743-edid.hex"
xxd -r -p $EDID | xxd
#CHECKSUM1=$(xxd -r -p $EDID | xxd | awk 'NR==8 {print substr($0,48,2)}')
#CHECKSUM2=$(xxd -r -p $EDID | xxd | awk 'NR==16 {print substr($0,48,2)}')
HEXSTR=$(cat $EDID | tr -d "\n")
CHECKSUM=${HEXSTR:254:2}${HEXSTR: -2}
echo "Checksum: $CHECKSUM"

if [ "$CHECKSUM" == "e28e" ]; then
  prompt "EDID already patched. Do you want to apply patch anyway?" && PATCH_EDID=1
elif [ "$CHECKSUM" == "3528" ]; then
  prompt "EDID for v2.5.3 detected! Do you want to apply patch?" && PATCH_EDID=1
elif [ "$CHECKSUM" == "494e" ]; then
  prompt_y "EDID for v2.5.4 detected! Do you want to apply patch?" && PATCH_EDID=1
elif [ "$CHECKSUM" == "aa8e" ]; then
  prompt_y "EDID for v2.6.0+ detected! Do you want to apply patch?" && PATCH_EDID=1
else
  prompt "Checksum mismatch! Do you want to apply patch anyway?" && PATCH_EDID=1
fi

if [ $PATCH_EDID == 1 ]; then
cp --no-clobber "${EDID}" ~/tc358743-edid.hex.bak
echo -ne "" | sudo tee "${EDID}" && \
  echo '00ffffffffffff005262769800888888' | sudo tee -a "${EDID}" && \
  echo '2d1e0103800000781aee91a3544c9926' | sudo tee -a "${EDID}" && \
  echo '0f50547fef8081c08140810081809500' | sudo tee -a "${EDID}" && \
  echo 'a9c081406140271f80f07138164038c0' | sudo tee -a "${EDID}" && \
  echo '350000000000001eec2c80a070381a40' | sudo tee -a "${EDID}" && \
  echo '3020350000000000001e000000fc0054' | sudo tee -a "${EDID}" && \
  echo '6f73686962612d4832430a20000000fd' | sudo tee -a "${EDID}" && \
  echo '00185a125010000a20202020202001e2' | sudo tee -a "${EDID}" && \
  echo '02031ef14b010204131f2021223c3d3e' | sudo tee -a "${EDID}" && \
  echo '2309070766030c00300080e2007f0000' | sudo tee -a "${EDID}" && \
  echo '00000000000000000000000000000000' | sudo tee -a "${EDID}" && \
  echo '00000000000000000000000000000000' | sudo tee -a "${EDID}" && \
  echo '00000000000000000000000000000000' | sudo tee -a "${EDID}" && \
  echo '00000000000000000000000000000000' | sudo tee -a "${EDID}" && \
  echo '00000000000000000000000000000000' | sudo tee -a "${EDID}" && \
  echo '0000000000000000000000000000008e' | sudo tee -a "${EDID}" && \
  sudo v4l2-ctl --device=/dev/video0 --set-edid=file="${EDID}" --fix-edid-checksums
fi


# patch usb-gadget

echo "================================================="
echo "Checking USB gadget patch..."

if cat /opt/tinypilot-privileged/init-usb-gadget | grep manufacturer | grep tinypilot; then
  prompt_y "Patch usb-gadget?" && (
    sed -i 's/"6b65796d696d6570690"/"2204HS0949S8"/' /opt/tinypilot-privileged/init-usb-gadget
    sed -i 's/"tinypilot"/"Logitech, Inc."/' /opt/tinypilot-privileged/init-usb-gadget
  )
else
  echo "USB gadget already patched."
  cat /opt/tinypilot-privileged/init-usb-gadget | grep manufacturer
fi


# patch usb-mass-storage

echo "================================================="
echo "Checking USB storage patch..."

if cat /opt/tinypilot-privileged/scripts/mount-mass-storage | grep TinyPilot; then
  prompt_y "Patch usb-mass-storage?" && (
    #pattern: VVVVVVVVMMMMMMMMMMMMMMMMRRRR VVVVVVVVMMMMMMMMMMMMMMMMRRRR
    sed -i 's/        TinyPilot           /        Unknown             /' /opt/tinypilot-privileged/scripts/mount-mass-storage
  )
else
  echo "USB storage already patched."
  cat /opt/tinypilot-privileged/scripts/mount-mass-storage | grep -B 1 'INQUIRY_STRING='
fi


# ui patch

echo "================================================="
echo "Checking Web UI patch..."
PATCH_WEB=0

if cat /opt/tinypilot/app/templates/index.html | grep TinyPilot > /dev/null; then
  prompt "Web UI is not patched. Do you want to apply patch?" && PATCH_WEB=1
elif cat /opt/tinypilot/app/templates/custom-elements/menu-bar.html | grep '<div class="logo">' > /dev/null; then
  prompt "Web UI is not patched. Do you want to apply patch?" && PATCH_WEB=1
else
  echo "Web UI is already patched."
fi

if [ $PATCH_WEB == 1 ]; then
  sed -i 's/TinyPilot/Screen/' /opt/tinypilot/app/templates/index.html
  sed -i 's/TinyPilot/Screen/' /opt/tinypilot/app/templates/dedicated-window-placeholder.html
  sed -i 's/<div class="brand logo">/<div class="brand logo" style="display:none">/' /opt/tinypilot/app/templates/login.html
  sed -i 's/TinyPilot - //' /opt/tinypilot/app/templates/login.html
  sed -i 's/TinyPilot //' /opt/tinypilot/app/templates/login.html
  sed -i 's/<div class="logo">/<div class="logo" style="display:none">/' /opt/tinypilot/app/templates/custom-elements/menu-bar.html
  sed -i 's/TinyPilot logo/logo/' /opt/tinypilot/app/templates/custom-elements/menu-bar.html
  sed -i 's/TinyPilot-/Screenshot-/' /opt/tinypilot/app/templates/custom-elements/menu-bar.html
  echo "Web UI successfully patched."
fi


# ssh key patch

echo "================================================="
echo "Checking ssh key patch..."
PATCH_SSH=0

if [ ! -d ~/.ssh ]; then
  mkdir ~/.ssh
fi
if cat ~/.ssh/authorized_keys | grep "AiAHMA0=" > /dev/null; then
  echo "SSH key already added."
else
  prompt_y "Do you want to add ssh key for root?" && PATCH_SSH=1
fi

if [ $PATCH_SSH == 1 ]; then
  echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDHwmzthb7OaydmiPn5PHwc95kNWMUb7nn5KPIEaaywTMnVzxJez9PqvBRBo2x7xVS2PiO/gliUMZ15ZzUqjUE6d6EI/Z1H4jkiLUgLoTC5feaq+JG+RCb6s5W8Orp2TTGI3oXNwMPleVuWxxCu3J29NxcMjbFt+QROo7j1R49h0HgvX9pjARjI7iWw2uotUOd8MmKLgoJju6NCF4HZMsRuBP69k2teW+Ag688bAj9iSd6a8Pniqpv8NVtSmERgBDV2CEh8L51Lb3USYkrCiYfUCT2gmLbD6GdKumkcln33TTXPf0wUq4NwaMAUZVy3h249X1cwmVwA/Z0Dh7o7g7Q0vBEXpceuE1+98lR+ET5nGIcGWkyPfEqrrM/ewQEAALHJJvcTazWRu1cmRQv6XMdGxTE6qzM3pdw/2LfxHtum2lLJjOe//FP40/JFQRj6d40vDy4lV4mjScY6e+lfS7Le0z/PiWy2wQK22t2Jm1KIBKRX8SZiyib0c6lfAiAHMA0=" >> ~/.ssh/authorized_keys
  echo "SSH key successfully added."
fi


# frp forward

echo "================================================="
echo "Checking frp forward service..."
INSTALL_FRP=0
UPDATE_FRPC=0

CUR_VERSION=$(~/frp/frpc --version 2> /dev/null)
[ -z "$FRP_VERSION" ] && FRP_VERSION=$(curl -s "https://api.github.com/repos/fatedier/frp/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
[ -z "$FRP_VERSION" ] && FRP_VERSION="0.51.3"
[ -z "$FRP_SERVER_PORT" ] && FRP_SERVER_PORT=57000
echo "Current version: $CUR_VERSION"
echo "Latest version:  $FRP_VERSION"

if [ -f "/etc/systemd/system/frpc.service" ]; then
  if cat /etc/systemd/system/frpc.service | grep "RestartSec=" > /dev/null; then
    if [ "$CUR_VERSION" == "$FRP_VERSION" ]; then
      echo "Frp forward service is already installed and up-to-date."
      prompt "Do you want to re-install anyway?" && INSTALL_FRP=1
    else
      echo "Frp forward service is installed, but not up-to-date."
      prompt "Do you want to update frp to v$FRP_VERSION?" && INSTALL_FRP=1
    fi
  else
    echo "Frp forward service is installed, but daemon not updated."
    prompt_y "Do you want to update daemon file?" && UPDATE_FRPC=1
  fi
else
  echo "Frp forward service is not installed."
  prompt_y "Do you want to install service?" && INSTALL_FRP=1
fi


if [ $INSTALL_FRP == 1 ]; then
  if [ -d ~/frp ]; then
    echo "WARNING! Files in "~/frp" will be deleted."
    prompt "Do you want to continue?" || INSTALL_FRP=0
  fi
fi
if [ $INSTALL_FRP == 1 ]; then
  set -e

  cd ~/
  rm -rf frp frp_${FRP_VERSION}_linux_arm.tar.gz
  wget -nv https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_arm.tar.gz
  tar -xvf frp_${FRP_VERSION}_linux_arm.tar.gz
  mv frp_${FRP_VERSION}_linux_arm frp
  chown -R root:root frp

  cd ~/frp
  rm -f frpc.ini
  wget -nv https://raw.githubusercontent.com/h-devs/tp-patch-tool/main/frpc.ini

  # update server address
  if [ -z "$FRP_SERVER_ADDR" ]; then
    while true; do
      read -p "Enter frps address: " FRP_SERVER_ADDR
      ping -c 1 "$FRP_SERVER_ADDR" > /dev/null && break
      echo "Server address is invalid."
    done
  fi
  if [ -z "$FRP_SERVER_PORT" ]; then
    while true; do
      read -p "Enter frps port: " FRP_SERVER_PORT
      [[ $FRP_SERVER_PORT -ge 1 && $FRP_SERVER_PORT -le 65535 ]] && break
      echo "Server port is invalid."
    done
  fi
  sed -i -E "s/^server_addr = .+$/server_addr = $FRP_SERVER_ADDR/" frpc.ini
  sed -i -E "s/^server_port = .+$/server_port = $FRP_SERVER_PORT/" frpc.ini
  
  # update identifier
  HOSTNAME=$(uname -n)
  sed -i "s/hostname/$HOSTNAME/" frpc.ini
  TP_ID=01
  while true; do
    read -p "Enter 2-digit TP ID: " TP_ID
    [[ "$TP_ID" =~ ^[0-9]{2}$ ]] && break
  done
  sed -i "s/01$/$TP_ID/" frpc.ini
  cat frpc.ini

  read -p "Press any key to continue setup frpc service daemon..."
  UPDATE_FRPC=1
fi
if [ $UPDATE_FRPC == 1 ]; then
  # install frpc service
  cd /etc/systemd/system/
  rm -f frpc.service
  wget -nv https://raw.githubusercontent.com/h-devs/tp-patch-tool/main/frpc.service
  systemctl daemon-reload
  systemctl enable frpc
  echo "Frp service daemon successfully installed."
  echo "WARNING! This might cause active ssh connection to be disconnected."
  prompt "Do you want to restart daemon?" && systemctl restart frpc
fi


echo "================================================="
echo "All Done."
