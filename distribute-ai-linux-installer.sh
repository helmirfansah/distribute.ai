#!/bin/sh

set -e

echo ""

INSTALL_DIRECTORY="$HOME/.local/share/distribute.ai"
DESKTOP_FILE_LOCATION="$HOME/.local/share/applications/DistributeAI.desktop"
LOCK_FILE_LOCATION="$INSTALL_DIRECTORY/install.lock"
RELEASES_URL="https://api.distribute.ai/release/latest/runtime"

#RELEASES_URL="http://localhost:8080/release/latest/runtime"

ACTION=
if [ -z $1 ]; then
    ACTION="install"
else
    ACTION=$1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "distribute.ai for linux only runs on x86_64,"
    echo "please switch to a different device to continue."
    exit 1
fi

DOWNLOAD_COMMAND=
if type curl &> /dev/null; then
	DOWNLOAD_COMMAND="curl -fsSL"
elif type wget &> /dev/null; then
	DOWNLOAD_COMMAND="wget -q -O-"
fi

TAR_COMMAND=
if type tar &> /dev/null; then
	TAR_COMMAND="tar"
fi

CAN_ELEVATE=0
SUDO_COMMAND=""
if [ "$(id -u)" = 0 ]; then
	CAN_ELEVATE=1
	SUDO_COMMAND=""
elif type sudo &> /dev/null; then
	CAN_ELEVATE=1
	SUDO_COMMAND="sudo"
elif type doas &> /dev/null; then
	CAN_ELEVATE=1
	SUDO_COMMAND="doas"
fi
if [ "$CAN_ELEVATE" != "1" ]; then
    if [ "$ACTION" = "remove" ]; then
        echo "the distribute.ai uninstaller requires root privileges to proceed."
    else
        echo "the distribute.ai installer requires root privileges to proceed."
    fi
    echo "we couldn't find 'sudo' or 'doas' on your system."
    echo "please run the script as root or configure sudo/doas."
    echo ""
	exit 1
fi

update() {
    mkdir -p "$INSTALL_DIRECTORY"

    if [ -z "$DOWNLOAD_COMMAND" ]; then
        exit 1
    fi
    if [ -z "$TAR_COMMAND" ]; then
        exit 1
    fi

    JQ=
    if type jq &> /dev/null; then
        JQ="jq"
    fi
    if [ -z "$JQ" ]; then
        JQ="./jq"
        $DOWNLOAD_COMMAND https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 >> $JQ
        chmod +x $JQ
    fi

    set +e
    $SUDO_COMMAND systemctl stop distributeai.service
    set -e

    INSTALL_URL=$($DOWNLOAD_COMMAND $RELEASES_URL | $JQ -r '.platforms."linux-x86_64".daemon.url')

    $DOWNLOAD_COMMAND $INSTALL_URL >> $INSTALL_DIRECTORY/release.tar.gz

    $TAR_COMMAND -xf $INSTALL_DIRECTORY/release.tar.gz -C $INSTALL_DIRECTORY

    rm $INSTALL_DIRECTORY/release.tar.gz

    if [ "$JQ" = "./jq" ]; then
        rm ./jq
    fi

    set +e
    RESTART_STATUS=$($SUDO_COMMAND systemctl restart distributeai.service>&1)
    set -e
}

if [ "$ACTION" = "update" ]; then
    mkdir -p "$INSTALL_DIRECTORY"
    if [[ -e "$LOCK_FILE_LOCATION" ]]; then
        echo "Failed to lock the distribute.ai install, another installer is likely using the directory."

        exit 1
    fi
    touch "$LOCK_FILE_LOCATION"

    update

    set +e
    rm "$LOCK_FILE_LOCATION"

    exit 0
fi

if [ "$ACTION" = "remove" ]; then
    echo "distribute.ai uninstaller"
fi

if [ "$ACTION" = "remove" ]; then
    mkdir -p "$INSTALL_DIRECTORY"
    if [[ -e "$LOCK_FILE_LOCATION" ]]; then
        echo "Failed to lock the distribute.ai install, another installer is likely using the directory."

        exit 1
    fi
    touch "$LOCK_FILE_LOCATION"

    echo "disabling system service..."
    set +e

    FAIL_CHECK=0
    $SUDO_COMMAND systemctl disable --now distributeai.service >&1
    FAIL_CHECK=$?
    $SUDO_COMMAND systemctl stop distributeai.service >&1
    FAIL_CHECK=$?

    $SUDO_COMMAND rm $DESKTOP_FILE_LOCATION
    $SUDO_COMMAND rm /usr/local/bin/distributeai-cli
    $SUDO_COMMAND rm -rf $INSTALL_DIRECTORY

    FAIL_CHECK=0
    $SUDO_COMMAND rm /etc/systemd/system/distributeai.service >&1
    FAIL_CHECK=$?
    if [ "$FAIL_CHECK" != "0" ]; then
        echo "almost done,"
        echo "distribute.ai needs to remove it's systemd service to be fully removed"
        echo "please delete a file named \"distributeai.service\" in your systemd units location"
        echo "(usually /etc/systemd/system/)"
        echo "and then run"
        echo ""
        echo "$SUDO_COMMAND systemctl daemon-reload"
        echo ""
        echo "done!"
        echo ""

        exit 0
    fi

    FAIL_CHECK=0
    $SUDO_COMMAND systemctl daemon-reload

    echo ""
    echo "done!"
    echo ""

    exit 0
