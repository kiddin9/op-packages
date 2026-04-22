/**************************************************************************
**
** (C) Copyright December 2006 Marvell International Ltd.
**
** All Rights Reserved.
**
** This software file (the "File") is distributed by Marvell International  
** Ltd. under the terms of the GNU General Public License Version 2, June  
** 1991 (the "License").  You may use, redistribute and/or modify this File   
** in accordance with the terms and conditions of the License, a copy of  
** which is available along with the File in the license.txt file or by   
** writing to the Free Software Foundation, Inc., 59 Temple Place, Suite 330,   
** Boston, MA 02111-1307 or on the worldwide web at 
** http://www.gnu.org/licenses/gpl.txt.
**
** THE FILE IS DISTRIBUTED AS-IS, WITHOUT WARRANTY OF ANY KIND, AND THE   
** IMPLIED WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR  
** PURPOSE ARE EXPRESSLY DISCLAIMED.  The License provides additional
** details about this warranty disclaimer. 
**
**  FILENAME:	WTPdef.h
**
**  PURPOSE: 	Definition file for the WTPTP software tools..
**  
******************************************************************************/

#ifndef WTPDEF_H // Only make declarations once.
#define WTPDEF_H
#include "kstring.h"
#include "./Macrodef.h"

#define DATALENGTH 0x4000
//#define RETURNDATALENGTH 0x1FFA  // Update for upload data size is 0x2000
#define MESSAGELENGTH 256


#ifndef __cplusplus
	#define ISMSGPORT  FALSE // Use this to enable port handshaking errors for debugging.
#endif




#define USB					0
#define SERIALPORT				1
#define UNKNOWNPORT		   -1

#define ACK			    	0
#define NACK				1
#define MESSAGEPENDING		1
#define MESSAGESTRING		0
#define MESSAGEERRORCODE	1

// Image ID definitions
#define TIMH				0x54494D48
#define DKBI				0x444B4249
#define OBMI				0x4F424D49
#define FBFI                0x46424649
#define FBFD                0x46424644
#define PART                0x50415254
#define TZII				0x545A4949
#define WTMI				0x57544D49


#define NOFASTDOWNLOAD  'N'      //added for fast download proj--used to turn off fast download
#define GET           0      //added for fast download proj--flag for fast download.
#define SET           1      //added for fast download proj--flag for fast download.
#define FDMODE        1      //dummy/default value when getting the value for fast download.

typedef enum 
{
   DISABLED			= 1,		// Standard WTPTP download
   MSG_ONLY			= 2,		//Turn on message mode(listen for msgs forever)
   MSG_AND_DOWNLOAD = 3 //Msg mode and WTPTP download
} MESSAGE_MODES;

struct stImageFile
{
	UINT32 nFileType;
	const char* strImageFile;
};
#define __stI_free(x)
KLIST_INIT(stifl,struct stImageFile,__stI_free)

struct stImageFileByDDR
{
	klist_t(stifl)  *ImageFileList;
	kstring_t sDDRVendorID;
	kstring_t sFlashInfo;
};
static void New_stImageFileByDDR(struct stImageFileByDDR * me)
{
	me->ImageFileList = kl_init(stifl);
}
static void Del_stImageFileByDDR(struct stImageFileByDDR * me)
{
	if (me == NULL) return;
	printf("kl_destroy(stifl, me->ImageFileList);\n");
	kl_destroy(stifl, me->ImageFileList);
	free( me);
}


#define __stID_free(x) Del_stImageFileByDDR(kl_val(x))

KLIST_INIT(stifdl,struct stImageFileByDDR*,__stID_free)

typedef klist_t(stifl)*			t_ImageFileList;
typedef kliter_t(stifl)* t_ImageFileListIter;
typedef kliter_t(stifl)* t_ImageFileListConstIter;

typedef klist_t(stifdl)*			t_ImageFileByDDRList;
typedef kliter_t(stifdl)* t_ImageFileByDDRIter;

// Protocol command definitions
#define PREAMBLE						0x00
#define PUBLICKEY						0x24
#define PASSWORD						0x28
#define SIGNEDPASSWORD					0x25
#define GETVERSION						0x20
#define SELECTIMAGE						0x26
#define VERIFYIMAGE						0x27
#define DATAHEADER						0x2A
#define DATA							0x22
#define MESSAGE							0x2B
#define OTPVIEW							0x2C
#define DEBUGBOOT						0x2D
#define IMEIBIND						0x2E
#define IMEIDATA						0x2F
#define DONE							0x30
#define DISCONNECT						0x31
#define UPLOADDATAHEADER                0x32
#define UPLOADDATA                      0x33
#define PROTOCOLVERSION                 0x34
#define GETPARAMETERS                   0x35
#define GETBADBLOCK 					0x37
#define GETIMAGECRC						0x38
#define UNKNOWNCOMMAND					0xFF


#define  UPLOAD_WITH_SPAREAREA             1
#define  UPLOAD_WITHOUT_SPAREAREA             0



#pragma pack(push,1)
typedef struct
{
	BYTE CMD;
	BYTE SEQ;
	BYTE CID;
	BYTE Flags;
	UINT32 LEN;
	BYTE Data[DATALENGTH];
} WTPCOMMAND;


typedef struct
{
	BYTE CMD;
	BYTE SEQ;
	BYTE CID;
	BYTE Status;
	BYTE Flags;
	BYTE DLEN;
	BYTE Data[DATALENGTH];
} WTPSTATUS;

typedef struct
{
    BYTE MajorVersion;
    BYTE MinorVersion;
    short Build;
} PROTOCOL_VERSION;
 
typedef struct
{
    unsigned int BufferSize;
    unsigned int Rsvd1;
    unsigned int Rsvd2;
    unsigned int Rsvd3;
} TARGET_PARAMS; 

#pragma pack(pop)

#endif
