/******************************************************************************
**
**  COPYRIGHT (C) 2000, 2002 Intel Corporation.
**
**  This software as well as the software described in it is furnished under
**  license and may only be used or copied in accordance with the terms of the
**  license. The information in this file is furnished for informational use
**  only, is subject to change without notice, and should not be construed as
**  a commitment by Intel Corporation. Intel Corporation assumes no
**  responsibility or liability for any errors or inaccuracies that may appear
**  in this document or any software that may be provided in association with
**  this document.
**  Except as permitted by such license, no part of this document may be
**  reproduced, stored in a retrieval system, or transmitted in any form or by
**  any means without the express written consent of Intel Corporation.
**
**  FILENAME:       downloader.h
**
**  PURPOSE:       
**
**  LAST MODIFIED:
******************************************************************************/

#ifndef DOWNLOADER_H
#define DOWNLOADER_H

#include "Macrodef.h"
#include "Typedef.h"
#if !defined (LINUX)
//#include <windows.h>
#else
//#include "global_types_linux.h"
#endif// LINUX

#define MAX_SIZE_OF_FILENAME_STRING 1024


/* Concentration of all per-build identifiers */
//#define DEBUG_BUILD

#define MAX_NUMBER_OF_IMAGES 200
//#define BLOCK_DEVICE_SECTOR_SIZE (32*1024)				// 32 KB

#ifdef FBFMAKEWEB
#define MAX_NUMBER_OF_IMAGE_STRUCTS_IN_DEVICE_HEADER    150
#else
#define MAX_NUMBER_OF_IMAGE_STRUCTS_IN_DEVICE_HEADER    30
#endif

#define MASTER_BLOCK_HEADER_SIZE_IN_BYTES (sizeof(MasterBlockHeader))
#define DEVICE_HEADER_SIZE_IN_BYTES (sizeof(DeviceHeader_VPXA92x))
#define MAX_NUMBER_OF_FLASH_SECTIONS 3
#define MAX_NUM_OF_FLASH_PROTECTION_REGIONS 10

/* end of per-build identifiers */ 

//#define DEBUG_BUILD


//#define FLASH_BLOCK_SIZE_IN_BYTES (64*1024)


/*-----------------12/22/2004 5:10PM----------------
 * Flash Commands
 * --------------------------------------------------*/
#define FLASH_CMD_WRITE_WORD_1 		0x40
#define FLASH_CMD_WRITE_WORD_2 		0x0

#define FLASH_CMD_BLOCK_ERASE_1		0x20
#define FLASH_CMD_BLOCK_ERASE_2		0xD0	/* Confirm erase */

#define FLASH_CMD_LOCK_BLOCK_1 		0x60
#define FLASH_CMD_LOCK_BLOCK_2		0x01

#define FLASH_CMD_UNLOCK_BLOCK_1	0x60
#define FLASH_CMD_UNLOCK_BLOCK_2	0xD0

#define FLASH_CMD_RESET_FOR_READ 	0xFF

#define FLASH_CMD_CLR_SR			0x50
#define FLASH_CMD_READ_SR			0x70

#define FLASH_ERASED_WORD_16BIT 0xffff 
#define FLASH_ERASED_WORD_32BIT 0xffffffff


#define SR_STATUS_BLOCK_LOCKED		0x02

#define DLCMD_DO_VERIFY_WRITE				 1 
#define DLCMD_DO_ERASE_BLOCKS		  		 2
#define DLCMD_WRITE_IMAGE			   		 3
#define DLCMD_DUMP_IMAGE				     4
#define DLCMD_IMAGE_TYPE_FIELD_BIT			 4			/* bit 4 through 7*/
#define DLCMD_IMAGE_TYPE_FIELD_SIZE_BITS	 4
#define DLCMD_IMAGE_SPARE_AREA_SZ_BIT	 	 8			/* bit 8 through 15 */
#define DLCMD_IMAGE_SPARE_AREA_SZ_FIELD_BITS 8
#define DLCMD_IMAGE_DUMP_SPARE_BIT		 	 16	
#define DLCMD_IMAGE_ABSOLUTE_FLASH_OFFSET_ENABLE_BIT  17
#define DLCMD_IMAGE_USE_SECTOR_BASED_ADDRESSING 18
#define DLCMD_PARTITION_NUM_FIELD_BIT	     (24)		/* bit 24 through 31 */
#define DLCMD_PARTITION_NUM_FIELD_BIT_SIZE   (8)


