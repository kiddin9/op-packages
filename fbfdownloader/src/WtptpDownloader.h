#pragma once
#include <pthread.h>
#include "ParaDefine.h"
#include "define.h"
#include "WTPdef.h"
#include "ConvetEdian.h"
#include "ApplicationINI.h"
#include "Typedef.h"
#include "BulkDevNonDrv_Linux.h"
#include "BinFileWtp.h"

/*******************************************************************************************************************

 (C) Copyright 20011 Marvell Semiconductor Hefei Ltd. All Rights Reserved

 *******************************************************************************************************************/


#define MMP2_BOOTLOADER_PROCESSOR   _T("MMP2")
#define MMP2_BOOTLOADER_VERSION  _T("3215")
#define MMP2_BOOTLOADER_DATE _T("12052009")

#define  WKNG_BOOTLOADER_PROCESSOR _T("WKNG")
#define  WKNG_BOOTLOADER_VERSION _T("3301")
#define  WKNG_BOOTLOADER_DATE _T("06172011")

#define NEVO_BOOTLOADER_PROCESSOR _T("NEVO")
#define NEVO_BOOTLOADER_VERSION _T("3301")
#define NEVO_BOOTLOADER_DATE _T("08182011")

#define MMP3_BOOTLOADER_PROCESSOR   _T("MMP3")
#define MMP3_BOOTLOADER_VERSION     _T("3302")
#define MMP3_BOOTLOADER_DATE         _T("03082012")


#define PXA92X_BOOTLOADER_PROCESSOR    _T("TVTD")
#define PXA92X_BOOTLOADER_VERSION      _T("3211")
#define PXA92X_BOOTLOADER_DATE         _T("06242009")

#define EMEI_BOOTLOADER_PROCESSOR    _T("EMEI")
#define EMEI_BOOTLOADER_VERSION      _T("3304")
#define EMEI_BOOTLOADER_DATE         _T("07022012")

#define HELAN_BOOTLOADER_PROCESSOR    _T("HELN")
#define HELAN_BOOTLOADER_VERSION      _T("3307")
#define HELAN_BOOTLOADER_DATE         _T("01152013")

#define EDEN_BOOTLOADER_PROCESSOR     _T("EDEN")
#define EDEN_BOOTLOADER_VERSION       _T("3307")
#define EDEN_BOOTLOADER_DATE          _T("04162013")

#define NEZHA3_BOOTLOADER_PROCESSOR   	 _T("NZA3")
#define NEZHA3_BOOTLOADER_VERSION       _T("3311")
#define NEZHA3_BOOTLOADER_DATE        	 _T("06012014")


#define HELAN2_BOOTLOADER_PROCESSOR     _T("HLN2")
#define HELAN2_BOOTLOADER_VERSION       _T("3308")
#define HELAN2_BOOTLOADER_DATE          _T("02122014")

#define EDENA0_BOOTLOADER_PROCESSOR     _T("EDEN")
#define EDENA0_BOOTLOADER_VERSION       _T("3307")
#define EDENA0_BOOTLOADER_DATE          _T("02142014")

#define ULC1_BOOTLOADER_PROCESSOR     _T("ULC1")
#define ULC1_BOOTLOADER_VERSION       _T("3313")
#define ULC1_BOOTLOADER_DATE          _T("09172014")

#define HELAN3_BOOTLOADER_PROCESSOR     _T("HLN3")
#define HELAN3_BOOTLOADER_VERSION       _T("3313")
#define HELAN3_BOOTLOADER_DATE          _T("11052014") 

#define HELAN4_BOOTLOADER_PROCESSOR     _T("HLN4")
#define HELAN4_BOOTLOADER_VERSION       _T("3313")
#define HELAN4_BOOTLOADER_DATE          _T("25032015") 

#define ULC2_BOOTLOADER_PROCESSOR     _T("ULC2")
#define ULC2_BOOTLOADER_VERSION       _T("3313")
#define ULC2_BOOTLOADER_DATE          _T("08052015") 

struct stFlatformBootLoaderInfo{
	ePlatForm ePlatFormType;
	const char*	  strBLDate;	
	const char*    strBLProcessor;
	const char*	  strBLVersion;
};

extern const struct stFlatformBootLoaderInfo gstFlatformBLInfoSet[];

#define USBPACKETSIZE   0x4000
//#define USBPACKETSIZE   4096  //Modify for FD don't work on NEVO c0 and VMWare download
static const int  NAND_BURNNING_SPEED = 1000; //per ms
static const int  EMMC_BURNNING_SPEED = 8000 ;//per ms
static const int  SPINOR_BURNNING_SPEED = 90 ;//per ms