fi

echo "distribute.ai installer"

if [ -z "$DOWNLOAD_COMMAND" ]; then
    echo "the distribute.ai installer requires a network request command to proceed."
    echo "we couldn't find 'curl' or 'wget' on your system,"
	echo "please install either curl or wget to proceed."
	exit 1
fi

if [ -z "$TAR_COMMAND" ]; then
    echo "the distribute.ai installer requires the tar command to proceed,"
	echo "please install tar to proceed."
	exit 1
fi

echo "testing network connection..."

FAIL_CHECK=0
TEST_OUT=$($DOWNLOAD_COMMAND "$RELEASES_URL" 2>&1) || FAIL_CHECK=$?
if [ "$FAIL_CHECK" != "0" ]; then
	echo "the distribute.ai installer cannot reach $RELEASES_URL"
	echo "please make sure that your machine has internet access."
	echo "output:"
	echo $TEST_OUT
	exit 1
fi

echo "network test succeeded!"

mkdir -p "$INSTALL_DIRECTORY"
if [[ -e "$LOCK_FILE_LOCATION" ]]; then
    echo "Failed to lock the distribute.ai install, another installer is likely using the directory."

    exit 1
fi
touch "$LOCK_FILE_LOCATION"

echo "installing application..."

update

set +e

DESKTOP_FILE="[Desktop Entry]
Type=Application
Name=Distribute.AI
GenericName=distribute.ai
Comment=The distribute.ai Desktop App
Exec=$INSTALL_DIRECTORY/desktop.AppImage
Icon=$INSTALL_DIRECTORY/desktop.png
Terminal=false
Categories=Utility;Application;"

echo "$DESKTOP_FILE" | $SUDO_COMMAND tee $DESKTOP_FILE_LOCATION >> /dev/null 2>&1

sudo mkdir -p /usr/local/bin
FAIL_CHECK=0
sudo ln -s $INSTALL_DIRECTORY/cli /usr/local/bin/distributeai-cli >> /dev/null 2>&1
FAIL_CHECK=$?
if [ "$FAIL_CHECK" != "0" ]; then
    echo ""
    echo "couldn't symlink the $INSTALL_DIRECTORY/cli to /usr/local/bin/distributeai-cli"
    echo "you won't be able to directly run distributeai-cli from the console"
    echo ""
    echo "please do one of the following:"
    echo " 1. manually symlink $INSTALL_DIRECTORY/cli to /usr/local/bin/distributeai-cli"
    echo " 2. add the following line to your shell rc file (ex. ~/.bashrc) :"
    echo "alias distributeai-cli='$INSTALL_DIRECTORY/cli'"
    echo ""
    echo "otherwise, you can directly use the cli by running '$INSTALL_DIRECTORY/cli'"
    echo ""
fi

echo "installing systemd unit..."

SYSTEMD_UNIT="[Unit]
Description=distribute.ai's distributed inference desktop service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIRECTORY/daemon
WorkingDirectory=$INSTALL_DIRECTORY
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target"

FAIL_CHECK=0
echo "$SYSTEMD_UNIT" | $SUDO_COMMAND tee /etc/systemd/system/distributeai.service >> /dev/null 2>&1
FAIL_CHECK=$?
if [ "$FAIL_CHECK" != "0" ]; then
    echo ""
    echo "almost done,"
    echo "distribute.ai needs to enable a systemd service to function correctly"
    echo "we couldn't write to the default systemd service directory, please write:"
    echo ""
    echo "\""
    echo "$SYSTEMD_UNIT"
    echo "\""
    echo ""
    echo "to a file named \"distributeai.service\" to your systemd units location, then run:"
    echo ""
    echo "$SUDO_COMMAND systemctl enable --now distributeai.service"
    echo "$SUDO_COMMAND systemctl start distributeai.service"
    echo ""
    echo "after that, you can launch the desktop app normally to check your status"
    echo ""
    echo "thank you for installing distribute.ai!"
    echo ""
else
    $SUDO_COMMAND systemctl daemon-reload
    $SUDO_COMMAND systemctl enable --now distributeai.service
    $SUDO_COMMAND systemctl start distributeai.service

    echo ""
    echo "you can now launch the desktop app normally to check your status"
    echo ""
    echo "done!"
    echo "thank you for installing distribute.ai!"
    echo ""
fi

rm "$LOCK_FILE_LOCATION"

exit 0
