#!/bin/bash

# SSH PermitRoot no
SSHD_CONFIG="/etc/ssh/sshd_config"

if [[ ! -f $SSHD_CONFIG ]]; then
  echo "$SSHD_CONFIG file does not exist." >&2
  exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${SSHD_CONFIG}.bak.${TIMESTAMP}"
cp "$SSHD_CONFIG" "$BACKUP_FILE"

if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
  sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
fi

# Restart sshd service
echo "Restarting sshd service."
systemctl restart sshd
if [[ $? -eq 0 ]]; then
  echo "sshd service restarted successfully."
else
  echo "Failed to restart sshd service. Please check manually." >&2
fi


# Password policy
CONFIG_FILE="/etc/security/pwquality.conf"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${CONFIG_FILE}.bak.${TIMESTAMP}"


if [[ -f "$CONFIG_FILE" ]]; then
  cp "$CONFIG_FILE" "$BACKUP_FILE"
  cat > "$CONFIG_FILE" <<EOL
# Password settings (refer to the description)
lcredit=-1    # Minimum lowercase letters
ucredit=-1    # Minimum uppercase letters
dcredit=-1    # Minimum numbers
ocredit=-1    # Minimum special characters
minlen=8      # Minimum password length
EOL
else
  echo "$CONFIG_FILE does not exist, creating a new one."
fi

# Check results
if [[ $? -eq 0 ]]; then
  echo "$CONFIG_FILE updated successfully."
else
  echo "An error occurred while updating $CONFIG_FILE." >&2
fi

# Faillock setting
FILES=("/etc/pam.d/system-auth" "/etc/pam.d/password-auth")

FAILLOCK_SETTINGS=$(cat << EOF
#%PAM-1.0
# This file is auto-generated.
# User changes will be destroyed the next time authselect is run.

auth        required      pam_env.so
auth        required      pam_faillock.so preauth silent deny=10 unlock_time=120
auth        sufficient    pam_unix.so try_first_pass nullok
auth        required      pam_faillock.so authfail deny=10 unlock_time=120
auth        required      pam_deny.so

account     required      pam_unix.so
account     required      pam_faillock.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password    sufficient    pam_unix.so try_first_pass use_authtok nullok sha512 shadow
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session    optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
EOF
)

for FILE in "${FILES[@]}"; do
  if [[ -f "$FILE" ]]; then
    # Create a backup
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    cp "$FILE" "${FILE}.bak.${TIMESTAMP}"

    # Remove existing pam_tally settings and add pam_faillock
    sed -i '/pam_tally.so/d' "$FILE"
    echo "$FAILLOCK_SETTINGS" >> "$FILE"
    echo "$FILE updated successfully."
  else
    echo "$FILE does not exist." >&2
  fi
done

echo "PAM configuration completed. Restart or re-login to verify the settings."

# Account chage
ACCOUNTS=$(awk -F: '($3 == 0 || $3 >= 500) && $7 != "/sbin/nologin" {print $1}' /etc/passwd)

if [[ -z "$ACCOUNTS" ]]; then
  echo "No accounts matching the conditions were found."
  exit 0
fi

echo "Setting chage -M 90 for the following accounts:"
for ACCOUNT in $ACCOUNTS; do
  echo "Setting for: $ACCOUNT"
  chage -M 90 "$ACCOUNT" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "Successfully set max password usage period to 90 days for $ACCOUNT."
  else
    echo "Failed to set for $ACCOUNT. Check permissions or account status."
  fi
done


# login.defs MAX_DAYS
LOGIN_DEFS_FILE="/etc/login.defs"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${LOGIN_DEFS_FILE}.bak.${TIMESTAMP}"

if [[ -f $LOGIN_DEFS_FILE ]]; then
  cp "$LOGIN_DEFS_FILE" "$BACKUP_FILE"
  if grep -q "^PASS_MAX_DAYS" "$LOGIN_DEFS_FILE"; then
  sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS    90/' "$LOGIN_DEFS_FILE"
  echo "PASS_MAX_DAYS updated to 90."
  else
    echo "PASS_MAX_DAYS    90" >> "$LOGIN_DEFS_FILE"
    echo "PASS_MAX_DAYS setting added."
  fi
else
  echo "$LOGIN_DEFS_FILE does not exist." >&2
fi


# TMOUT 600
PROFILE_FILE="/etc/profile"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${PROFILE_FILE}.bak.${TIMESTAMP}"

TMOUT_SETTING="TMOUT=600"
EXPORT_SETTING="export TMOUT"

# Check if the profile file exists
if [[ -f $PROFILE_FILE ]]; then
  echo "Backing up $PROFILE_FILE to $BACKUP_FILE..."
  cp "$PROFILE_FILE" "$BACKUP_FILE"
  
  echo "Modifying $PROFILE_FILE..."
  
  # Replace or add TMOUT setting
  if grep -q "^TMOUT=" "$PROFILE_FILE"; then
    sed -i "s/^TMOUT=.*/$TMOUT_SETTING/" "$PROFILE_FILE"
    echo "TMOUT updated to $TMOUT_SETTING."
  else
    echo "$TMOUT_SETTING" >> "$PROFILE_FILE"
    echo "TMOUT added: $TMOUT_SETTING."
  fi
  
  # Add export TMOUT if missing
  if ! grep -q "^export TMOUT" "$PROFILE_FILE"; then
    echo "$EXPORT_SETTING" >> "$PROFILE_FILE"
    echo "Added export TMOUT: $EXPORT_SETTING."
  fi

  echo "Modifications to $PROFILE_FILE complete."
else
  echo "$PROFILE_FILE does not exist. Exiting."
fi

# PAM SU
PAM_SU_FILE="/etc/pam.d/su"

if [[ ! -f $PAM_SU_FILE ]]; then
  echo "$PAM_SU_FILE does not exist." >&2
  exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${PAM_SU_FILE}.bak.${TIMESTAMP}"
cp "$PAM_SU_FILE" "$BACKUP_FILE"

# Uncomment specific line
sed -i 's/^#auth[[:space:]]\+required[[:space:]]\+pam_wheel\.so[[:space:]]\+use_uid/auth            required        pam_wheel.so use_uid/' "$PAM_SU_FILE"

if grep -q "^auth[[:space:]]\+required[[:space:]]\+pam_wheel\.so[[:space:]]\+use_uid" "$PAM_SU_FILE"; then
  echo "Successfully uncommented line in: $PAM_SU_FILE"
else
  echo "Failed to uncomment line. Please check $PAM_SU_FILE." >&2
fi

chmod 400 /etc/hosts
chmod 4750 /usr/bin/su
