#!/bin/bash

set -e

say() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }
cmd() { "$@" || { err "Command failed: $*"; exit 1; }; }

say "1. Verifying user 'ec2-user' exists..."

if ! id ec2-user &>/dev/null; then
    err "User 'ec2-user' does not exist!"
    exit 1
fi

say "2. Ensuring 'ec2-user' has correct shell..."

CURRENT_SHELL=$(getent passwd ec2-user | cut -d: -f7)
if [[ "$CURRENT_SHELL" != "/bin/bash" ]]; then
    say " → Changing shell to /bin/bash for ec2-user"
    cmd chsh -s /bin/bash ec2-user
else
    say " → Shell already set correctly"
fi

say "3. Creating 'docker' group if it doesn't exist..."
cmd groupadd -f docker

say "4. Adding 'ec2-user' to 'docker' group..."

BEFORE_GROUPS=$(id -nG ec2-user)
cmd usermod -aG docker ec2-user
AFTER_GROUPS=$(id -nG ec2-user)

say " → Groups before: $BEFORE_GROUPS"
say " → Groups after : $AFTER_GROUPS"

say "✅ Completed without errors."

echo -e "\n⚠️  IMPORTANT:"
echo "→ Don't log out immediately."
echo "→ Run: 'newgrp docker' OR reboot the instance to apply group changes."
