/**************************************************************************
**
**  (C) Copyright December 2006 Marvell International Ltd.
**
**  All Rights Reserved.
**
**  This software file (the "File") is distributed by Marvell International  
**  Ltd. under the terms of the GNU General Public License Version 2, June  
**  1991 (the "License").  You may use, redistribute and/or modify this File   
**  in accordance with the terms and conditions of the License, a copy of  
**  which is available along with the File in the license.txt file or by   
**  writing to the Free Software Foundation, Inc., 59 Temple Place, Suite 330,   
**  Boston, MA 02111-1307 or on the worldwide web at 
**  http://www.gnu.org/licenses/gpl.txt.
**
**  THE FILE IS DISTRIBUTED AS-IS, WITHOUT WARRANTY OF ANY KIND, AND THE   
**  IMPLIED WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR  
**  PURPOSE ARE EXPRESSLY DISCLAIMED.  The License provides additional
**  details about this warranty disclaimer. 
**
**  FILENAME:	WTPIOCTL.H
**
**  PURPOSE: 	This contains the IoCtl code(s) and other external interfaces 
**              supported in BOOT.
**
**  IMPORTANT NOTE:
**	            Because this header file includes the DEFINE_GUID declaration  
**              it should only be included in the WTPUSBLIB dll. This is   
**              because the GUID for the USB driver should only be advertised   
**              once to the operating system.
**
**  Environment:
**              Kernel mode only                
**                  
******************************************************************************/

#pragma warning (disable : 4005)

#ifndef WTPIOCTLDEF
#define WTPIOCTLDEF

#define CTL_CODE(DeviceType, Function, Method, Access) ( ((DeviceType) << 16) | \
                                                         ((Access) << 14) | \
                                                         ((Function) << 2) | \
                                                         (Method) )
	
#define FILE_ANY_ACCESS         0
#define FILE_DEVICE_UNKNOWN     0x00000022

#define METHOD_BUFFERED         0
#define METHOD_IN_DIRECT        1
#define METHOD_OUT_DIRECT       2
#define METHOD_NEITHER          3

#define BOOT_IOCTL_INDEX		0xDF0 // specific ioctls based from here.

#define BOOT_IOCTL_METHOD_NEITHER(function) CTL_CODE(FILE_DEVICE_UNKNOWN, \
                                                     (BOOT_IOCTL_INDEX + function), \
                                                     METHOD_NEITHER, FILE_ANY_ACCESS)

#define BOOT_IOCTL_METHOD_IN_DIRECT(function) CTL_CODE(FILE_DEVICE_UNKNOWN, \
                                                       (BOOT_IOCTL_INDEX + function), \
                                                       METHOD_IN_DIRECT, FILE_ANY_ACCESS)

#define BOOT_IOCTL_METHOD_OUT_DIRECT(function) CTL_CODE(FILE_DEVICE_UNKNOWN, \
                                                        (BOOT_IOCTL_INDEX + function), \
                                                        METHOD_OUT_DIRECT, FILE_ANY_ACCESS)

#define BOOT_IOCTL_METHOD_BUFFERED(function) CTL_CODE(FILE_DEVICE_UNKNOWN, \
                                                      (BOOT_IOCTL_INDEX + function), \
                                                      METHOD_BUFFERED, FILE_ANY_ACCESS)

#define IOCTL_BOOT_PREAMBLE									BOOT_IOCTL_METHOD_BUFFERED(9) 
#define IOCTL_BOOT_GETVERSION								BOOT_IOCTL_METHOD_BUFFERED(9) 
#define IOCTL_BOOT_PUBLICKEYXMIT							BOOT_IOCTL_METHOD_BUFFERED(9) 
#define IOCTL_BOOT_SEEDPASSWORDRECEIVE						BOOT_IOCTL_METHOD_BUFFERED(9) 
#define IOCTL_BOOT_SIGNEDPASSWORDXMIT						BOOT_IOCTL_METHOD_BUFFERED(9) 
#define IOCTL_BOOT_SELECTIMAGE						        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_JUMPADDRESS						        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_IMAGEDATAXMIT					        BOOT_IOCTL_METHOD_BUFFERED(8)
#define IOCTL_BOOT_VERIFYIMAGE								BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_DATAHEADER						        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_OTPVIEW									BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_DEBUGBOOT								BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_DISCONNECT						        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_DONE								        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_MESSAGE							        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_PROTOCOLVERSION					        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_GETPARAMETERS					        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_UPLOADDATAHEADER						    BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_UPLOADDATA						        BOOT_IOCTL_METHOD_BUFFERED(9)
#define IOCTL_BOOT_SEND										BOOT_IOCTL_METHOD_BUFFERED(14)
#define IOCTL_BOOT_RECEIVE									BOOT_IOCTL_METHOD_BUFFERED(15)

typedef unsigned long ULONG;

#pragma pack(push,1)
    typedef struct _BOOTROM_COMMAND {
        UCHAR   Command;
        UCHAR   Sequence;
        USHORT  Length;
        UCHAR	Data[3996];
    } BOOTROM_COMMAND, *PBOOTROM_COMMAND;

    typedef struct _BOOTROM_PREAMBLE {
        UCHAR	Data[4];
    } BOOTROM_PREAMBLE, *PBOOTROM_PREAMBLE;

    typedef struct _BOOTROM_SENDPUBLICKEY {
        UCHAR   Command;
        UCHAR   Sequence;
        USHORT  Length;
		ULONG	KeyLength;								// can be 16, 32, or 64. units is 4 byte words
        UCHAR	PublicKeyAndModulus[4 * 64 + 4 * 64];	// pub key & mod are same leng
														// mod immediately follows actual pub key with no padding
    } BOOTROM_SENDPUBLICKEY, *PBOOTROM_SENDPUBLICKEY;

    typedef struct _BOOTROM_SENDENCRYPTEDSIGNATURE {
        UCHAR   Command;
        UCHAR   Sequence;
        USHORT  Length;
        UCHAR	EncryptedSignature[4 * 64];	
    } BOOTROM_SENDENCRYPTEDSIGNATURE, *PBOOTROM_SENDENCRYPTEDSIGNATURE;

    typedef union _BOOTROM_PACKET {
		BOOTROM_PREAMBLE				Preamble;
		BOOTROM_COMMAND					Command;
		BOOTROM_SENDPUBLICKEY			SendPublicKey;
		BOOTROM_SENDENCRYPTEDSIGNATURE	SendEncryptedSignature;
    } BOOTROM_PACKET, *PBOOTROM_PACKET;
#pragma pack(pop)


#endif
