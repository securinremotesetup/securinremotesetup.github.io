#!/bin/bash
if [ $(id -u) -ne 0 ]; then
    echo "Please run this command as root."
    exit
fi

clear

if [ -e /home/callhome/callhome-neptune.sh ]; then
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

echo "Testing TLS/purple.securin.io:443."
BANNERNEPTUNE="$(timeout 5s head -c 3 <(openssl s_client -verify_return_error -quiet -connect purple.securin.io:443 </dev/null 2>/dev/null) )"
if [ "$BANNERNEPTUNE" = "SSH" ]; then
    echo "Connectivity check TLS/purple.securin.io:443 passed."
else
    echo "Warning: connectivity check to TLS/purple.securin.io:443 failed."
    echo "Please verify that firewall rules allow outbound access"
    echo "to purple.securin.io."
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
purple.securin.io ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGB6OCa+/oIfW7uvjSH9BIopz3cvTEeqQATneECSDg7r
EOF
chown callhome:callhome /home/callhome/.ssh/known_hosts

my_uuid="$(cat /proc/sys/kernel/random/uuid)"
my_password="$(cat /proc/sys/kernel/random/uuid)"
my_pubkey="$(cat /home/callhome/.ssh/id_ed25519.pub)"
my_privkey="$(cat /home/securin/.ssh/id_ed25519)"

cat >/home/callhome/callhome-neptune.sh <<EOF
#!/bin/bash
CONNECT_COMMAND="openssl s_client -verify_return_error -quiet -connect purple.securin.io:443"
while : ; do
    ssh -N -v -p 443 \\
        -R /opt/socketcallhome/socketcallhome/$my_uuid:127.0.0.1:22 \\
        -o ConnectTimeout=60 \\
        -o ExitOnForwardFailure=true \\
        -o ServerAliveInterval=30 \\
        -o ServerAliveCountMax=3 \\
        -o ProxyCommand="\$CONNECT_COMMAND" \\
        socketcallhome@purple.securin.io
    sleep 30
done
EOF

chmod +x /home/callhome/callhome-neptune.sh

cat >/lib/systemd/system/securincallhome-neptune.service <<EOF
[Unit]
Description=Securin Remote Access Service

[Service]
ExecStart=/bin/bash /home/callhome/callhome-neptune.sh
User=callhome

[Install]
WantedBy=default.target
EOF

echo "securin:$my_password" | chpasswd
usermod -a -G sudo securin 2>/dev/null
usermod -a -G wheel securin 2>/dev/null
systemctl daemon-reload
systemctl enable securincallhome-neptune.service 2>/dev/null
systemctl restart securincallhome-neptune.service 2>/dev/null

gpg --import --batch >/dev/null 2>/dev/null <<EOF
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZ/9tuRYJKwYBBAHaRw8BAQdAlygag3aP8mQi1cOeZQoJn2OPZ8g/qyuaFikY
kuBrfHa0N1NlY3VyaW4gUmVtb3RlIFNldHVwIElubmVyIEtleSA8cmVtb3Rlc2V0
dXBAc2VjdXJpbi5pbz6IjgQTFgoANgIbAwIXgBYhBPCAh658S/thKgDf8/Bn26jZ
Zf0HBQJoAZUEBAsJCAcFFQoJCAsEFgIDAQIeBQAKCRDwZ9uo2WX9B8yRAQDfVHY/
G1Tw6oa5vJlP6fUylOuFNjdmKNI4SAPTq4l60QEAvUYsDgMwr9MJo9hJMUyfTBrw
9tBHtNdj/grfT6Bupgu4OARn/225EgorBgEEAZdVAQUBAQdAYud4d0pcv4sb3R7E
Ox4gRovCkQ7U0IGsCszaEXLuZzkDAQgHiHgEGBYKACAWIQTwgIeufEv7YSoA3/Pw
Z9uo2WX9BwUCZ/9tuQIbDAAKCRDwZ9uo2WX9B73FAQDp5O4gObBOBNRQ9M3wkV4+
Xco36jKOWFYSfN5AbEaQXAD/dqNxqGUa09dxvIICMvjVGyFuC+etkeNs37ziDNcI
5AM=
=QImA
-----END PGP PUBLIC KEY BLOCK-----
EOF
gpg --import --batch >/dev/null 2>/dev/null <<EOF
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZ/9siRYJKwYBBAHaRw8BAQdABBOA1xHlwXV711xJo8SPwgsT4NcqR6v99Zg+
J7MVLaG0PFNlY3VyaW4gUmVtb3RlIFNldHVwIE91dGVyIEtleSA8b3V0ZXJyZW1v
dGVzZXR1cEBzZWN1cmluLmlvPoiOBBMWCgA2AhsDAheAFiEE5o7Cq4nXUSawlMzn
d0bgAaaAaj0FAmgBlOYECwkIBwUVCgkICwQWAgMBAh4FAAoJEHdG4AGmgGo93JsA
/iKza08YtuTatzR0FB+8sYnYUENStprF66TGshOoxgLAAQC0qB8GEHRZ3gjupS8V
NVumGp3lJHArRDe2EbEjzZaxC7g4BGf/bIkSCisGAQQBl1UBBQEBB0DbUJziiPeA
kHAr0nl6yKWtIA2f2xH83Jd5WO6mBzxXKwMBCAeIeAQYFgoAIBYhBOaOwquJ11Em
sJTM53dG4AGmgGo9BQJn/2yJAhsMAAoJEHdG4AGmgGo9DWAA/AmWokPV/VlWZMy2
IUzDSBuzE2JmOh+CfA5jObl42DMJAP4hv9R8oeDrpRcX9Fn01OHonSgiRRf+2ipd
UkKc67MRBQ==
=wGoQ
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
