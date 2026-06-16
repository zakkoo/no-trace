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
