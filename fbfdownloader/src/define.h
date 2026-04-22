
#ifndef  DEFINE_H
#define  DEFINE_H
#include "./Typedef.h"
#include "ParaDefine.h"
#include <pthread.h>
#include <stdio.h>
#include "kstring.h"

#define MAX_PATH          1024
struct CWtpComm;
struct CWtptpDownLoad;
#define RXTIMEOUT							10000
#define TXTIMEOUT							5000
#define WTPTPERRORREPORT                   1
#define WTPTPNOTIFICATION                  0
#define WTPTPNOTIFICATION_BURNTSIZE		   2
#define WTPTPNOTIFICATION_UPLOAD		   3
#define WTPTPNOTIFICATION_FLASHSIZE		   4
#define WTPTPREPORT_EXTENDED_FUSE_INFO     5
#define WTPTPREPORT_UEINFO                 6

#define MAX_FILE_PATH 1024
#define USBPACKETSIZE   0x4000

#define STOPFLAG 1
//#define DLCMD_DO_ERASE_ALL_FLASH_MSK				 0
//#define DLCMD_DO_UPLOAD_DATA_MSK				     1
//#define DLCMD_DO_RESETBBT_MSK				         2
//#define DLCMD_DO_CUSTMOIZEPREAMBLE_MSK				 3
//#define DLCMD_DO_ERASE_ALL_FLASH_ONLY_MSK            4
//#define DLCMD_DO_ENABLE_JTAG_MSK                     5
typedef struct _DEVICE
{
	TCHAR  		UsbDevName[MAX_FILE_PATH];// 
    TCHAR  		LogFileName[MAX_FILE_PATH];// record downloding process to get debug information
	TCHAR        szCurrentMsg[MAX_FILE_PATH];
	BadBlockData	DevBadBlk;		// flash bad block data
	ImageCRCInfo	DevImageCrc;	// CRC value of Images read back from flash
	FILE        *hLog;
	int 		SerialNo; // Serial number of the device.
	int 		npercent;
	int			nBootRomId,
		        nBootLoaderId,
				nDevType;		
	struct CWtpComm    *pWtpComm ;
	volatile int ThreadExit;
	pthread_t   ThreadId; 
	eProcessState kProState;
     
}DEVICE, *PDEVICE;

typedef struct _DISPLAYINFO
{
	TCHAR  		UsbDevName[MAX_FILE_PATH];
	TCHAR        szCurrentMsg[MAX_FILE_PATH];
	BadBlockData	szBadBlk;				// flash bad block data
	ImageCRCInfo	szImageCrc;				// CRC value of Images read back from flash
	eProcessState kProState;
	int 		npercent;
}DISPLAYINFO,*PDISPLAYINFO;

typedef struct _DOWNLOADTARGET
{
	PDEVICE pDev;
    struct CWtptpDownLoad  *pWtptpDownload;

}DOWNLOADTARGET,*PDOWNLOADTARGET;

#define __pdev_free(x)
KLIST_INIT(pdevl, PDEVICE, __pdev_free)
KLIST_INIT(pdisl, PDISPLAYINFO, __pdev_free)

typedef klist_t(pdevl)*  t_DeviceList;
typedef kliter_t(pdevl)*  t_DeviceIter;
typedef klist_t(pdisl)*  t_DisplayInfoList;
typedef kliter_t(pdisl)*  t_DisplayInfoIter;


typedef enum _EDeviceType
{
	kNone    = 0,
	kBootRom	 = 1,
	kBootLoader   = 2,
}EDeviceType;

enum eBootROM_Operation_Mode
{
	NonTrustedBoot1            = 0,
	NonTrustedBoot2            = 1,
	TrustedBoot                = 2,
	TamperBoot                 = 3 // BootROM will not boot device, so, OBM can't detect such mode.
};

typedef struct
{
	UINT32 ChipID                   : 16;                        // 0x1920
	UINT32 RevisionID           : 8;                          // 0xB0
	UINT32 Reserved             : 8;
}ChipIDInfo;


// extended message data
typedef struct {
	UINT32 OEMKeyHash[8];
	UINT32 DeviceUID[2];
	enum eBootROM_Operation_Mode BRMode;
	UINT32 MMCSerialNumber;
	ChipIDInfo ChipId;
} ExMessageData, *pExMessageData;

// extended message report
typedef struct {
	UINT8 ReportType;
	UINT8 ReportLength;
	UINT8 TotalMsgNumber;//OBM分多次送消息，如果消息长度大于0x40
	UINT8 MsgIndex;  //Current Msg Index
	ExMessageData ReportData;
} ExMessageReport, *pExMessageReport;

typedef struct {
	UINT32 OEMKeyHash[8];
	UINT32 DeviceUID[2];
	UINT32 BRMode;
	ChipIDInfo ChipId;
	UINT8  eMMCInfo[16]; //128bit
	UINT32 Reserved1;
	UINT32 Reserved2;
	UINT32 EmmcSize;     //MB
	UINT32 DDRSize;      //MB
} UEInfo;
// extended message report
typedef struct {
	 UINT8 ReportType;
	 UINT8 ReportLength;
	 UINT8 TotalMsgNumber;  //OBM分多次送消息，如果消息长度大于0x40
	 UINT8 MsgIndex;    //Current Msg Index
	 UEInfo  ReportData;
} Ex2MessageReport, *pEx2MessageReport;

typedef struct {
	UEInfo  UEMessageInfo;
	TCHAR lpUsbPortAddress[260];
} MessageUEInfoReport;
#endif
