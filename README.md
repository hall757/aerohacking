# Aerohacking

- Randy Hall
- Oct 26, 2021

## The hardware: HiveAP230

The [AP121](https://openwrt.org/toh/aerohive/aerohive_ap121) and [AP330](https://openwrt.org/toh/hwdata/aerohive/aerohive_hiveap-330) have had support for [OpenWRT](https://openwrt.org/) since 2017.  These APs are quite long in the tooth by now.  I wanted to play with something a little newer so I grabbed an [AP230](http://en.techinfodepot.shoutwiki.com/wiki/Aerohive_AP230) off ebay.  I would guess this procedure would work with all of their devices if they have a serial console port.  I can confirm that this works for the AP122 & AP245x. Running OpenWRT isn't the goal here, but if it were, getting root on the device to probe it's inner workings would be high on the list of things to do in preparation of that.  

## Upgrading the firmware

[Extreme Networks](https://www.extremenetworks.com/) do not make the firmware images available to the general public.  You need to be a customer with a support contract before you can download them from the support portal.  You can sign up for a [trial of their cloud based management console](https://www.extremenetworks.com/cloud-networking/).  Even with that, you cannot get the images.  You can only connect a device to the cloud and tell the console to upgrade the firmware.  The console tells the AP to do an upgrade and the AP downloads the image directly from a password protected location.  I won't go into all the details, but here is a hint.

```bash
# Sign up for trial, setup squid to to handle transparent SSL and log all headers.
# Upgrade an AP and monitor all SSL headers between AP and cloud.
# Once you find the token, use with curl and download the images.
curl -h "Authorization: Basic INSERT_YOUR_MAGIC_CREDENTIALS_HERE"  \
 -o "AP230-10.0r9b.img.S" \
 "https://va.extremecloudiq.com:443/afs-webapp/hiveos/images/AP230-10.0r9b.img.S"
# Don't ask for the password, I will ignore you.
```

There were three reasons reasons I upgraded the firmware.

1. Simply state that these instructions should work for anything up to  HiveOS 10.0r9b
2. To have three different versions on hand to recover if and when I broke my device.
3. Just to see if I could.

## Digging in

After upgraded, I attached a serial console and booted up the AP to see what can be gotten from the console output.  Here are the goods from my AP230.

```
Loading kernel from device 0: nand0 (offset 0xa80000) ... done
Loading rootfs from device 0: nand0 (offset 0x3780000) ... done
## Booting kernel from Legacy Image at 01005000 ...
   Image Name:   Linux-3.16.36
   Image Type:   ARM Linux Kernel Image (uncompressed)
   Data Size:    2582421 Bytes = 2.5 MiB
   Load Address: 80008000
   Entry Point:  80008000
   Verifying Checksum ... OK
## Loading init Ramdisk from Legacy Image at 02005000 ...
   Image Name:   uboot initramfs rootfs
   Image Type:   ARM Linux RAMDisk Image (uncompressed)
   Data Size:    28737536 Bytes = 27.4 MiB
   Load Address: 00000000
   Entry Point:  00000000
   Verifying Checksum ... OK 
```
This tells me the kernel is stored in nand starting at 0xa80000 with a length of 2582421 (0x276795, but I rounded up to 0x300000) that gets loaded in ram at 0x01005000.  The ramdisk starts at 0x3780000 with a length of 28737536 (0x1B68000) loaded at 0x02005000.

Depending on which partition was active, it could have produced the address.

```
Loading kernel from device 0: nand0 (offset 0x580000) ... done
Loading rootfs from device 0: nand0 (offset 0xf80000) ... done
```

With that, reboot the AP and hit enter to interrupt the boot process. A password prompt comes up.  A quick search yields either ```administrator``` or ```AhNf?d@ta06``` as the uboot password.  The old AP330 was the former and this AP230 was the later.

The trick i used to get into the AP330 was to simply change the bootargs and include ```init=/bin/sh```.  Ths no longer works.  The kernel ignores any attempt to change them.  This needed a more aggressive approach.

## Grabbing the ramdisk

I have the downloaded firmware image.  Should I start there?  Heck no.

Don't even bother trying to extract anything from the official firmware files.  They are encrypted and it's easier to let the AP do the work.  We are going to grab the ramdisk right out of NAND.

### First test
Can we boot the normal image manually from uboot?  When you interrupt eboot, the variables in the uboot environment are not set to correctly boot the image.  We will use the addresses from the boot sequence to replicate this. 

- Be careful with all these addresses.  Your device may have different values and you need to make the appropriate changes throughout.  
- Nothing is permanent until the step where we write our changes to NAND.
- The hex numbers on the read commands are (RAM location) (NAND start) (NAND length).  It's ok for the length to be too long.
- The hex numbers for bootm are (kernel RAM location) (initrd RAM location).

```shell
# in u-boot console AhNf?d@ta06
# load the kernel AP230
  nand read 0x1005000 0xa80000 0x300000
# nand read 0x1005000 0x580000 0x300000 # alt location
# load the kernel AP245x & AP122
# nand read 0x1005000 0xf00000 0x300000
# nand read 0x1005000 0x800000 0x300000 # alt location

# load the initramdisk AP230
  nand read 0x2005000 0x3780000 0x1C00000
# nand read 0x2005000  0xf80000 0x1C00000 # alt location
# load the initramdisk AP245x & AP122
# nand read 0x2005000 0x3e00000 0x1F00000
# nand read 0x2005000 0x1600000 0x1F00000 # alt location

# startup the system AP230 & AP245x
  bootm 0x1005000 0x2005000 
```
### That worked, lets rip the ramdisk
For this to work, you need a tftp server.  I'm using [pfsense](https://www.pfsense.org/) for my router which has a TFTP server package.  After installing the package, I create a zero byte file on the pfsense box to accept the upload.  This implemnetation of pfsense only allows uploads to pre-existing files.
```bash
# on the pfsense shell
# create empty file
touch /tftpboot/AP230-10.0r9b.initramfs.uImage.00
# make world readable
chmod 666 /tftpboot/AP230-10.0r9b.initramfs.uImage.00
```
### Transfer the image

Back to the AP.  Reset and get to the uboot prompt. 

```bash
# in u-boot console AhNf?d@ta06
# get an IP address
  dhcp
# set to YOUR TFTP server
  setenv serverip 192.168.1.0
# read initramdisk, use your appropriate values
  nand read 0x2005000 0x3780000 0x1C00000 # AP230
# nand read 0x2005000 0x3e00000 0x1F00000 # AP245x & AP122
# send memory block to TFTP
  tftpput  AP230-10.0r9b.initramfs.uImage 0x2005000 0x1C00000 # AP230
# tftpput AP245x-10.0r9b.initramfs.uImage 0x2005000 0x1f00000 # AP245x
# tftpput  AP122-10.0r9b.initramfs.uImage 0x2005000 0x1f00000 # AP122
```
### Modify the initial ramdisk
Download the image to a linux machine with squashfs tools.  
Use the make_initrd script to expand, patch and rebuild the image.

### Make some changes to the files. 

I patch etc2/init.d/rcS just before the init startup section.  It's a minimal approach that lets me into the box after boot and provides a hook linked to the persistant storage for future changes (like adding ssh keys) without needing to rebuild a new initramfs.  The above script will apply all diff files in the same directory as the script.  

To use, put a script named ```/f/startup.sh```.  It will run on boot up.  This does not work on the AP122 & AP245x because the mount is done much later.  For this platform, name the file ```/f/startup2.sh```.

To lockdown the console after you add your ssh keys, make your script delete the ```/tmp/ah_bringup``` file.

The patches are name rcS.diff & ah_startup.diff 

### Test the modified image

This ensures all works before we write the image back to NAND.

Reboot the AP back to uboot

```sh
# in u-boot console AhNf?d@ta06
# get an IP address
dhcp
# set to YOUR TFTP server
setenv serverip 192.168.1.0
# load kernel, use your appropriate values
nand read 0x1005000 0xa80000 0x300000
# load initramfs from TFTP server
tftpboot 0x2005000 AP230-10.0r9b.new.initramfs.uImage
# start the system
bootm 0x1005000 0x2005000 
```
- From the serial console, login is root with no password.
- Do whatever you want to do to verify it works
### Make the changes permanent
You guessed it, reboot the AP to uboot
```sh
# in u-boot console AhNf?d@ta06
# get an IP address
dhcp
# set to YOUR TFTP server
setenv serverip 192.168.1.0
# load initramfs from TFTP server
  tftpboot 0x2005000 AP230-10.0r9b.new.initramfs.uImage
# tftpboot 0x2005000 AP245x-10.0r9b.new.initramfs.uImage
# write to NAND, use your appropriate values
# the tftpboot will show the file size.  Mine was 0x1b68040.  The max size is 0x2800000.
  nand erase 0xf80000 0x1b68040 # AP230
  nand write 0x2005000 0xf80000 0x1b68040 #AP230
# nand erase 0x3e00000 0x1e38040 # AP245x
# nand write 0x2005000 0x3e00000 0x1e38040 # AP245x
# test your work, remember that "boot" won't work because the env is not setup correctly on this device.
reset
```
Enjoy.  

### Summary of addresses

These are the observed values from each device running HiveOS 10.0r9b

| Product | Kernel RAM start | Kernel length | Kernel NAND 1 start | Kernel NAND 2 start | Initrd RAM start | Initrd length | Initrd NAND 1 start | Initrd NAND 2 start |
| :-----: | :--------------: | :-----------: | :-----------------: | :-----------------: | :--------------: | :-----------: | :-----------------: | :-----------------: |
|  AP230  |    0x1005000     |   0x276795    |      0x580000       |      0xa80000       |    0x2005000     |   0x1B68000   |      0xf80000       |      0x3780000      |
|  AP122  |    0x1005000     |   0x251756    |      0x800000       |      0xF00000       |    0x2005000     |   0x1A72000   |      0x1600000      |      0x3e00000      |
| AP245x  |    0x1005000     |   0x25E8D1    |      0x800000       |      0xF00000       |    0x2005000     |   0x1E38000   |      0x1600000      |      0x3e00000      |

###### MTD layout for AP230

Dumped from /proc/mtd after root was obtained.  Added to the table is the offset from the begining of MTD as well as the location & max size for each kernel and initrd.

| Device |        Offset |          Size | Erase Size | Name             |
| -----: | ------------: | ------------: | ---------: | ---------------- |
|   mtd0 |           0x0 |      0x400000 |    0x20000 | Uboot            |
|   mtd1 |      0x400000 |       0x40000 |    0x20000 | Uboot Env        |
|   mtd2 |      0x440000 |       0x40000 |    0x20000 | nvram            |
|   mtd3 |      0x480000 |       0x60000 |    0x20000 | Boot Info        |
|   mtd4 |      0x480000 |       0x60000 |    0x20000 | Static Boot Info |
|   mtd5 |      0x540000 |       0x40000 |    0x20000 | Hardware Info    |
|   mtd6 |      0x580000 |      0xa00000 |    0x20000 | Kernel           |
|        |  **0x580000** |  **0x500000** |    0x20000 | **Kernel 1**     |
|        |  **0xa80000** |  **0x500000** |    0x20000 | **Kernel 2**     |
|   mtd7 |      0xf80000 |     0x5000000 |    0x20000 | App Image        |
|        |  **0xf80000** | **0x2800000** |    0x20000 | **Initrd 1**     |
|        | **0x3780000** | **0x2800000** |    0x20000 | **Initrd 2**     |
|   mtd8 |     0x5f80000 |    0x1a080000 |    0x20000 | JFFS2            |

###### MTD layout for AP245x

Dumped from /proc/mtd after root was obtained.  Added to the table is the offset from the begining of MTD as well as the location & max size for each kernel and initrd.

| Device |        Offset |          Size | Erase Size | Name             |
| :----: | ------------: | ------------: | ---------: | ---------------- |
|  mtd0  |           0x0 |      0x400000 |    0x20000 | Uboot            |
|  mtd1  |      0x400000 |      0x200000 |    0x20000 | shmoo            |
|  mtd2  |      0x600000 |      0x100000 |    0x20000 | Hardware Info    |
|  mtd3  |      0x700000 |      0x100000 |    0x20000 | nvram            |
|  mtd4  |      0x800000 |      0xe00000 |    0x20000 | Kernel Image     |
|        |  **0x800000** |  **0x700000** |    0x20000 | **Kernel 1**     |
|        |  **0xF00000** |  **0x700000** |    0x20000 | **Kernel 2**     |
|  mtd5  |     0x1600000 |     0x5000000 |    0x20000 | App Image        |
|        | **0x1600000** | **0x2800000** |    0x20000 | **Initrd 1**     |
|        | **0x3e00000** | **0x2800000** |    0x20000 | **Initrd 2**     |
|  mtd6  |     0x6600000 |      0x100000 |    0x20000 | Uboot Env        |
|  mtd7  |     0x6700000 |      0x100000 |    0x20000 | Boot Info        |
|  mtd8  |     0x6800000 |      0x100000 |    0x20000 | Static Boot Info |
|  mtd9  |     0x6900000 |    0x19700000 |    0x20000 | UBIFS            |

###### MTD layout for AP122

Dumped from /proc/mtd after root was obtained.  Added to the table is the offset from the begining of MTD as well as the location & max size for each kernel and initrd.

| Device |        Offset |          Size | Erase Size | Name             |
| :----: | ------------: | ------------: | ---------: | ---------------- |
|  mtd0  |           0x0 |      0x400000 |    0x20000 | Uboot            |
|  mtd1  |      0x400000 |      0x200000 |    0x20000 | shmoo            |
|  mtd2  |      0x600000 |      0x100000 |    0x20000 | Hardware Info    |
|  mtd3  |      0x700000 |      0x100000 |    0x20000 | nvram            |
|  mtd4  |      0x800000 |      0xe00000 |    0x20000 | Kernel Image     |
|        |  **0x800000** |  **0x700000** |    0x20000 | **Kernel 1**     |
|        |  **0xF00000** |  **0x700000** |    0x20000 | **Kernel 2**     |
|  mtd5  |     0x1600000 |     0x5000000 |    0x20000 | App Image        |
|        | **0x1600000** | **0x2800000** |    0x20000 | **Initrd 1**     |
|        | **0x3e00000** | **0x2800000** |    0x20000 | **Initrd 2**     |
|  mtd6  |     0x6600000 |      0x200000 |    0x20000 | DTS Image        |
|  mtd7  |     0x6800000 |      0x100000 |    0x20000 | Uboot Env        |
|  mtd8  |     0x6900000 |      0x100000 |    0x20000 | Boot Info        |
|  mtd9  |     0x6a00000 |      0x100000 |    0x20000 | Static Boot Info |
| mtd10  |     0x6b00000 |    0x19500000 |    0x20000 | UBIFS            |

### Did you break it?

Thats ok.  I did it myself.  Just keep in mind there are two flash locations in the device that the normal firmware flash cycle with alternate between.  The flash process is smart enough to not flash the same version as one already on the device (even if it is invalid because it was incorrectly updated).  So if you break it or want to recover back to stock, you will need three differnet versions.  Two of any version and a third of the version you want to acutally use.  The uboot commands you need to research are [set_bootparam and image_flash](https://community.extremenetworks.com/accesspoints-233173/could-you-give-me-the-password-on-ap-sn-02301704030524-when-i-stop-autoboot-all-default-passwords-not-work-aerohive-aerovive1-thanks-7827254).

1. Flash first throwaway version, reboot.

2. Flash second throwaway version, reboot.

   At this point, both partitions have been overwritten

3. Flash your desired version, reboot.

### Some extra info

They were also kind enough to include the kernel config.

```
AH-0beef0:/tmp/root# ls -la /proc/config.gz
-r--r--r--    1 root     root         15201 Oct 22 16:40 /proc/config.gz
```

### Why?

These are great devices.  If you need to manage a bunch of APs for your business or institution, [check them out](https://www.extremenetworks.com/).  I would never do this to a device I depended on.  I don't even have any ideas of what else I would add or modify on them.  The only real issue I have is I wish there were a way to authenticate to the devices with ssh keys rather than passwords.  With root, that is no longer a problem.  I may sacrifice one of my AP230's to see if I can get OpenWRT running on it, but don't hold your breath.

### Before we go

One more bit of aerohive hacking trivia.  There used to be a hard coded password in [VPN Gateway Virtual Appliance](https://www.aerohiveworks.com/VPN-Gateway-Virtual.asp).  You could get around the activation sequence with the code ```A3rO!5#```.  I discovered this late one night many years ago with a copy of the virtual machine image and the [IDA PRO](https://www.hex-rays.com/products/ida/) decompiler.