static const double SPINOR_16M_ERASE_SPEED = 1.3;
static const double SPINOR_32M_ERASE_SPEED   = 0.52;
static const double SPINAND_128M_ERASE_SPEED  = 2.8;
static const double EMMC_ERASE_SPPED  = 96.0;
static const double NAND_ERASE_SPPED  = 49.0;
#define DLCMD_DO_ERASE_ALL_FLASH_MSK                 1
#define DLCMD_DO_UPLOAD_DATA_MSK                 2
#define DLCMD_DO_RESETBBT_MSK                        4
#define DLCMD_DO_ERASE_ALL_FLASH_ONLY_MSK                       16
#define MAX_IMG_FILES                                100
#define MAX_DOWNLOAD_DEVICENUM                       32

#define IMAGEID_LEN 4
#define stringer(x)	#x
void NewCWtptpDownLoad (struct CWtptpDownLoad *me);
BOOL WtptpDownLoad_DownloadImage(struct CWtptpDownLoad *me,PDEVICE pDev, int iFile,const t_ImageFileList* plImgFileList, UINT64 uiAllimgsize,UINT64 *uidownloadsize,int nImages,char* strDownloadImgName);
BYTE WtptpDownLoad_AckWithImageName (struct CWtptpDownLoad *me,const UINT32 ImageType,TCHAR *szFileName,const t_ImageFileList* plImageList);
BOOL WtptpDownLoad_ParseTim (struct CWtptpDownLoad *me,t_ImageFileByDDRList* ImageFileByDDRlist);
BOOL WtptpDownLoad_SetAndWaitForThreadExit(struct CWtptpDownLoad *me,PDEVICE pDev);
BOOL WtptpDownLoad_RemoveEntryList(struct CWtptpDownLoad *me,PDEVICE pDev);
BOOL WtptpDownLoad_GetDeviceBootType(struct CWtptpDownLoad *me,PDEVICE pDev);
BOOL WtptpDownLoad_UploadDataFromTarget(struct CWtptpDownLoad *me,PDEVICE pDev);
BOOL WtptpDownLoad_OpenDevice(struct CWtptpDownLoad *me,PDEVICE pDev);
void WtptpDownLoad_WtptpOpenDevice(struct CWtptpDownLoad *me,struct CWtptpDownLoad *pWtptpDownLoad, USB_HANDLE *pLinuxUsb);
BOOL WtptpDownLoad_ValidateWTPTPMSGReport(struct CWtptpDownLoad *me,PDEVICE pDev, WTPSTATUS *pWtpStatus, UINT32 *ReturnCode);
UINT32 WtptpDownLoad_GetWTPTPMSGReturnCode(struct CWtptpDownLoad *me,WTPSTATUS *pWtpStatus);
BOOL    WtptpDownLoad_WTPTPDownLoad (struct CWtptpDownLoad *me,PDEVICE pDev);
void	WtptpDownLoad_Report(struct CWtptpDownLoad *me);
void    WtptpDownLoad_AddDisplayInfoDevice(struct CWtptpDownLoad *me,PDEVICE pDev);
void    WtptpDownLoad_RemoveDisplayInfoDevice(struct CWtptpDownLoad *me,PDEVICE pDev);
void  WtptpDownLoad_ResetParameter(struct CWtptpDownLoad *me);
BOOL WtptpDownLoad_prepareDumpFlashParam(struct CWtptpDownLoad *me,const PInstanceParams pInstParam);
BOOL WtptpDownLoad_prepareEnabledJtagImg(struct CWtptpDownLoad *me,const PInstanceParams pInstParam);
BOOL WtptpDownLoad_prepareDownloadImg(struct CWtptpDownLoad *me,const PInstanceParams pInstParam);
static PVOID   WtptpDownLoad_BootRomIOThread(PVOID Arg);
static PVOID   WtptpDownLoad_BootLoaderIOThread(PVOID Arg);
static PVOID   WtptpDownLoad_BootLoaderUploadThread(PVOID Arg);
static PVOID   WtptpDownLoad_WtptpDeviceDetectThread(PVOID Arg);
static int WtptpDownLoad_init_hotplug_sock();
BOOL WtptpDownLoad_InitializeBL(struct CWtptpDownLoad *me,PInstanceParams pInstParam);
//BOOL WtptpDownLoadInitializeBLEx(struct CWtptpDownLoad *me,PInstanceParams pInstParam,const TCHAR * pszBLFfileName ,const TCHAR * pszFBFTimFile,const TCHAR * pszFBFfileName);
BOOL WtptpDownLoad_TerminateBL(struct CWtptpDownLoad *me);
void WtptpDownLoad_SetBootDeviceType(struct CWtptpDownLoad *me,PDEVICE pDev,EDeviceType eDevieBootType);
eDDREMMCMatchResult WtptpDownLoad_HandleDownloadImagesByDDRIDandEMMCSize(struct CWtptpDownLoad *me,UINT32 uiDdrVendorId, UINT32 uiDdrUnitSize,UINT32 uiEMMCSize); 
eDDREMMCMatchResult WtptpDownLoad_HandleNandDLImgByDDRID(struct CWtptpDownLoad *me,UINT32 uiDdrVendorId, UINT32 uiDdrUnitSize);
char*  WtptpDownLoad_replace_all(char* str,const char*  old_value,const char* new_value) ;
EDeviceType WtptpDownLoad_GetDeviceType(struct CWtptpDownLoad *me,ePlatForm ePlatfromType,const char* strDate,const char* strVersion ,const char* strProcessor);
void DelCWtptpDownLoad (struct CWtptpDownLoad *me);