//image type define
#define	DLCMD_RAW_BINARY_IMAGE_TYPE			(0) /* used when burning raw binary */
#define DLCMD_WINDOWS_MOBILE_IMAGE_TYPE		(1) /* used for WM image type */
#define DLCMD_YAFFS_IMAGE_TYPE			(2) /* this image type is used for YAFFS */
#define DLCMD_UBIFS_IMAGE_TYPE			    (3) /* this image type is used for UBIFS */
#define DLCMD_JFFS2_IMAGE_TYPE			    (4) /* this image type is used for JFFS2 */
#define DLCMD_RND_IMAGE_TYPE	            (5)
#define DLCMD_SPARSE_IMAGE_TYPE				(6) /* this image type is used for Sparse file of Android*/
#define DLCMD_LZMA_IMAGE_TYPE				(7) //OBM burn compressed image to flash
#define DLCMD_LZMA2_IMAGE_TYPE				(8) //OBM burn decompressed image to flash
#define DLCMD_YAFFS_LZMA_IMAGE_TYPE			(9) //SWD compress the image with lzma algorithm,write the compressed image to FBF for image type 9-12
#define DLCMD_UBIFS_LZMA_IMAGE_TYPE			(10) 
#define DLCMD_JFFS2_LZMA_IMAGE_TYPE			(11)
#define DLCMD_RAW_LZMA_IMAGE_TYPE			(12)



#define DLCMD_DUMP_BINARY_IMAGE_WITH_SPARE_TYPE     (3)
#define DLCMD_ABSOLUTE_FLASH_OFFSET_TYPE            (4)
#define DLCMD_ABSOLUTE_FLASH_OFFSET_WITH_SPARE_TYPE (5)

/* general downloader commands */
#define FBF_GENERAL_CMD_INITIALIZE_FLASH_MSK					(1)
#define FBF_GENERAL_CMD_PRODUCTION_INIT_FLASH_MSK				(2)
#define FBF_GENERAL_CMD_DISABLE_ERASE_WM_USER_PARTITIONS_MSK	(4)
#define FBF_GENERAL_CMD_ERASE_ALL_FLASH_MSK					    (8)
#define FBF_GENERAL_CMD_PERFORM_TARGET_RESET_MSK		        (16)

/* Flash parameters flags */
#define FLASH_PARAMETERS_ENABLE_BIT        1

#define FLASH_ERASED_VALUE		 	0xFF


#define BUF_FLAG_PRIMARY_VALID				1
#define BUF_FLAG_SECONDARY_VALID   			2
#define BUF_FLAG_IS_FIRST_SWITCH   			4


#define HARD_SECTOR_SIZE 512 //TBD - receive from ini 

//static int numOfFlashDevices = 0;			/* number of flash devices */



typedef UINT16 CORE_ID;

#define MANITOBA_CORE_ID  0xABAB
#define	HERMON_CORE_ID    0xBBAC
#define BULVERDE_CORE_ID  0xABAD
#define TAVOR_CORE_ID 	  0x1f34



typedef UINT8 FLASH_FAMILY;


#define BOOT_BLOCKS_START_OFFSET 0x0
#define NUM_OF_BOOT_BLOCKS		 4 /* Boot blocks == TIM + OBM + PINMUX + OS Loader */


/* Device Header flags */
#define DEVICE_EXTERNAL_FLASH	1


#define MAX_NUMBER_OF_FLASH_DEVICES_IN_MASTER_HEADER    4
#define MAX_NUMBER_OF_FLASH_DEVICES                     10
#define MAX_RESEVERD_LEN	4
#define MAX_NUM_SKIP_BLOCKS      32

#pragma pack (1)


