#!/bin/bash
if [ $(id -u) -ne 0 ]; then
    echo "Please run this command as root."
    exit
fi

clear

if [ -e /home/callhome/callhome1.sh ]; then
    echo "Securin remote access appears to already be set up."
    echo "Please avoid running this script multiple times on the same host."
    echo
    echo "Please press ctrl+c to exit or press enter to continue (not recommended.)"
    echo
    read ignored </dev/tty
fi

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

echo
echo "Installing..."
sleep 1

useradd -m -s /bin/bash securin
useradd -m -s /bin/bash callhome
if [ ! -e /home/callhome/.ssh/id_ed25519 ]; then
  sudo -u callhome ssh-keygen -t ed25519 -f /home/callhome/.ssh/id_ed25519 -P '' >/dev/null 2>/dev/null
fi;
if [ ! -e /home/securin/.ssh/id_ed25519 ]; then
  sudo -u securin ssh-keygen -t ed25519 -f /home/securin/.ssh/id_ed25519 -P '' >/dev/null 2>/dev/null
fi;
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
systemctl enable --now securincallhome1.service 2>/dev/null
systemctl enable --now securincallhome2.service 2>/dev/null

gpg --import --batch >/dev/null 2>/dev/null <<EOF
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZ/9tuRYJKwYBBAHaRw8BAQdAlygag3aP8mQi1cOeZQoJn2OPZ8g/qyuaFikY
kuBrfHa0N1NlY3VyaW4gUmVtb3RlIFNldHVwIElubmVyIEtleSA8cmVtb3Rlc2V0
dXBAc2VjdXJpbi5pbz6IkwQTFgoAOxYhBPCAh658S/thKgDf8/Bn26jZZf0HBQJn
/225AhsDBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJEPBn26jZZf0HVuUA
/A5Qd/ZPtfpHKMkMtgbS6798OF8x7zPZiod7ZIuxoPoeAP0e/fZAMPUXpG7lvfQ+
zZcI2sV/dxmPeMIpLUYy5uV9Bbg4BGf/bbkSCisGAQQBl1UBBQEBB0Bi53h3Sly/
ixvdHsQ7HiBGi8KRDtTQgawKzNoRcu5nOQMBCAeIeAQYFgoAIBYhBPCAh658S/th
KgDf8/Bn26jZZf0HBQJn/225AhsMAAoJEPBn26jZZf0HvcUBAOnk7iA5sE4E1FD0
zfCRXj5dyjfqMo5YVhJ83kBsRpBcAP92o3GoZRrT13G8ggIy+NUbIW4L562R42zf
vOIM1wjkAw==
=cJQI
-----END PGP PUBLIC KEY BLOCK-----
EOF
gpg --import --batch >/dev/null 2>/dev/null <<EOF
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZ/9siRYJKwYBBAHaRw8BAQdABBOA1xHlwXV711xJo8SPwgsT4NcqR6v99Zg+
J7MVLaG0PFNlY3VyaW4gUmVtb3RlIFNldHVwIE91dGVyIEtleSA8b3V0ZXJyZW1v
dGVzZXR1cEBzZWN1cmluLmlvPoiTBBMWCgA7FiEE5o7Cq4nXUSawlMznd0bgAaaA
aj0FAmf/bIkCGwMFCwkIBwICIgIGFQoJCAsCBBYCAwECHgcCF4AACgkQd0bgAaaA
aj3vuwEAjIefRxVkPNJUpzzIe1U6MDKNv45p7EsVYDIEnsliocMBAOi/UMbySEwV
FNkONF66nTr8LhSxkyzRKVzRVHROTRAMuDgEZ/9siRIKKwYBBAGXVQEFAQEHQNtQ
nOKI94CQcCvSeXrIpa0gDZ/bEfzcl3lY7qYHPFcrAwEIB4h4BBgWCgAgFiEE5o7C
q4nXUSawlMznd0bgAaaAaj0FAmf/bIkCGwwACgkQd0bgAaaAaj0NYAD8CZaiQ9X9
WVZkzLYhTMNIG7MTYmY6H4J8DmM5uXjYMwkA/iG/1Hyh4OulFxf0WfTU4eidKCJF
F/7aKl1SQpzrsxEF
=mp4C
-----END PGP PUBLIC KEY BLOCK-----
EOF

inner_package=$(echo -e "$my_password\n$my_privkey" | gpg --trust-model=always -a -e -r F08087AE7C4BFB612A00DFF3F067DBA8D965FD07 );

package=$(echo -e "$my_uuid\n$my_pubkey\n$inner_package" | gzip -9 | gpg --trust-model=always -e -a -r E68EC2AB89D75126B094CCE77746E001A6806A3D );

echo "$package" > /root/securinsetup.txt

sleep 1

echo "Setup is complete. Please send the following value to your"
echo "Securin point of contact to enable Securin to access this device."
echo
echo "$package"
echo
echo "This value has also been stored at /root/securinsetup.txt"