struct CWtptpDownLoad
{
	struct CConvertLT2B MyConvertLT2B;
    TCHAR   m_szPrimaryDkbPath[MAX_PATH];
    TCHAR   m_szPrimTimPath[MAX_PATH];
    TCHAR   m_szSecondaryFlasherPath[MAX_PATH];
    TCHAR   m_szOBMPath[MAX_PATH];
    TCHAR   m_szWTMPath[MAX_PATH];
    TCHAR    m_szSWDPath[MAX_PATH];
    TCHAR   m_szTZIPath[MAX_PATH];
    UINT32  m_nFlashDataPageSize ;
    UINT32  m_nBurningSpeed;
    BOOL    m_binitFlag;
    volatile BOOL    m_bTerminateDownload;

	int m_uTotalDDRTypeNum;
	int m_uTotalFlashTypeNum;
	int m_uFlashBadBlockRate;//坏块率门限 m_uFlashBadBlockRate/10000
	
	t_ImageFileList* m_plBootRomImageList;
	t_ImageFileList* m_plBootLoaderImageList;
	t_ImageFileList* m_plJtagEnabledImageList;


	t_ImageFileByDDRList m_lBootRomImageWithDDRList;
	t_ImageFileByDDRList m_lBootLoaderImageWithDDRList;
	t_ImageFileByDDRList m_lJtagEnabledImageWithDDRList;
	
    BOOL        m_bDumpFlash; //to do upload in wtptpdownload
	BOOL        m_bEnabledJtag;
	
    BOOL    m_bInitialiezed ;       // Indicates whether the InitializeBL was called (and was TerminateBL called afterwards)
    BOOL    m_bTermination ;
    BOOL    m_bUploadFromTarget ; //to do upload in wtptpdownload
//
    BOOL    m_bCustPreamble  ;
    BOOL    m_bTrusted;
    BOOL    m_bEraseAllFlash ;
    BOOL    m_bEraseAllFlashOnly;
    BOOL    m_bResetBBT ;
    BOOL    m_bDebugTrace;
    BOOL    m_bOnlyOBMDownload;
    volatile BOOL    m_bTerminateUSBDetect;
    BOOL    m_bSingleDownload;
	BOOL	m_bGetBadBlk;
	BOOL	m_bImageCrcEnable;
    BOOL    m_bIsLittleEndian;
	ePlatForm   m_ePlatformType;
    eFlashType  m_FlashType;
    t_DeviceList m_WtptpDeviceList;
    t_DisplayInfoList  m_DisplayInfoList;


    PInstanceParams     m_lpInstParam ;
    //pWTPTPREAMBLECOMMAND m_lpCustPreambleCmd ;
    t_UpLoadDataSpecList* m_lpUpLoadDataSpecList ;
    int     m_nBootRomDevNum ;
    int     m_nBootLoaderDevNum ;
    int     m_nUploadDevNum;
    pthread_t          BootRomTypeThread[MAX_DOWNLOAD_DEVICENUM];
    pthread_t          BootLoaderTypeThread[MAX_DOWNLOAD_DEVICENUM];
    pthread_t          UploadThread[MAX_DOWNLOAD_DEVICENUM];
    pthread_t          DetectThread;

    pthread_mutex_t    DeviceList_mutex;
    //pthread_mutex_t    Device_mutex;
    pthread_mutex_t    Quit_mutex;
    pthread_mutex_t    callback_mutex;

    

    
    
	
	
	
	
};




