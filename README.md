# mytool-tailsworkflow

A privacy focused workflow for using bitbox on your computer. Leave no traces. Don't trust, verify.

## Prerequisites
- get an usb stick and flash it with [Tails OS](https://tails.net)
- during first setup make sure you configure it with a persistante storage

## The Workflow - Using your bitbox

Every time you want to access your wallet with your bitbox do following

- boot tails os
- connect to the tor network
- Download *wizard.sh* into *~/Persistent/wizard.sh*, if not already there
- Open the terminal and enter following commands.

```
cd ~/Persistent
chmod +x wizard.sh
./wizard.sh
```

- Go through the wizard step by step and make sure to read every instruction carefuly. Especially the last step where it tells you to enable tor network in the bitbox app
- hodl

### Troubleshoot
In case you have any connectivity issues with your bitbox, just restart the app by double click it from the file system in persistent/something.appimage

## mannually - the alternative workflow
everything the script does you can do it by hand. just follow these steps:
- make sure no devices blabla
- boot tails os
- connect...