typedef struct
{ 
	UINT32 tCH;   /*Enable Signal Hold Time*/
	UINT32 tCS;   /*Enable Signal Setup Time*/
	UINT32 tWH;   /*ND_nWE high duration*/
	UINT32 tWP;   /*ND_nWE pulse width*/
	UINT32 tRH;   /*ND_nRE high duration*/
	UINT32 tRP;   /*ND_nRE pulse width*/
	UINT32 tR;    /*ND_nWE high to ND_nRE Low for Read*/
	UINT32 tWHR;  /*ND_nWE High to ND_nRE Low for Read Status*/ 
	UINT32 tAR;   /*ND_ALE Low to ND_nRE Low Delay*/
} FlashTimingStruct;

typedef struct
{
	UINT32 TotalNumOfBlocks; /*The total number of blocks in flash*/
	UINT32 FlashBlockSize; /*Block size in Flash*/
	UINT32 FlashOffset; /*Flash offset address*/
	UINT32 FlashBufferSize; /*Buffer size in Flash*/
	UINT32 NumberOfBlocksInBadBlockPool; /*What is the number of Blocks in the Bad Block Pool*/
	UINT32 SpareAreaSize; /* Flash Device spare area size */
	UINT32 ManufacturerBadBlockInfoOffset; /* Where manufacturer bad block information in flash*/
} FlashSectionStruct;

typedef struct
{ 
	FlashTimingStruct FlashTiming; /*Timing Parameters*/
	FlashSectionStruct FlashSection[MAX_NUMBER_OF_FLASH_SECTIONS];
} FlashParametersStruct;

typedef struct
{
	UINT32 flash_partition_size; /* flash partition size */
	UINT32 commands;		 	 /* bit switches */
	UINT32 First_Sector;		    /* First sector of the image in the block device */
	UINT32 length;			        /* Block length in bytes */
	UINT32 Flash_Start_Address;     /* start address in flash */
	UINT32 Flash_block_size;        /* flash device block size */
	UINT32 ChecksumFormatVersion2;  /* new format version image checksum (left for backwards compatibility) */
} ImageStruct_VPXA92x;

typedef struct
{
	UINT32 Image_ID;				/* image id*/
    UINT32 Image_In_TIM;			/* indicate this image is in TIM or not*/
    UINT32 Flash_partition;        /* partition number of the image */
    UINT32 Flash_erase_size;      /* erase size of the image */
    UINT32 commands;                /* bit switches */
    UINT32 First_Sector;            /* First sector of the image in the block device */
    UINT32 length;                 /*  Image length in bytes */
    UINT32 Flash_Start_Address;    /* start address in flash */
    UINT32 Reserved[MAX_RESEVERD_LEN];
    UINT32 ChecksumFormatVersion2;  /* new format version image checksum (left for backwards compatibility) */
} ImageStruct_V11;

typedef ImageStruct_V11 *PImageStruct_V11;
typedef struct
{
	UINT32 Total_Number_Of_SkipBlocks; // total numbers of skip blocks
	UINT32 Skip_Blocks[MAX_NUM_SKIP_BLOCKS];
} SkipBlocksInfoStruct;


typedef struct 
{
	UINT32 EraseAll; // erase all flag for user partition
    UINT32 ResetBBT; // indicate if reset BBT
	UINT32 NandID;	 // nand flash ID
	UINT32 Reserved[MAX_RESEVERD_LEN - 1];
	SkipBlocksInfoStruct  Skip_Blocks_Struct;
}FlashOptStruct;


typedef struct
{
	UINT32 DeviceFlags; 
	FlashParametersStruct FlashParameters;        /*  Device Parameters */
	UINT8 nOfImages;		/* number of images */
    UINT8 BufferSizeLSB;        /* init to 0x00 */
	UINT16 AccessWidth;		/* init to 0x0000 */
	CORE_ID Core_ID;
	FLASH_FAMILY FlashFamily;			/*	Device Flags */
	UINT8 BufferSizeMSB;
	ImageStruct_VPXA92x imageStruct[MAX_NUMBER_OF_IMAGE_STRUCTS_IN_DEVICE_HEADER]; /* array of image structs */
} DeviceHeader_VPXA92x;


