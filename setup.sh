#!/bin/bash
if [ $(id -u) -ne 0 ]; then
    echo "Please run this command as root."
    exit
fi
clear
if ss -lptn | grep -q :22; then
    true;
else
    echo "Warning: sshd must be running on port 22 for successful "
    echo "remote access. This does not appear to be the current "
    echo "configuration."
    echo
    echo "Press enter to continue or press ctrl+c to exit."
    echo
    read ignored </dev/tty
fi
echo "Welcome to the Securin remote access setup script.        "
echo "This script will configure an outbound connection from    "
echo "this host to Securin servers in order to allow Securin to "
echo "remotely access this host to provide security services.   "
echo
echo "Press enter to continue or press ctrl+c to cancel. "
echo

read ignored </dev/tty

echo "Testing connectivity to Securin servers..."

echo "Testing TCP/145.40.65.195:10503."
BANNER1="$(timeout 5s head -c3 </dev/tcp/145.40.65.195/10503)"
if [ "$BANNER1" = "SSH" ]; then
    echo "Connectivity check TCP/145.40.65.195:10503 passed."
else
    echo "Warning: connectivity check failed."
    echo "Please verify that firewall rules allow outbound access"
    echo "to TCP/145.40.65.195:10503."
    echo
    echo "Press enter to continue or press ctrl+c to cancel. "
    read ignored </dev/tty
fi

echo "Testing TCP/50.216.117.76:443."
BANNER2="$(timeout 5s head -c3 <(openssl s_client -quiet -connect 50.216.117.76:443 -servername connectivity.louisiana.cswsonar.app </dev/null 2>/dev/null) )"
if [ "$BANNER2" = "SSH" ]; then
    echo "Connectivity check TCP/50.216.117.76:443 passed."
else
    echo "Warning: connectivity check failed."
    echo "Please verify that firewall rules allow outbound access"
    echo "to TCP/50.216.117.76:443."
    echo
    echo "Press enter to continue or press ctrl+c to cancel. "
    read ignored </dev/tty
fi


useradd -m -s /bin/bash securin
useradd -m -s /bin/bash callhome
sudo -u callhome ssh-keygen -t ed25519 -f /home/callhome/.ssh/id_ed25519 -P '' >/dev/null 2>/dev/null
sudo -u securin ssh-keygen -t ed25519 -f /home/securin/.ssh/id_ed25519 -P '' >/dev/null 2>/dev/null
sudo -u securin bash -c 'cat /home/securin/.ssh/id_ed25519.pub > /home/securin/.ssh/authorized_keys'
cat >>/home/callhome/.ssh/known_hosts <<EOF
[145.40.65.195]:10503 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIElSlObj/errpMCA9NBA/ab5uklfjPIHjA6uHqQgm8IS
[50.216.117.76]:443 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILbHu9sVc/Dfc9iPFOb4lxgbtIgKVzgH5jvAhCi8Kma/
EOF
chown callhome:callhome /home/callhome/.ssh/known_hosts

my_uuid="$(cat /proc/sys/kernel/random/uuid)"
my_password="$(cat /proc/sys/kernel/random/uuid)"
my_pubkey="$(cat /home/callhome/.ssh/id_ed25519.pub)"
my_privkey="$(cat /home/securin/.ssh/id_ed25519)"

cat >/home/callhome/callhome1.sh <<EOF
#!/bin/bash
while : ; do
      ssh \\
        -R /opt/socketcallhome/socketcallhome/$my_uuid:127.0.0.1:22 \\
        -o ConnectTimeout=60 \\
	-o ServerAliveInterval=30 \\
	-o ServerAliveCountMax=3 \\
	-o ExitOnForwardFailure=yes \\
	-p 10503 \\
	socketcallhome@145.40.65.195
      sleep 20
done
EOF


cat >/home/callhome/callhome2.sh <<EOF
#!/bin/bash
CONNECT_COMMAND="openssl s_client -quiet -connect 50.216.117.76:443 -servername $my_uuid.socketcallhome.louisiana.cswsonar.app"
while : ; do
    ssh -N -v -p 443 \\
        -R /opt/socketcallhome/socketcallhome/$my_uuid:127.0.0.1:22 \\
        -o ConnectTimeout=60 \\
        -o ExitOnForwardFailure=true \\
        -o ServerAliveInterval=30 \\
        -o ServerAliveCountMax=3 \\
        -o ProxyCommand="\$CONNECT_COMMAND" \\
        socketcallhome@50.216.117.76
    sleep 30
done
EOF

chmod +x /home/callhome/callhome1.sh
chmod +x /home/callhome/callhome2.sh

cat >/lib/systemd/system/securincallhome1.service <<EOF
[Unit]
Description=Securin Remote Access Service

[Service]
ExecStart=/home/callhome/callhome1.sh
User=callhome

[Install]
WantedBy=default.target
EOF

cat >/lib/systemd/system/securincallhome2.service <<EOF
[Unit]
Description=Securin Remote Access Service

[Service]
ExecStart=/home/callhome/callhome2.sh
User=callhome

[Install]
WantedBy=default.target
EOF



echo "securin:$my_password" | chpasswd
usermod -a -G sudo securin
systemctl daemon-reload
systemctl enable --now securincallhome1.service
systemctl enable --now securincallhome2.service

package=$(echo -e "$my_uuid\n$my_password\n$my_pubkey\n$my_privkey" | gzip -c | base64);

echo "$package" > /root/securinsetup.txt

echo "Setup is complete. Please send the following value to your"
echo "Securin point of contact to enable us to access this device."
echo
echo "----------"
echo "$package"
echo "----------"
echo
echo "This value has also been stored at /root/securinsetup.txt"
