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
systemctl enable --now securincallhome1.service 2>/dev/null
systemctl enable --now securincallhome2.service 2>/dev/null

gpg --import --batch >/dev/null 2>/dev/null <<EOF
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZDZ+XRYJKwYBBAHaRw8BAQdAJqtKwrugrVPsaQGuIa4GmO8lyWfnuJGSu9Qo
5P8mjw20FnJlbW90ZXNldHVwQHNlY3VyaW4uaW+IlgQTFggAPhYhBAlGeCXhnDLm
DWkO/v4oabZrs3gaBQJkNn5dAhsDBQkDwmcABQsJCAcCBhUKCQgLAgQWAgMBAh4B
AheAAAoJEP4oabZrs3ga7+AA/RRYLE+TJ46byUK9ClFz+cNH2dPYae7ph1YYLq+u
a4pFAP4m90xUAOYYC6H1sYsC+mdlo4x2VczVo2r0c752dbg4BLg4BGQ2fl0SCisG
AQQBl1UBBQEBB0CN9e8ox3WjBgPr/Ip8RSOqi4h26zEMGflMuUGOXUkERgMBCAeI
eAQYFggAIBYhBAlGeCXhnDLmDWkO/v4oabZrs3gaBQJkNn5dAhsMAAoJEP4oabZr
s3ga4l8A/33E1KJOrz6QmJNoDQrLaUCtnsaU6QXmCsC8MoecMSzJAP9FcESg74uj
X5XKkfXtI3Wj8s4lxwGmcdtiNRykiDe3BA==
=t7Lg
-----END PGP PUBLIC KEY BLOCK-----
EOF
gpg --import --batch >/dev/null 2>/dev/null <<EOF
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZDeQ/hYJKwYBBAHaRw8BAQdADEVGCQUwqZQowfR+ENhfDv6dx2drt5U2Z0wq
hONXxSa0G291dGVycmVtb3Rlc2V0dXBAc2VjdXJpbi5pb4iWBBMWCAA+FiEEGdA8
0RUCu8oAGnMTmMnV2HGaBTgFAmQ3kP4CGwMFCQPCZwAFCwkIBwIGFQoJCAsCBBYC
AwECHgECF4AACgkQmMnV2HGaBTgqXAD/f6ePQ8NbZEWEtv1BgfxLWqCEvsFtAbf3
0sbprSL7Yq8BAIZZ6shid8dlhDtk18/11QBMVoT6gi3JtNy6F7gJjTMKuDgEZDeQ
/hIKKwYBBAGXVQEFAQEHQMo+J4BzBdzWGhBe/el/SaNxpptCBIdDhv8auhSGzvEb
AwEIB4h4BBgWCAAgFiEEGdA80RUCu8oAGnMTmMnV2HGaBTgFAmQ3kP4CGwwACgkQ
mMnV2HGaBTgZVgEA04ywnbkOvJQWKNPBGXct7TJ+vSbfsoBQB7DSLj1YDaQBAIYB
PVJ72JenP8ApjubeD5Ms0hh1AddZOHadl7RpTKgH
=sZzB
-----END PGP PUBLIC KEY BLOCK-----
EOF

inner_package=$(echo -e "my_password\n$my_privkey" | gpg --trust-model=always -e -r 09467825E19C32E60D690EFEFE2869B66BB3781A );

package=$(echo -e "$my_uuid\n$my_pubkey\n$inner_package" | gzip -9 | gpg --trust-model=always -e -a -r 19D03CD11502BBCA001A731398C9D5D8719A0538 );

echo "$package" > /root/securinsetup.txt

sleep 1

echo "Setup is complete. Please send the following value to your"
echo "Securin point of contact to enable Securin to access this device."
echo
echo "$package"
echo
echo "This value has also been stored at /root/securinsetup.txt"