typedef struct
{
	UINT32 DeviceFlags;                 /* NAND, eMMC, SPI-NOR, etc*/
	UINT32 DeviceParameters[16];        /*  Device Parameters, reserve 16 U32 here, will be defined depending on different devices */
	FlashOptStruct  FlashOpt;
	UINT32 ProductionMode;             // production mode 
	UINT8 OptValue;	// choice: 0 - Not reset after download, 1 - Reset after download
	UINT8 ChipID;
	UINT8 BBCS_EN;
	UINT8 CRCS_EN;	
	UINT32 Reserved[MAX_RESEVERD_LEN-2];
	UINT32 nOfImages;        /* number of images */
	ImageStruct_V11 imageStruct[MAX_NUMBER_OF_IMAGE_STRUCTS_IN_DEVICE_HEADER]; /* array of image structs */
} DeviceHeader_V11;

typedef DeviceHeader_VPXA92x *PDeviceHeader_VPXA92x;
typedef DeviceHeader_V11 *PDeviceHeader_V11;


#define NUM_OF_SUPPORTED_FLASH_DEVS	   4

typedef struct
{
	char Unique[24];
	UINT16 Flash_Device_Spare_Area_Size[NUM_OF_SUPPORTED_FLASH_DEVS];
	UINT16 Format_Version;
	UINT16 Size_of_Block;
	UINT32 Bytes_To_Program;
	UINT32 Bytes_To_Verify;
	UINT32 Number_of_Bytes_To_Erase;
	UINT32 Main_Commands;
	UINT32 nOfDevices;	 /* number of devices to burn in parallel */
	UINT32 DLerVersion;	 /* Version of downloader current 1		  */
	UINT32 deviceHeaderOffset[MAX_NUMBER_OF_FLASH_DEVICES_IN_MASTER_HEADER]; /* offset in Sector 0 for each flash device header  */
} MasterBlockHeader;
typedef MasterBlockHeader *PMasterBlockHeader;


typedef struct
{
	char Unique[24];
	UINT16 Flash_Device_Spare_Area_Size[NUM_OF_SUPPORTED_FLASH_DEVS];
	UINT16 Format_Version;
	UINT16 Size_of_Block;
	UINT32 Bytes_To_Program;
	UINT32 Bytes_To_Verify;
	UINT32 Number_of_Bytes_To_Erase;
	UINT32 Main_Commands;
	UINT32 nOfDevices;	 /* number of devices to burn in parallel */
	UINT32 DLerVersion;	 /* Version of downloader current 1		  */
	UINT32 deviceHeaderOffset[MAX_NUMBER_OF_FLASH_DEVICES]; /* offset in Sector 0 for each flash device header  */
} MasterBlockHeader_PXA92x;
typedef MasterBlockHeader_PXA92x *PMasterBlockHeader_PXA92x;
#pragma pack ()

/*- Functions declaration */

void DLMakeMasterBlock(MasterBlockHeader* pMasterBlock, UINT32 nOfDevices, UINT32 DLerVersion);
void DLmakeDeviceHeader(DeviceHeader_V11* devHeader, UINT32 numOfImages);
UINT16 DLgetMasterBlockHeaderChksum(MasterBlockHeader *mBlockHeader);
void DLaddDeviceToMasterHeader(PMasterBlockHeader mbHeader);
void DLaddImageToDeviceHeader(PDeviceHeader_V11 pDev, PImageStruct_V11 pImageStruct);
//void startFlashProgramming(void);

void DLmakeImageStruct( PImageStruct_V11 pImageStruct,
						UINT32 commands,	/* bit switches */
						UINT32 BlockDevice_Start_Block, /* start block in Block device */
                        UINT32 length,             /* Block length in bytes */
                        UINT32 Flash_Start_Address /* start address in flash */
						);


typedef struct
{
	UINT16* startAddr;
	UINT32	nOfBlocksToErase;
    UINT32 Flash_block_size;    /* flash device block size */
} BlockRange;


/*
typedef enum
{
   INVALID = 0,
   READ_REQ,
   READ_PENDING,
   READ_COMPLETE,
   FLASH_WRITING

} BlockStatus;

typedef struct
{
	UINT32 sectorNumber;
	UINT16* ptrBuffer;
	BlockStatus status;
} BlockDeviceHandle;


*/

typedef struct
{
	UINT32 DumpAddressRange;	
    UINT32 FlashStartAddress;
	UINT32 length;
	UINT32 Core_ID;
} FilePreamble;


typedef void (*pfnDebugLog)(TCHAR* pLogEntry);

#endif // DOWNLOADER_H

