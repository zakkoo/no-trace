# mytool-tailsworkflow

Sets up and verifies the BitBoxApp in Tails Persistent Storage.
```
cd ~/Persistent
chmod +x wizard.sh
./wizard.sh
```

```
 echo "--- os-release ---"; cat /etc/os-release; echo "--- /etc/amnesia ---"; ls -la /etc/amnesia 2>&1; echo "--- other ---"; ls /etc | grep -iE 'tails|amnesia|version|lsb'; cat /etc/lsb-release 2>&1
```
amnesia@amnesia:~/Persistent$  echo "--- os-release ---"; cat /etc/os-release; echo "--- /etc/amnesia ---"; ls -la /etc/amnesia 2>&1; echo "--- other ---"; ls /etc | grep -iE 'tails|amnesia|version|lsb'; cat /etc/lsb-release 2>&1
--- os-release ---
NAME="Tails"
ID="tails"
ID_LIKE="debian"
PRETTY_NAME="Tails"
VERSION="7.8.1"
HOME_URL="https://tails.net/"
SUPPORT_URL="https://tails.net/support/"
BUG_REPORT_URL="https://tails.net/doc/first_steps/whisperback/"
TAILS_DISTRIBUTION="unstable"
TAILS_SOURCE_DATE_EPOCH="1780484293"
TAILS_GIT_COMMIT="e40f5a4aefc2c20389aded8facf128be2e010ed6"
TAILS_GIT_TAG="7.8.1"
--- /etc/amnesia ---
total 0
drwxr-xr-x 1 root root   3  3. Jun 10:58 .
drwxr-xr-x 1 root root 740 16. Jun 18:36 ..
--- other ---
amnesia
debian_version
tails
tails-get-network-time.conf
cat: /etc/lsb-release: No such file or directory
