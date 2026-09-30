# Whyred LineageOS Flashing Guide

Notes:
* This is a FBEv2 ROM with NO way to disable encryption (at least not for now)
* Enforced and encrypted
* With [SukiSU](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
* With [MindTheGapps](https://github.com/MindTheGapps/16.0.0-arm64)
* With [Kernel](https://github.com/user-why-red/android_kernel_xiaomi_sdm660_419)
* With Whyred repos from [NopeNopeGuy](https://github.com/NopeNopeGuy) [Whyred](https://github.com/Bouquet-Dynamic-Development)

## Clean Flash:
1. Download the ROM
2. Flash the dynamic recovery provided (recovery.img is inside the ROM zip). fastboot flash recovery <recovery.img>
3. If fastboot dissapears (it is in waiting for device), you have to connect cable via some usb hub, that will increase electric current.
5. Boot into recovery 
6. Apply Update > Sideload ROM > adb sideload <ROM.zip> (or you can use SD Card)
8. Format DATA (only for first time to enable DATA encryption, for updates it is not needed)
9. Reboot and enjoy!
