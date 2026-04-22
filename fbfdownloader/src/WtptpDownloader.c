// WtptpDownLoad.cpp : Defines the entry point for the DLL application.
//

#include "Macrodef.h"
#ifdef PCIEDOWNLOAD
#include "Parser.h"
#ifdef LS_PCIEDOWNLOAD
#include "asm/types.h" //for lightsurfuring
#endif
#endif
#include <string.h>
#include <ctype.h>
#include <sys/errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/types.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include <signal.h>
#include <sys/time.h>
#include "ErrorCode.h"
#include "WtptpDownloader.h"
#include "WTPCOMMCLASS.h"
#include "Tim.h"
//#include "listdefine.h"
#include "Typedef.h"
#include "WTPdef.h"
#include "ParaDefine.h"
#include "CommonFun.h"

/****************************************************/
#define UEVENT_BUFFER_SIZE 2048
#define UNIT_GB 0X40000000
static BOOL isFastDownloadSwtchSet = 1;

struct CBinFileWtp gBinFileWtp;

char g_LogPath[255] = {0};


const struct stFlatformBootLoaderInfo gstFlatformBLInfoSet[] = {	
	{PLAT_ULC2,		ULC2_BOOTLOADER_DATE,	ULC2_BOOTLOADER_PROCESSOR,		ULC2_BOOTLOADER_VERSION},
	{PLAT_HELAN4,	HELAN4_BOOTLOADER_DATE,	HELAN4_BOOTLOADER_PROCESSOR,	HELAN4_BOOTLOADER_VERSION},
	{PLAT_HELAN3,	HELAN3_BOOTLOADER_DATE,	HELAN3_BOOTLOADER_PROCESSOR,	HELAN3_BOOTLOADER_VERSION},
	{PLAT_ULC1,		ULC1_BOOTLOADER_DATE,	ULC1_BOOTLOADER_PROCESSOR,		ULC1_BOOTLOADER_VERSION},
	{PLAT_NEZHA3,	NEZHA3_BOOTLOADER_DATE,	NEZHA3_BOOTLOADER_PROCESSOR,	NEZHA3_BOOTLOADER_VERSION},
	{PLAT_EDEN_A0,	EDENA0_BOOTLOADER_DATE,	EDENA0_BOOTLOADER_PROCESSOR,	EDENA0_BOOTLOADER_VERSION},
	{PLAT_HELAN2,	HELAN2_BOOTLOADER_DATE,	HELAN2_BOOTLOADER_PROCESSOR,	HELAN2_BOOTLOADER_VERSION},
	/*{PLAT_NEZHA2,	NEZHA2_BOOTLOADER_DATE,	NEZHA2_BOOTLOADER_PROCESSOR,	NEZHA2_BOOTLOADER_VERSION},*/
	{PLAT_EDEN,		EDEN_BOOTLOADER_DATE,	EDEN_BOOTLOADER_PROCESSOR,		EDEN_BOOTLOADER_VERSION},
	{PLAT_HELANLTE,	HELAN_BOOTLOADER_DATE,	HELAN_BOOTLOADER_PROCESSOR,		HELAN_BOOTLOADER_VERSION},
	{PLAT_HELAN,	HELAN_BOOTLOADER_DATE,	HELAN_BOOTLOADER_PROCESSOR,		HELAN_BOOTLOADER_VERSION},
	{PLAT_EMEI,		EMEI_BOOTLOADER_DATE,	EMEI_BOOTLOADER_PROCESSOR,		EMEI_BOOTLOADER_VERSION},
	{PLAT_NEVO_OTA,	NEVO_BOOTLOADER_DATE,	NEVO_BOOTLOADER_PROCESSOR,		NEVO_BOOTLOADER_VERSION},
	{PLAT_NEVO,		NEVO_BOOTLOADER_DATE,	NEVO_BOOTLOADER_PROCESSOR,		NEVO_BOOTLOADER_VERSION},
	{PLAT_MMP3,		MMP3_BOOTLOADER_DATE,	MMP3_BOOTLOADER_PROCESSOR,		MMP3_BOOTLOADER_VERSION},
	{PLAT_PXA92x,	PXA92X_BOOTLOADER_DATE,	PXA92X_BOOTLOADER_PROCESSOR,	PXA92X_BOOTLOADER_VERSION},
	{PLAT_MMP2,		MMP2_BOOTLOADER_DATE,	MMP2_BOOTLOADER_PROCESSOR,		MMP2_BOOTLOADER_VERSION},
	{PLAT_WUKONG,	WKNG_BOOTLOADER_DATE,	WKNG_BOOTLOADER_PROCESSOR,		WKNG_BOOTLOADER_VERSION}
};

void NewCWtptpDownLoad (struct CWtptpDownLoad *me)
{
	NewCConvertLT2B(&me->MyConvertLT2B);
    me->m_nBurningSpeed = 0;
    me->m_bTerminateDownload = FALSE;
	if (me->m_WtptpDeviceList)
    	kl_destroy(pdevl, me->m_WtptpDeviceList);
	me->m_WtptpDeviceList = kl_init(pdevl);
#if DEBUG_MODE
    me->m_bDebugTrace = TRUE;
#else
    me->m_bDebugTrace = FALSE;
#endif
	if (me->m_DisplayInfoList)
    	kl_destroy(pdisl, me->m_DisplayInfoList);
	me->m_DisplayInfoList = kl_init(pdisl);
	if (me->m_lBootRomImageWithDDRList)
		kl_destroy(stifdl,me->m_lBootRomImageWithDDRList);
	me->m_lBootRomImageWithDDRList = kl_init(stifdl);
	if (me->m_lBootLoaderImageWithDDRList)
		kl_destroy(stifdl, me->m_lBootLoaderImageWithDDRList);
	me->m_lBootLoaderImageWithDDRList = kl_init(stifdl);
	if (me->m_lJtagEnabledImageWithDDRList)
		kl_destroy(stifdl, me->m_lJtagEnabledImageWithDDRList);
	me->m_lJtagEnabledImageWithDDRList = kl_init(stifdl);
    me->m_bOnlyOBMDownload = FALSE;
    me->m_bTerminateUSBDetect = FALSE;
    me->m_bSingleDownload = FALSE;
    me->m_bIsLittleEndian = FALSE;
	me->m_uTotalDDRTypeNum = 0;
	me->m_uTotalFlashTypeNum = 0;
    IsLittleEndian(&me->MyConvertLT2B);

}
void DelCWtptpDownLoad (struct CWtptpDownLoad *me)
{
	printf("DelCWtptpDownLoad\n");
    for(t_DisplayInfoIter iter = kl_begin(me->m_DisplayInfoList); iter!=kl_end(me->m_DisplayInfoList); iter = kl_next(iter))
    {
        free( kl_val(iter));
    }
	kl_destroy(pdisl,me->m_DisplayInfoList);
	kl_destroy(pdevl, me->m_WtptpDeviceList);
	kl_destroy(stifdl,me->m_lBootRomImageWithDDRList);
	kl_destroy(stifdl,me->m_lBootLoaderImageWithDDRList);
	kl_destroy(stifdl,me->m_lJtagEnabledImageWithDDRList);

	/*for(t_DeviceIter iter = m_WtptpDeviceList.begin(); iter != m_WtptpDeviceList.end(); ++iter)
	{
		delete (*iter)->pWtpComm;
		delete *iter;
	}
	m_WtptpDeviceList.clear();*/
	pthread_mutex_destroy(&me->DeviceList_mutex);  
	pthread_mutex_destroy(&me->Quit_mutex);  
	pthread_mutex_destroy(&me->callback_mutex);  
}


BOOL WtptpDownLoad_RemoveEntryList(struct CWtptpDownLoad *me,PDEVICE pDev)
{
	t_DeviceIter iter;
    for( t_DeviceIter iter = kl_begin(me->m_WtptpDeviceList); iter != kl_end(me->m_WtptpDeviceList); iter = kl_next(iter))
    {
        if(pDev==kl_val(iter))
        {  
        	CloseUsbPort(pDev->pWtpComm);
			kl_erase(pdevl, me->m_WtptpDeviceList, &iter);
			if (pDev->pWtpComm != NULL)
			{
            	free( pDev->pWtpComm);
				pDev->pWtpComm = NULL;
			}
			if (pDev != NULL)
            {
            	free( pDev);			
            	pDev = NULL;
			}
            break;
        }  
    }
    return TRUE;
}

PVOID   WtptpDownLoad_BootRomIOThread(PVOID Arg)
{

    BOOL bSuccess = FALSE;
    PDOWNLOADTARGET pTarget = (PDOWNLOADTARGET)Arg;
    PDEVICE pDev = pTarget->pDev ;

    tfprintf (pDev->hLog,_T("\nEnter BootRomIOThread\n"));
    static int ActiveBootRomDev;
    
    BOOL bReport = TRUE;

    tfprintf (pDev->hLog,_T("\nEnter BootRom Thread\n"));
    fflush(pDev->hLog);
    bSuccess = WtptpDownLoad_WTPTPDownLoad(pTarget->pWtptpDownload,pDev);


    if (bSuccess)
    {
        tfprintf (pDev->hLog,_T("\nDownLoad Images to BootRom Completed\n"));
    }
    else
    {
        pDev->kProState =kProcAborting;
        WtptpDownLoad_AddDisplayInfoDevice(pTarget->pWtptpDownload,pDev);
        WtptpDownLoad_Report(pTarget->pWtptpDownload);
        tfprintf (pDev->hLog,_T("\nAbnormal Termination in BootRom\n"));
        tprintf(_T("Download failed in BootRom thread\n"));
    }

    tfprintf (pDev->hLog,_T("\nExit BootRom Thread\n"));
    fflush(pDev->hLog);

    if (pDev->hLog != NULL )
    {
        fclose (pDev->hLog);
        pDev->hLog = NULL;
    }
	
    for(int i =0; i<pTarget->pWtptpDownload->m_nBootRomDevNum%32; i++)
    {
        if(pDev->ThreadId == pTarget->pWtptpDownload->BootRomTypeThread[i])
        {
            pTarget->pWtptpDownload->BootRomTypeThread[i] = 0;
            break;
        }
    }

    if(!bSuccess)
    {

        time_t now;
        char strtemp[255];
        time(&now);
        struct   tm     *timenow;
        timenow  = localtime(&now);
        char szfailedlogname[256] = {0};
        sprintf(szfailedlogname,"%s/%d_%d_%d_%d_%d_%d_failed_wtp.log", pTarget->pWtptpDownload->m_szSWDPath,timenow->tm_year+1900,timenow->tm_mon+1,timenow->tm_mday,timenow->tm_hour,timenow->tm_min,timenow->tm_sec);
        tprintf(_T("failelog name is %s\n"),szfailedlogname);
        if(taccess(pDev->LogFileName,0)==0)
        {
            tprintf(_T("rename is %s\n"),pDev->LogFileName);
            rename(pDev->LogFileName,szfailedlogname);
        }
    }

	WtptpDownLoad_RemoveDisplayInfoDevice(pTarget->pWtptpDownload,pDev);
	pthread_mutex_lock(&pTarget->pWtptpDownload->DeviceList_mutex);  
    pTarget->pWtptpDownload->m_nBootRomDevNum--;
    WtptpDownLoad_RemoveEntryList(pTarget->pWtptpDownload,pDev);
	pthread_mutex_unlock(&pTarget->pWtptpDownload->DeviceList_mutex);  

	free( pTarget);
	pTarget = NULL;
	pthread_detach(pthread_self());

    return NULL;
}





PVOID WtptpDownLoad_BootLoaderIOThread(PVOID Arg)
{
#if PRINTLOG
    tprintf(_T("Enter into BootLoaderIOThread\n"));
#endif
    PDOWNLOADTARGET pTarget = (PDOWNLOADTARGET)Arg;
    PDEVICE pDev = pTarget->pDev ;

    tfprintf (pDev->hLog,_T("\nEnter into BootLoader Thread\n"));
    fflush(pDev->hLog);
    BOOL bSuccess = FALSE;
    if(pTarget->pWtptpDownload->m_bSingleDownload)
    {
        pTarget->pWtptpDownload->m_bTerminateUSBDetect = TRUE;
    }
    bSuccess = WtptpDownLoad_WTPTPDownLoad(pTarget->pWtptpDownload,pDev);

    if(bSuccess)
    {
        pDev->kProState =kProcCompleted;
        WtptpDownLoad_AddDisplayInfoDevice( pTarget->pWtptpDownload,pDev);
        WtptpDownLoad_Report(pTarget->pWtptpDownload);

    }
    else
    {
        pDev->kProState =kProcAborting;
        WtptpDownLoad_AddDisplayInfoDevice( pTarget->pWtptpDownload,pDev);
        WtptpDownLoad_Report(pTarget->pWtptpDownload);
        tfprintf (pDev->hLog,_T("\nAbnormal Termination in BootLoader\n"));

        time_t now;
        char strtemp[255];
        time(&now);
        struct   tm     *timenow;
        timenow  = localtime(&now);
        char szfailedlogname[256] = {0};
        sprintf(szfailedlogname,"%s/%d_%d_%d_%d_%d_%d_failed_wtp.log", pTarget->pWtptpDownload->m_szSWDPath,timenow->tm_year+1900,timenow->tm_mon+1,timenow->tm_mday,timenow->tm_hour,timenow->tm_min,timenow->tm_sec);
        tprintf(_T("failelog name is %s\n"),szfailedlogname);
        if(taccess(pDev->LogFileName,0)==0)
        {
            tprintf(_T("rename is %s\n"),pDev->LogFileName);
            rename(pDev->LogFileName,szfailedlogname);
        }
    }
    
    tfprintf (pDev->hLog,_T("\nBootLoader Thread Completed!\n"));
    fflush(pDev->hLog);

    if (pDev->hLog != NULL )
    {
        fclose (pDev->hLog);
        pDev->hLog = NULL;
#if PRINTLOG
        tprintf(_T("\nBootLoader Thread Completed A!\n"));
#endif
	}

#ifndef __ANDROID__
	WtptpDownLoad_RemoveDisplayInfoDevice(pTarget->pWtptpDownload,pDev);
	pthread_mutex_lock(&pTarget->pWtptpDownload->DeviceList_mutex);  
    pTarget->pWtptpDownload->m_nBootLoaderDevNum--;
    WtptpDownLoad_RemoveEntryList(pTarget->pWtptpDownload,pDev);
	pthread_mutex_unlock(&pTarget->pWtptpDownload->DeviceList_mutex);  
#endif
#if PRINTLOG
    tprintf(_T("\nBootLoader Thread Completed B!\n"));
#endif
	free( pTarget);
	pTarget = NULL;
#if PRINTLOG
    tprintf(_T("\nBootLoader Thread Completed C!\n"));
#endif
	pthread_detach(pthread_self()); //detach thread to release memory resources  for joinable thread 
#if PRINTLOG
	tprintf(_T("\nBootLoader Thread Completed E!\n"));
#endif
	return NULL;

}



PVOID WtptpDownLoad_BootLoaderUploadThread(PVOID Arg)
{
    tprintf(_T("Enter BootLoaderIOThread\n"));
    static int ActiveUploadBootloader = 0;
    PDOWNLOADTARGET pTarget = (PDOWNLOADTARGET)Arg;
    PDEVICE pDev = pTarget->pDev ;
    tfprintf (pDev->hLog,_T("\nEnter BootLoader Thread\n"));
    fflush(pDev->hLog);
    BOOL bSuccess = FALSE;
    bSuccess = WtptpDownLoad_UploadDataFromTarget(pTarget->pWtptpDownload,pDev);
    if(bSuccess)
    {
        pDev->kProState =kProcCompleted;
        WtptpDownLoad_AddDisplayInfoDevice( pTarget->pWtptpDownload,pDev);
        WtptpDownLoad_Report(pTarget->pWtptpDownload);
        tfprintf (pDev->hLog,_T("\nBootLoader Upload Thread Completed!\n"));
    }
    else
    {
        pDev->kProState =kProcAborting;
        WtptpDownLoad_AddDisplayInfoDevice( pTarget->pWtptpDownload,pDev);
        WtptpDownLoad_Report(pTarget->pWtptpDownload);

        tfprintf (pDev->hLog,_T("\nAbnormal Termination in BootUpload\n"));

    }

    fflush(pDev->hLog);
    if (pDev->hLog != NULL )
    {
        fclose (pDev->hLog);
        pDev->hLog = NULL;

    }
	pthread_mutex_lock(&pTarget->pWtptpDownload->DeviceList_mutex);  
    pTarget->pWtptpDownload->m_nUploadDevNum--;
    WtptpDownLoad_RemoveEntryList( pTarget->pWtptpDownload,pDev);
	pthread_mutex_unlock(&pTarget->pWtptpDownload->DeviceList_mutex);  
	free( pTarget);
	pTarget = NULL;

    tprintf (_T("\nBootLoader Upload Thread Completed!\n"));
	pthread_detach(pthread_self());

    return NULL;
}


void   WtptpDownLoad_AddDisplayInfoDevice(struct CWtptpDownLoad *me,PDEVICE pDev)
{
    if(kl_size(pdisl,me->m_DisplayInfoList)==0)
    {
        PDISPLAYINFO pDevDisplayInfo = (PDISPLAYINFO)malloc(sizeof(DISPLAYINFO));
        memset(pDevDisplayInfo,0,sizeof(DISPLAYINFO));
        memcpy(pDevDisplayInfo->UsbDevName,pDev->UsbDevName,sizeof(pDev->UsbDevName));
        memcpy(pDevDisplayInfo->szCurrentMsg,pDev->szCurrentMsg,sizeof(pDev->szCurrentMsg));
        memcpy(&pDevDisplayInfo->szBadBlk,&pDev->DevBadBlk,sizeof(pDev->DevBadBlk));
        memcpy(&pDevDisplayInfo->szImageCrc,&pDev->DevImageCrc,sizeof(pDev->DevImageCrc));        
        pDevDisplayInfo->kProState = pDev->kProState;
        pDevDisplayInfo->npercent = pDev->npercent;
		*kl_pushp(pdisl, me->m_DisplayInfoList) = pDevDisplayInfo;        
    }
    else
    {
        BOOL bIsDeviceExist = FALSE;
        t_DisplayInfoIter Iter = kl_begin(me->m_DisplayInfoList);
        const char* sDeviceName, *stmp;
        sDeviceName = pDev->UsbDevName;
        while(Iter!=kl_end(me->m_DisplayInfoList))
        {
            stmp = kl_val(Iter)->UsbDevName;
            if(strstr(stmp,sDeviceName)!=NULL)
            {
                bIsDeviceExist = TRUE;
                memcpy(kl_val(Iter)->UsbDevName,pDev->UsbDevName,sizeof(pDev->UsbDevName));
                memcpy(kl_val(Iter)->szCurrentMsg,pDev->szCurrentMsg,sizeof(pDev->szCurrentMsg));
                memcpy(&kl_val(Iter)->szBadBlk,&pDev->DevBadBlk,sizeof(pDev->DevBadBlk));
                memcpy(&kl_val(Iter)->szImageCrc,&pDev->DevImageCrc,sizeof(pDev->DevImageCrc));  
                kl_val(Iter)->kProState = pDev->kProState;
                kl_val(Iter)->npercent = pDev->npercent;
                break;
            }
            Iter = kl_next(Iter);
        }

        if(!bIsDeviceExist)
        {
            PDISPLAYINFO pDevDisplayInfo = (PDISPLAYINFO)malloc(sizeof(DISPLAYINFO));
            memset(pDevDisplayInfo,0,sizeof(DISPLAYINFO));
            memcpy(pDevDisplayInfo->UsbDevName,pDev->UsbDevName,sizeof(pDev->UsbDevName));
            memcpy(pDevDisplayInfo->szCurrentMsg,pDev->szCurrentMsg,sizeof(pDev->szCurrentMsg));
            memcpy(&pDevDisplayInfo->szBadBlk,&pDev->DevBadBlk,sizeof(pDev->DevBadBlk));
            memcpy(&pDevDisplayInfo->szImageCrc,&pDev->DevImageCrc,sizeof(pDev->DevImageCrc));             
            pDevDisplayInfo->kProState = pDev->kProState;
            pDevDisplayInfo->npercent = pDev->npercent;
            *kl_pushp(pdisl,me->m_DisplayInfoList)=pDevDisplayInfo;
        }

    }
}
void    WtptpDownLoad_RemoveDisplayInfoDevice(struct CWtptpDownLoad *me,PDEVICE pDev)
{

    if(kl_size(pdisl,me->m_DisplayInfoList)==0)
    {
        return;
    }
    else
    {
        t_DisplayInfoIter Iter = kl_begin(me->m_DisplayInfoList);
        const char* sDeviceName,*stmp;
        sDeviceName = pDev->UsbDevName;
        while(Iter!=kl_end(me->m_DisplayInfoList))
        {
            stmp = kl_val(Iter)->UsbDevName;
            if(strstr(stmp,sDeviceName)!= NULL)
            {    
				free( kl_val(Iter));
				kl_val(Iter) = NULL;
                kl_erase(pdisl,me->m_DisplayInfoList,&Iter);
                break;
            }
            Iter = kl_next(Iter);
        }
    }

}

void	WtptpDownLoad_Report(struct CWtptpDownLoad *me)
{

    t_DisplayInfoIter iter = kl_begin(me->m_DisplayInfoList);
    while(iter!=kl_end(me->m_DisplayInfoList))
    {
        NotifyStatus ProcInfo;
        memset(&ProcInfo,0, sizeof(ProcInfo));
        My_strcpy(ProcInfo.pszUSBPortAddress,_tcslen(kl_val(iter)->UsbDevName)+1,kl_val(iter)->UsbDevName);
        My_strcpy(ProcInfo.pszProcMsg,_tcslen(kl_val(iter)->szCurrentMsg)+1,kl_val(iter)->szCurrentMsg);
        memcpy(&ProcInfo.lpBadBlk,&kl_val(iter)->szBadBlk,sizeof(BadBlockData));
        memcpy(&ProcInfo.lpImageCrc,&kl_val(iter)->szImageCrc,sizeof(ImageCRCInfo));
        ProcInfo.eProcState = kl_val(iter)->kProState;
        ProcInfo.nDownloadedPercent = kl_val(iter)->npercent;

        if (me->m_lpInstParam->CallbackProc)
        {
            pthread_mutex_lock(&me->callback_mutex);
            ((CALLBACKPROC)me->m_lpInstParam->CallbackProc)(&ProcInfo);
            pthread_mutex_unlock(&me->callback_mutex);
        }
        iter = kl_next(iter);
    }


}

BOOL WtptpDownLoad_SetAndWaitForThreadExit(struct CWtptpDownLoad *me,PDEVICE pDev)
{
    //pthread_mutex_lock(&Device_mutex);
    pDev->ThreadExit = STOPFLAG;
    SetExitHandle(pDev->pWtpComm,1);
    //pthread_mutex_unlock(&Device_mutex);
    usleep(2000000);
    WtptpDownLoad_RemoveEntryList(me,pDev);

    return TRUE;
}

void WtptpDownLoad_WtptpOpenDevice(struct CWtptpDownLoad *me,struct CWtptpDownLoad *pWtptpDownLoad, USB_HANDLE *pLinuxUsb)
{
    PDEVICE pDev = (PDEVICE)malloc(sizeof(DEVICE));
    memset(pDev, 0, sizeof(DEVICE));
    struct CWtpComm *pWtpComm = (struct CWtpComm *)malloc(sizeof(struct CWtpComm));
	NewCWtpComm(pWtpComm);
    pDev->pWtpComm = pWtpComm;
#if PRINTLOG
    printf(_T("add DevName:%s\n"), pLinuxUsb->DevName);
#endif
	char szBuffer[MAX_FILE_LENGTH];
	memset(szBuffer,0,sizeof(TCHAR)*MAX_FILE_LENGTH);
	snprintf(szBuffer,sizeof(szBuffer),("echo ---add DevName:%s--- > /dev/kmsg"),pLinuxUsb->DevName);
	system(szBuffer);
	PUSB_HANDLE pUsb = (PUSB_HANDLE) malloc(sizeof(USB_HANDLE));
	NEW_USB_HANDLE(pUsb);
	COPY_USB_HANDLE(pUsb, pLinuxUsb);
    SetLinuxDev(pDev->pWtpComm,pUsb);

    sprintf(pDev->UsbDevName, _T("%s"), pLinuxUsb->DevName);
    char sUSBName[128];
	strcpy(sUSBName, pLinuxUsb->DevName);
    WtptpDownLoad_replace_all(sUSBName, _T("/"), _T("_"));
    sprintf(pDev->LogFileName, _T("%s/wtp%s.log"), pWtptpDownLoad->m_szSWDPath, sUSBName);
	#if PRINTLOG
	printf(_T("LogFileName  is:%s\n"), pDev->LogFileName);
#endif
    if (WtptpDownLoad_OpenDevice(pWtptpDownLoad,pDev))
    {
        pthread_mutex_lock(&pWtptpDownLoad->DeviceList_mutex);
        *kl_pushp(pdevl,pWtptpDownLoad->m_WtptpDeviceList)=pDev;
        pthread_mutex_unlock(&pWtptpDownLoad->DeviceList_mutex);

        pDev->kProState = kProcConnecting;
        WtptpDownLoad_AddDisplayInfoDevice(pWtptpDownLoad,pDev);
        WtptpDownLoad_Report(pWtptpDownLoad);
#if PRINTLOG
        tprintf(_T("Open device successfully\n"));
#endif
		fflush(stdout);
    }
    else
    {
		pDev->kProState = kProcAborting;
        WtptpDownLoad_AddDisplayInfoDevice(pWtptpDownLoad,pDev);
        WtptpDownLoad_Report(pWtptpDownLoad);
        tprintf(_T("Open device failed\n"));
        fflush(stdout);
        free( pDev);
        pDev = NULL;
    }
}

PVOID   WtptpDownLoad_WtptpDeviceDetectThread(PVOID Arg)
{

    struct CWtptpDownLoad* pWtptpDownLoad  = (struct CWtptpDownLoad*)Arg;
    PUSB_HANDLE hUSBDev[MAX_DEVNUM];

    int hotplug_sock = WtptpDownLoad_init_hotplug_sock();
    int existing_num = BulkDevNonDrv_FindAllSupportedDevices(hUSBDev);
    if (0 == existing_num)
    {
#if PRINTLOG
        tprintf(_T("Please plug your USB device\n"));
#endif
        fflush(stdout);
    }
    else
    {
        for (int loops = 0; loops < existing_num; loops++)
            {
                WtptpDownLoad_WtptpOpenDevice(pWtptpDownLoad,pWtptpDownLoad,hUSBDev[loops]);
                tprintf(_T("Open existing USB device number %d\n"), loops);
                fflush(stdout);
                free( hUSBDev[loops]);
            }
    }

    while (1)
    {
        pthread_mutex_lock(&(pWtptpDownLoad->Quit_mutex));
        if(pWtptpDownLoad->m_bTerminateDownload)
        {
#if PRINTLOG
        	tprintf(_T("\nQuit from detect device.....\n"));       
#endif
			break;
        }
        pthread_mutex_unlock(&(pWtptpDownLoad->Quit_mutex));
        usleep(100);

        /* Netlink message buffer */
        TCHAR buf[UEVENT_BUFFER_SIZE * 2] = {0};
       int nLen = recv(hotplug_sock, &buf, sizeof(buf), 0);
       //printf(_T("Recieve message is:%s\n"), buf);
		USB_HANDLE *pLinuxUsb;
		int bAdd = 0;
		pLinuxUsb = (USB_HANDLE *)calloc(1, sizeof(USB_HANDLE));
        if ( BulkDevNonDrv_CheckDevForNetLink(pLinuxUsb, buf, nLen, &bAdd) )
        {
			if ( 1 == bAdd )
		    {
				if(pWtptpDownLoad->m_bTerminateUSBDetect)
                {
                     continue; //不检测插入的新设备，但是可以检测移除的设备
                }
				system("echo ---bAdd=1--- > /dev/kmsg");
                WtptpDownLoad_WtptpOpenDevice(pWtptpDownLoad,pWtptpDownLoad, pLinuxUsb);
            }
			else 
			if (0 == bAdd)
			{
				const char* sCurrentRemoveDevice = pLinuxUsb->DevName;
#if PRINTLOG
				printf(_T("remove DevName:%s\n"), pLinuxUsb->DevName);
#endif
				system("echo ---remove DevName--- > /dev/kmsg");
				pthread_mutex_lock(&pWtptpDownLoad->DeviceList_mutex);  
                if(kl_size(pdevl,pWtptpDownLoad->m_WtptpDeviceList)>0)
                {
					t_DeviceIter iter  = kl_begin(pWtptpDownLoad->m_WtptpDeviceList);
					while(iter!=kl_end(pWtptpDownLoad->m_WtptpDeviceList))
					{
						const char* strDev  = GetLinuxDev((kl_val(iter))->pWtpComm)->DevName;
						const char* strtmp = pLinuxUsb->DevName;
						if(strstr(sCurrentRemoveDevice,strtmp)!= NULL)  // it this device is removed , so will terminate thread
						{
							WtptpDownLoad_SetAndWaitForThreadExit(pWtptpDownLoad,kl_val(iter));
							break;
						}
						iter = kl_next(iter);
                   }
              	}
				pthread_mutex_unlock(&pWtptpDownLoad->DeviceList_mutex);  
			}
        }


		free( pLinuxUsb);
    }
    close(hotplug_sock); //close socket.
    pthread_detach(pthread_self());
    return NULL;
}

int WtptpDownLoad_init_hotplug_sock()
{
    const int buffersize = 1024*16*16;
    int ret;

    struct sockaddr_nl snl;
#ifdef __ANDROID__
    memset(&snl, 0, sizeof(struct sockaddr_nl));
#else
    bzero(&snl, sizeof(struct sockaddr_nl));
#endif
    snl.nl_family = AF_NETLINK;
    snl.nl_pid = getpid();
    snl.nl_groups = 1;
#if PRINTLOG
    tprintf(_T("init_hotplug_sock\n"));
#endif
	fflush(stdout);

    //tprintf(_T("enter into init_hotplug_sock, snl.nl_pid = %d,snl.nl_groups = %d\n"),snl.nl_pid,snl.nl_groups);
    
    int s = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_KOBJECT_UEVENT);
    if (s == -1)
    {
#if PRINTLOG
        perror(_T("socket"));
#endif
        return -1;
    }
    //tprintf(_T("socket return %d\n"),s);
    ret = setsockopt(s, SOL_SOCKET, SO_RCVBUF, &buffersize, sizeof(buffersize));
    if (ret < 0)
    {
#if PRINTLOG
        perror(_T("setsockopt"));
#endif
    }

    ret = bind(s, (struct sockaddr *)&snl, sizeof(struct sockaddr_nl));
    
    if (ret < 0)
    {
        tprintf(_T("bind return %d... , errno  %d\n"),ret , errno);
        printf("strerror: %s\n", strerror(errno));     
        close(s);
        return -1;
    }

    //tprintf(_T("Please plug your USB device\n"));
	fflush(stdout);

    return s;
}


void WtptpDownLoad_SetBootDeviceType(struct CWtptpDownLoad *me,PDEVICE pDev,EDeviceType eDevieBootType)
{
	CWtpCommSetBootDeviceType(pDev->pWtpComm,eDevieBootType);
	pDev->nDevType = eDevieBootType;  
	if (kBootLoader == eDevieBootType)
	{		
		strcpy(pDev->szCurrentMsg,"Open an BootLoader Device");
		tfprintf (pDev->hLog,_T("\nOpen an BootLoader Device\n"));
	}
	else
	{
		strcpy(pDev->szCurrentMsg,"Open an BootRom Device");
		tfprintf (pDev->hLog,_T("\nOpen an BootRom Device\n"));
	}
	fflush(pDev->hLog);
	
    pDev->kProState = kProcDebugLog;
	WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
	WtptpDownLoad_Report(me);

}



BOOL WtptpDownLoad_GetDeviceBootType(struct CWtptpDownLoad *me,PDEVICE pDev)
{
    IsLittleEndian(&me->MyConvertLT2B);
#if PRINTLOG
	tprintf(_T("Getting type of Device.....\n"));
#endif
	if(me->m_bDebugTrace)
    {
        tprintf(_T("Getting type of Device.....\n"));
    }

    tfprintf (pDev->hLog,_T("\nGetting type of Device\n"));
    pDev->nDevType = kNone;

    MESSAGE_MODES currentMessageMode=MSG_AND_DOWNLOAD;
   SetMessageMode( pDev->pWtpComm,currentMessageMode);


    if (!OpenUsbPort(pDev->pWtpComm))
    {
        tfprintf (pDev->hLog,_T("\n Open Usb Port in GetDeviceBootType failed\n"));
        return FALSE;
    }
    SetPortType(pDev->pWtpComm,0);//set usb port as default

    if( PLAT_HELAN ==me->m_ePlatformType)
    {
        sleep (1);
    }
    if (!SendPreamble(pDev->pWtpComm,me->m_bCustPreamble) )
    {
        tprintf (_T("\nSendPreamble failed in GetDeviceBootType\n"));
        return FALSE;
    }

    tfprintf (pDev->hLog,_T("\n GetTargetMessage after sendpreamble\n"));
    WTPSTATUS WtpStatus = {0x00, 0x00, 0x00, 0x00, 0x01, htole32(0x00)};
    if (currentMessageMode == MSG_AND_DOWNLOAD )
    {
        WtpStatus.Status = ACK;
        if(!GetTargetMessage(pDev->pWtpComm,&WtpStatus))
        {
            tfprintf (pDev->hLog,_T("\n GetTargetMessage after sendpreamble failed\n"));
            return FALSE;
        }
        WtpStatus.Flags = 0x1;
    }

    tfprintf(pDev->hLog,_T("\nGetting Version...\n"));
    WtpStatus.CMD = 0x0;
    WtpStatus.SEQ = 0x0;
    WtpStatus.CID = 0x0;
    WtpStatus.Status= 0x0;
    WtpStatus.Flags = 0x1;
    WtpStatus.DLEN = 0x0;
    fflush(pDev->hLog);

    if (!GetVersion(pDev->pWtpComm,&WtpStatus))
    {
        tprintf (_T("\nGetting Version failed\n"));
        return FALSE;
    }
    if(ACK != WtpStatus.Status)
    {
        CWtpCommSetBootDeviceType(pDev->pWtpComm,kNone);
        pDev->nDevType = kNone;
        tprintf(_T("Can't get response from Target when getting type of device\n"));
        tfprintf (pDev->hLog,_T("\nUnknown Device\n"));
        fflush(pDev->hLog);
        return FALSE;
    }


    TCHAR Processor[24];
    TCHAR Version[24];
    TCHAR Date[24];
	memset(Processor, 0, 24);
	memset(Version, 0, 24);
	memset(Date, 0, 24);
	
    if(me->m_bDebugTrace)
    {
        tprintf(_T("\nVersion: %c%c%c%c\n"),WtpStatus.Data[3],WtpStatus.Data[2],WtpStatus.Data[1],WtpStatus.Data[0]);
        tprintf(_T("\nDate: %08X\n"),le32toh(*(unsigned int *)&WtpStatus.Data[4]));
        tprintf(_T("\nProcessor: %c%c%c%c\n"),WtpStatus.Data[11],WtpStatus.Data[10],WtpStatus.Data[9],WtpStatus.Data[8]);

    }
    sprintf(Version,_T("%c%c%c%c"),WtpStatus.Data[3],WtpStatus.Data[2],WtpStatus.Data[1],WtpStatus.Data[0]);
    sprintf(Date,_T("%02x%02x%02x%02x"),WtpStatus.Data[7],WtpStatus.Data[6],WtpStatus.Data[5],WtpStatus.Data[4]);
    sprintf(Processor,_T("%c%c%c%c"),WtpStatus.Data[11],WtpStatus.Data[10],WtpStatus.Data[9],WtpStatus.Data[8]);
    const char* strProcessor,*strVersion,*strDate;
    strProcessor = Processor;
    strVersion = Version;
    strDate = Date;
    tfprintf(pDev->hLog,_T("\nVersion: %c%c%c%c"),WtpStatus.Data[3],WtpStatus.Data[2],WtpStatus.Data[1],WtpStatus.Data[0]);
    tfprintf(pDev->hLog,_T("\nDate: %08X"),le32toh(*(unsigned int *)&WtpStatus.Data[4]));
    tfprintf(pDev->hLog,_T("\nProcessor: %c%c%c%c"),WtpStatus.Data[11],WtpStatus.Data[10],WtpStatus.Data[9],WtpStatus.Data[8]);
    fflush(pDev->hLog);

   

	BOOL bObmSupportMutliDDR = FALSE;
	BOOL bObmSupportMultiFlash = FALSE;
	UINT32 uiEMMCSize = 0;
	UINT32 uiDdrVendorId = 0;
	UINT32 uiDdrUnitSize = 0;
	TCHAR szDDRVendorID[20];
	memset(szDDRVendorID,0,sizeof(szDDRVendorID));
	//new OBM return DDR Vendor ID and DDR SIZE 8 bytes: 4 bytes for Vendor ID : ID01,ID02;DDR size : 0001,0002 the value is unit(512M)
	if(20 == WtpStatus.DLEN)
	{
		tsprintf(szDDRVendorID,_T("0x%c%c"),WtpStatus.Data[13],WtpStatus.Data[12]);		
		uiDdrVendorId = Str2Uint32(szDDRVendorID);
		uiDdrUnitSize = *(unsigned long *)&WtpStatus.Data[16];	
		bObmSupportMutliDDR = TRUE;
	}
	else if (24 == WtpStatus.DLEN)
	{
		tsprintf(szDDRVendorID,_T("0x%c%c"),WtpStatus.Data[13],WtpStatus.Data[12]);		
		uiDdrVendorId = Str2Uint32(szDDRVendorID);
		uiDdrUnitSize = *(unsigned long *)&WtpStatus.Data[16];
		uiEMMCSize = *(unsigned long *)&WtpStatus.Data[20];
		bObmSupportMutliDDR = TRUE;
		bObmSupportMultiFlash = TRUE;
	}

	EDeviceType eBootDeviceType = WtptpDownLoad_GetDeviceType(me,me->m_ePlatformType,strDate,strVersion,strProcessor);
	if (kNone == eBootDeviceType)
	{
		strcpy(pDev->szCurrentMsg,"Unkown Device");	
    	pDev->kProState = kProcErrorCode;
    	WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
    	WtptpDownLoad_Report(me);
	
		tfprintf (pDev->hLog,_T("\nUnkown Device\n"));
		fflush(pDev->hLog);
		return FALSE;
	}

	WtptpDownLoad_SetBootDeviceType(me,pDev, eBootDeviceType);
		
  
	if(kBootLoader ==pDev->nDevType )
	{
		if (FLASH_EMMC == me->m_FlashType)
		{			
			if (me->m_uTotalDDRTypeNum>0 && !bObmSupportMutliDDR)
			{
				tfprintf (pDev->hLog,_T("Current OBM don't suppport multiple DDR feature, please update OBM.\n"));		
				return FALSE;
			}
			
			if (me->m_uTotalFlashTypeNum>1 && !bObmSupportMultiFlash)
			{
				tfprintf (pDev->hLog,_T("Current OBM don't suppport multiple eMMC feature, please update OBM.\n"));
				return FALSE;
			}

			eDDREMMCMatchResult eError = WtptpDownLoad_HandleDownloadImagesByDDRIDandEMMCSize(me,uiDdrVendorId,uiDdrUnitSize,uiEMMCSize);
			if(eError!=kMatchNoError)
			{			
			
				TCHAR szMessage[MAX_FILE_LENGTH]={0};
				if(kDDRMismatchError==eError)
				{
					tsnprintf(szMessage,MAX_FILE_LENGTH,_T("DDRType is not found , OBM read vendor DDR Pid 0x%x, can't find it in blf configure \n"),uiDdrVendorId<<8|uiDdrUnitSize);
				}
				else if(kEMMCMismatchError==eError)
				{
					tsnprintf(szMessage,MAX_FILE_LENGTH,_T("EMMC Size Type is not found , OBM read EMMC Size is %08X, can't find it in blf configure \n"),uiEMMCSize);
				}
				else
					tsnprintf(szMessage,MAX_FILE_LENGTH,_T("InitialBL have issue\n"));

				tfprintf (pDev->hLog,szMessage);				
				return FALSE;
			}
		}
		else if (FLASH_NAND == me->m_FlashType)
		{
			if (me->m_uTotalDDRTypeNum>0 && !bObmSupportMutliDDR)
			{
				tfprintf (pDev->hLog,_T("Current OBM don't suppport multiple DDR feature, please update OBM.\n"));	
				return FALSE;
			}
			
			eDDREMMCMatchResult eError = WtptpDownLoad_HandleNandDLImgByDDRID(me,uiDdrVendorId,uiDdrUnitSize);
			if(eError!=kMatchNoError)
			{
				TCHAR szMessage[MAX_FILE_LENGTH]={0};
				if(kDDRMismatchError==eError)
				{
					tsnprintf(szMessage,MAX_FILE_LENGTH,_T("DDRType is not found , OBM read vendor DDR Pid 0x%x, can't find it in blf configure \n"),uiDdrVendorId<<8|uiDdrUnitSize);
				}
				tfprintf (pDev->hLog,szMessage);			
				return FALSE;
			}
		}
		else
		{
			t_ImageFileByDDRIter Iter = kl_begin(me->m_lBootLoaderImageWithDDRList); 
			me->m_plBootLoaderImageList = &((kl_val(Iter))->ImageFileList);
		}
	}
	fflush(pDev->hLog);
    return TRUE;
}


BOOL WtptpDownLoad_OpenDevice(struct CWtptpDownLoad *me,PDEVICE pDev)
{
    PDOWNLOADTARGET pTarget = (PDOWNLOADTARGET)malloc(sizeof(DOWNLOADTARGET));
    pTarget->pDev = pDev;
    pTarget->pWtptpDownload = me;
    if((pDev->hLog = _tfopen (pDev->LogFileName,_T("w"))) == NULL)
    {
        tprintf(_T("Create log file failed\n"));
        return FALSE;
    }
    else
    {
        SetLogFile(pDev->pWtpComm,pDev->hLog);
    }
	SetPlatformType(pDev->pWtpComm,me->m_ePlatformType);
    //Do upload only after detect a device if user want to do upload
    if(me->m_bDumpFlash)
    {
        pDev->nDevType = kBootLoader;
        pDev->SerialNo = me->m_nUploadDevNum;
        int res= pthread_create(&me->UploadThread[me->m_nUploadDevNum%32], NULL,WtptpDownLoad_BootLoaderUploadThread , pTarget);
        if(res!=0)
        {
#if PRINTLOG
            perror (_T("Thread creation failed\n"));
#endif
			free( pTarget);
            return FALSE;
        }
        else
        {
            pDev->ThreadId = me->UploadThread[me->m_nUploadDevNum%32];
            me->m_nUploadDevNum++;

        }
    }
    else
    {
        if(WtptpDownLoad_GetDeviceBootType(me,pDev))
        {
#if PRINTLOG
            tprintf(_T("Get type of device successfully\n"));
#endif
			tfprintf(pDev->hLog,_T("\nGet type of device successfully\n"));
            fflush(pDev->hLog);
        }
        else
        {
            tprintf(_T("Get type of device failed\n"));
            tfprintf(pDev->hLog,_T("\nGet type of device failed\n"));
            fflush(pDev->hLog);
            fclose(pDev->hLog);
			free( pTarget);
            return FALSE;
        }
        if(pDev->nDevType == kBootRom)
        {
            int res = pthread_create(&me->BootRomTypeThread[me->m_nBootRomDevNum%32], NULL,WtptpDownLoad_BootRomIOThread , pTarget);
            if(res!=0)
            {
#if PRINTLOG
                perror (_T("Thread creation failed\n"));
#endif
				fclose(pDev->hLog);
				free( pTarget);
                return FALSE;
            }
            else
            {
                pDev->ThreadId = me->BootRomTypeThread[me->m_nUploadDevNum%32];
                me->m_nBootRomDevNum++;
            }
        }
        else if(pDev->nDevType == kBootLoader)
        {
#if PRINTLOG
            tprintf (_T("Thread creation BootLoaderTypeThread\n"));
#endif
			int res = pthread_create(&me->BootLoaderTypeThread[me->m_nBootLoaderDevNum%32], NULL,WtptpDownLoad_BootLoaderIOThread , pTarget);
            if(res!=0)
            {
#if PRINTLOG
                perror (_T("Thread creation failed\n"));
#endif
				fclose(pDev->hLog);
				free( pTarget);
                return FALSE;
            }
            else
            {
                pDev->ThreadId = me->BootLoaderTypeThread[me->m_nBootLoaderDevNum%32];
                me->m_nBootLoaderDevNum++;
            }

        }
    }


    return TRUE;

}


BOOL WtptpDownLoad_DownloadImage(struct CWtptpDownLoad *me,PDEVICE pdev, int iFile,const t_ImageFileList* plImgFileList, UINT64 uiAllimgsize,UINT64 *uidownloadsize,int nImages,char* strDownloadImgName)
{
	if(pdev->ThreadExit == STOPFLAG)
    {
        pdev->kProState = kProcAborting;
        WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
        WtptpDownLoad_Report(me);
        return FALSE;
    }
    _tcscpy(pdev->szCurrentMsg,_T("Begin DownloadImage..........."));
    pdev->kProState = kProcDebugLog;
    WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
    WtptpDownLoad_Report(me);
    tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);
    fflush(pdev->hLog);

    WTPCOMMAND WtpCmd;
    eProcessState  eProcState;
    MESSAGE_MODES currentMessageMode=MSG_AND_DOWNLOAD;
    SetMessageMode(pdev->pWtpComm,currentMessageMode);
    WTPSTATUS WtpStatus = {0x00, 0x00, 0x00, 0x00, 0x01, 0x00};
    UINT32  ImageType = 0;
    BYTE IsImage = NACK;
    unsigned int uiRemainingBytes = 0;
    unsigned int uiBufferSize = 0;
    TCHAR szFileName[MAX_PATH];
	memset(szFileName,0,MAX_PATH);
    long lFileSize = 0,BytesRead;
    FILE* hFile = NULL;
    int i = 0;


    if(iFile!=0)
    {
        tfprintf (pdev->hLog,_T("\nSending Preamble...\n"));

        if(me->m_bDebugTrace)
        {
            _tcscpy(pdev->szCurrentMsg,_T("Sending Preamble..."));
            pdev->kProState = kProcDebugLog;
            WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
            WtptpDownLoad_Report(me);
            tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);
        }


        if (!SendPreamble(pdev->pWtpComm,me->m_bCustPreamble))
        {
            _tcscpy(pdev->szCurrentMsg,_T("SendPreamble can not get ACK..."));
            pdev->kProState = kProcDebugLog;
			WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
            WtptpDownLoad_Report(me);
            tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);
            return FALSE;
        }

        if (currentMessageMode == MSG_AND_DOWNLOAD )
        {
            WtpStatus.Status = ACK;
            GetTargetMessage(pdev->pWtpComm,&WtpStatus);
            WtpStatus.Flags = 0x1;
        }
        tfprintf (pdev->hLog,_T("\nGetting Version...\n"));

        if(me->m_bDebugTrace)
        {
            _tcscpy(pdev->szCurrentMsg,_T("Getting Version..."));
			WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
            WtptpDownLoad_Report(me);
        }

        if (!GetVersion(pdev->pWtpComm,&WtpStatus))
        {
            _tcscpy(pdev->szCurrentMsg,_T("GetVersion failed..."));
            pdev->kProState = kProcDebugLog;
			WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
            WtptpDownLoad_Report(me);
            tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);
            return FALSE;
        }


    }
    fflush(pdev->hLog);
    if (!SelectImage(pdev->pWtpComm,&ImageType))
    {
        _tcscpy(pdev->szCurrentMsg,_T("SelectImage failed..."));
        pdev->kProState = kProcDebugLog;
		WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
		WtptpDownLoad_Report(me);
        tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);

        return FALSE;
    }


    IsImage = WtptpDownLoad_AckWithImageName(me,ImageType,szFileName,plImgFileList);
    strcpy(strDownloadImgName, szFileName);
    if (!VerifyImage(pdev->pWtpComm,IsImage))
    {
        _tcscpy(pdev->szCurrentMsg,_T("Verify image failed..."));
        pdev->kProState = kProcDebugLog;
		WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
		WtptpDownLoad_Report(me);
        tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);

        return FALSE;

    }
    tsprintf(pdev->szCurrentMsg,_T("download file name is %s"),szFileName);
    pdev->kProState = kProcDebugLog;
	WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
	WtptpDownLoad_Report(me);
    tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);

    /*if ((hFile = _tfopen (szFileName,_T("rb"))) == NULL)
    {
        TCHAR szMessage[1024];
        sprintf(szMessage,_T("\nError: Can't open  %s file!\n"),szFileName);
        _tcscpy(pdev->szCurrentMsg,szMessage);
        pdev->kProState = kProcDebugLog;
        AddDisplayInfoDevice(pdev);
        Report();
        tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);

        return FALSE;
    }*/
	if (!BinFileWtp_IsFileExist(&gBinFileWtp,szFileName))
	{
		TCHAR szMessage[1024];
		sprintf(szMessage,_T("\nError: Can't open  %s file!\n"),szFileName);
		_tcscpy(pdev->szCurrentMsg,szMessage);
		pdev->kProState = kProcDebugLog;
		WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
		WtptpDownLoad_Report(me);
		tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);
		
		return FALSE;

	}

    //fseek (hFile,0L,SEEK_END); // Set position to EOF
    //lFileSize = ftell (hFile); // Get position of file, thus the file size.
	lFileSize = BinFileWtp_GetFileSize(&gBinFileWtp,szFileName);
	
    if ((ImageType == TIMH) || (ImageType == PART))
    {
        //fseek (hFile,0L,SEEK_SET); // Set position to SOF
        BinFileWtp_FseekBin(&gBinFileWtp,szFileName, 0L, SEEK_SET);
        uiRemainingBytes = (unsigned int)lFileSize;
    }
    else
    {
        //fseek (hFile,4L,SEEK_SET); // Set position to SOF
        BinFileWtp_FseekBin(&gBinFileWtp,szFileName, 4L, SEEK_SET);
        uiRemainingBytes = (unsigned int)lFileSize - 4;
    }

    if ((ImageType == FBFD) && me->m_bGetBadBlk && (!me->m_bEraseAllFlashOnly))
    {
        /*
        before download the FBF image, first judge the Bad block number
        */
        _tcscpy(pdev->szCurrentMsg, _T("Getting Bad Blocks......"));
        pdev->kProState = kProcDebugLog;
		WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
		WtptpDownLoad_Report(me);
        tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);

        if (!GetBadBlockInfo(pdev->pWtpComm,&WtpStatus))
        {
            _tcscpy(pdev->szCurrentMsg, _T("BBCError"));
            pdev->kProState = kProcDownloading;
			WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
			WtptpDownLoad_Report(me);

            tfprintf (pdev->hLog,_T("Error:  GetBadBlockInfo failed!\n"));
            fflush(pdev->hLog);
            //return FALSE; //Don't interrupt here, can do it in the mainfrm.cpp
        }
        else
        {
            pBadBlockData pFlashBadBlockData = (pBadBlockData)WtpStatus.Data;
            memset(&pdev->DevBadBlk, 0, sizeof(BadBlockData));
            memcpy(&pdev->DevBadBlk,pFlashBadBlockData, sizeof(BadBlockData));
            _tcscpy(pdev->szCurrentMsg, _T("BadBlkNum"));
            pdev->kProState = kProcDownloading;
			WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
			WtptpDownLoad_Report(me);

            tfprintf(pdev->hLog, _T("\nTotalBadBlocks: %d, Total Blocks: %d"),le32toh(pFlashBadBlockData->TotalBadBlocks),le32toh(pFlashBadBlockData->TotalBlocks));
            tfprintf(pdev->hLog, _T("\nImage ID: %s, bad Blocks: %d\n"),le32toh(pFlashBadBlockData->BadCount[0].ImageID),le32toh(pFlashBadBlockData->BadCount[0].BadCnt));

            tfprintf (pdev->hLog,_T("GetBadBlockInfo OK!\n"));
            fflush(pdev->hLog);
			int u32TotalBlocks = le32toh(pdev->DevBadBlk.TotalBlocks);
			int u32BadBlocks = le32toh(pdev->DevBadBlk.TotalBadBlocks);
			if ( u32BadBlocks > (int)((double)(me->m_uFlashBadBlockRate*u32TotalBlocks)/(double)BADBLOCKRATE_BASE))
			{
				_tcscpy(pdev->szCurrentMsg,_T("BadBlockRate is  out of range!"));
				pdev->kProState = kProcDebugLog;
				WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
				WtptpDownLoad_Report(me);
				tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);
				fflush(pdev->hLog);
				return FALSE;
			}
        }
    }

    pdev->kProState = kProcDownloading;
    BOOL bFastDownload = FALSE;
    //Helan2/Eden_A0 BootRom֧��fastdownload,����ƽֻ̨��BootLoader֧��fastdownload
    if(kBootLoader ==  pdev->nDevType 
		|| PLAT_EDEN_A0 ==  me->m_ePlatformType 
		|| PLAT_HELAN2 ==  me->m_ePlatformType 
		|| PLAT_ULC1  ==  me->m_ePlatformType
		|| PLAT_HELAN3 ==  me->m_ePlatformType
        || PLAT_HELAN4== me->m_ePlatformType		)
    {
        bFastDownload = TRUE;
		isFastDownload(pdev->pWtpComm,SET, TRUE);
    } 
	else
    {
    	isFastDownload(pdev->pWtpComm,SET, FALSE);
    }

    if (!DataHeader(pdev->pWtpComm,uiRemainingBytes,&WtpStatus,bFastDownload))
    {
        if (hFile != NULL)
            fclose (hFile);

        tfprintf (pdev->hLog,_T("\nData header CMD failed\n"));
        return FALSE;
    }
    else
    {
        for (int i = 0; i < (int)WtpStatus.DLEN; i++)
            uiBufferSize |= WtpStatus.Data[i] << (8 * i);
    }

	if(kBootRom==  pdev->nDevType && PLAT_EDEN_A0 ==  me->m_ePlatformType)
    {
        usleep(100000); //100ms
    }

	
    tfprintf(pdev->hLog,_T("\nReturn flag in Dataheader CMD: %d,FDSwitch is %d,BufferSize is 0x%X\n"),WtpStatus.Flags,isFastDownloadSwtchSet,uiBufferSize);
    fflush(pdev->hLog);
    if(me->m_bDebugTrace)
    {
        TCHAR szMessage[1024];
        sprintf(szMessage,_T("Return flag in Dataheader CMD: %d,FDSwitch is %d"),WtpStatus.Flags,isFastDownloadSwtchSet);
        _tcscpy(pdev->szCurrentMsg,szMessage);
        pdev->kProState = kProcDebugLog;
		WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
		WtptpDownLoad_Report(me);
        tfprintf (pdev->hLog,_T("%s"),pdev->szCurrentMsg);

    }
    if (WtpStatus.Flags & 0x4 && isFastDownloadSwtchSet)
    {
        fprintf (pdev->hLog,"\n*******NOTE:: Fast Download is NOW activated!\n");
        isFastDownload(pdev->pWtpComm,SET, TRUE);
        fflush(pdev->hLog);
    }
    else
    {
        isFastDownload(pdev->pWtpComm,SET, FALSE);
        fprintf (pdev->hLog,"\nFast Download is not activated\n");
        fflush(pdev->hLog);
    }

    unsigned int uitotalsize=uiRemainingBytes;
    double percentage;
    unsigned int downloadbytes;
	int loop =0;
    while (uiRemainingBytes > 0)
    {


        if (! isFastDownload(pdev->pWtpComm,GET, FDMODE)  && loop)
        {

            if (!DataHeader(pdev->pWtpComm,uiRemainingBytes,&WtpStatus,FALSE) )
            {
                tfprintf (pdev->hLog,_T("Error: WtpComm.DataHeader failed to receive an ACK!\n"));
                if (hFile != NULL) fclose (hFile);
                return FALSE;
            }
            else
            {
                for (int i = 0; i < (int)WtpStatus.DLEN; i++)
                    uiBufferSize |= WtpStatus.Data[i] << (8 * i);
			}

			//workaround for eden a0 bootrom failed
			if(kBootRom==  pdev->nDevType && PLAT_EDEN_A0 ==  me->m_ePlatformType)
    		{
        		usleep(100000); //100ms
    		}
        }
        loop ++;

   
        if(uiBufferSize > uiRemainingBytes)
        {
            uiBufferSize = uiRemainingBytes;
        }


        uiRemainingBytes -= uiBufferSize; // Calculate remaining bytes
        if (isFastDownload(pdev->pWtpComm,GET, FDMODE))
        {
            /* Code to see if last data */
            if(uiRemainingBytes == 0)
            {

                tfprintf (pdev->hLog,_T("Last Data\n"));
                isLastData(pdev->pWtpComm,SET, TRUE);
            }
        }


        BYTE* pSendDataBuffer = (BYTE*)malloc(sizeof(BYTE)*uiBufferSize);
        if(NULL == pSendDataBuffer)
        {
            tfprintf (pdev->hLog,_T("Molloc Memory failed in DownloadImage.\n"));
            return FALSE;
        }

        //BytesRead = fread (pSendDataBuffer,1,uiBufferSize,hFile);
		BytesRead = BinFileWtp_ReadBinFile(&gBinFileWtp,pSendDataBuffer, 1, uiBufferSize, szFileName);


        if ((BytesRead != (long)uiBufferSize))
        {

            if (hFile != NULL) fclose (hFile);
            tfprintf (pdev->hLog,_T("Error:Read file failed!\n"));
            free(pSendDataBuffer);
            return FALSE;
        }

        else
        {
                unsigned int totalSize = 0;
                unsigned int mark = 0;

                // We do not split packets based on packetSize for FastDownload

                unsigned int packetSize = isFastDownload(pdev->pWtpComm,GET, FDMODE)? uiBufferSize : GetPacketSize(pdev->pWtpComm);
                totalSize = uiBufferSize;

                if (totalSize > packetSize )
                {
                    do
                    {
                        if (!Data(pdev->pWtpComm,pSendDataBuffer + mark,packetSize) )
                        {
                            if (hFile != NULL) fclose (hFile);
                            free(pSendDataBuffer);
                            return FALSE;
                        }
                        else
                        {
                            downloadbytes=uitotalsize-uiRemainingBytes;
                            percentage=(double)(*uidownloadsize+downloadbytes)/(double)uiAllimgsize;
                            double nPercent = percentage*100;

                            pdev->kProState = kProcDownloading;
                            pdev->npercent = (int)nPercent;
							WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
							WtptpDownLoad_Report(me);
                        }

                        mark += packetSize;
                        totalSize-=packetSize;

                        if (totalSize <= packetSize)
                            packetSize = totalSize;

                    }
                    while (totalSize > 0);

                }
                else
                {
                    if (!Data(pdev->pWtpComm,pSendDataBuffer,uiBufferSize))
                    {
                        tfprintf (pdev->hLog,_T("\nData command failed\n"));
                        if (hFile != NULL) fclose (hFile);
                        free(pSendDataBuffer);
                        return FALSE;
                    }
                    else
                    {
                        downloadbytes=uitotalsize-uiRemainingBytes;
                        percentage=(double)(*uidownloadsize+downloadbytes)/(double)uiAllimgsize;
                        double nPercent = percentage*100;

                        pdev->kProState = kProcDownloading;
                        pdev->npercent = (int)nPercent;
						WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
						WtptpDownLoad_Report(me);

                    }
                }
            }

        free(pSendDataBuffer);
		pSendDataBuffer = NULL;

    }
    tfprintf (pdev->hLog,_T("Download data finished\n"));
    fflush(pdev->hLog);
    if(me->m_bDebugTrace)
    {
        pdev->kProState = kProcDebugLog;
        _tcscpy(pdev->szCurrentMsg,_T("Download data finished"));
		WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
		WtptpDownLoad_Report(me);

        tfprintf (pdev->hLog,_T("%s"),pdev->szCurrentMsg);

    }

    Done(pdev->pWtpComm);

    if (isFastDownload(pdev->pWtpComm,GET, FDMODE))
    {
        isLastData (pdev->pWtpComm,SET, FALSE);
    }

    *uidownloadsize+=uitotalsize;
    if (hFile != NULL)
        fclose (hFile);


    pdev->kProState = kProcDebugLog;
    sprintf(pdev->szCurrentMsg,_T("Completed DownLoad file: %s"),szFileName);
	WtptpDownLoad_AddDisplayInfoDevice(me,pdev);
	WtptpDownLoad_Report(me);
    tfprintf (pdev->hLog,_T("%s\n"),pdev->szCurrentMsg);
    fflush(pdev->hLog);

    return TRUE;
}


BYTE WtptpDownLoad_AckWithImageName (struct CWtptpDownLoad *me,const UINT32 ImageType,TCHAR *szFileName,const t_ImageFileList* plImageList)
{
	BYTE IsImage = NACK;

	for (t_ImageFileListConstIter ite = kl_begin(*plImageList); ite != kl_end(*plImageList); ite = kl_next(ite))
	{
		if (kl_val(ite).nFileType == ImageType)
		{
			IsImage = ACK;
			_tcscpy (szFileName,kl_val(ite).strImageFile);
			break;
		}
	}

	return IsImage;
}


#define __u32_free(x)
KLIST_INIT(u32,UINT32,__u32_free)

BOOL WtptpDownLoad_ParseTim (struct CWtptpDownLoad *me,t_ImageFileByDDRList* ImageFileByDDRlist)
{
	t_ImageFileByDDRIter DDRDownloadIMGIter = kl_begin(*ImageFileByDDRlist);
	klist_t(u32)* lImageIDList = kl_init(u32);
	while(DDRDownloadIMGIter!= kl_end(*ImageFileByDDRlist))
	{
	BOOL bFoundTim = FALSE;
	const char* strTimFile;
	for (t_ImageFileListIter ite = kl_begin(kl_val(DDRDownloadIMGIter)->ImageFileList); ite != kl_end(kl_val(DDRDownloadIMGIter)->ImageFileList); ite = kl_next(ite))
	{
		FILE* fpFile = NULL; //= _tfopen(ite->strImageFile.c_str(), _T("rb"));
		UINT32 dwTimId;
		BinFileWtp_OpenBinFile(&gBinFileWtp,_T("rb"));
		//fseek(fpFile,sizeof(UINT32),SEEK_SET);
		BinFileWtp_FseekBin(&gBinFileWtp,kl_val(ite).strImageFile, sizeof(UINT32), SEEK_SET);
		//fread(&dwTimId,sizeof(UINT32),1,fpFile);
		BinFileWtp_ReadBinFile(&gBinFileWtp,&dwTimId,sizeof(UINT32) , 1,kl_val(ite).strImageFile);
#if PRINTLOG
		printf("TIMH=0x%x dwTimId=0x%x le32toh(dwTimId)=0x%x\n",TIMH,dwTimId,le32toh(dwTimId));
#endif
		if (TIMH == le32toh(dwTimId))
		{
			if (!bFoundTim)
			{
				bFoundTim = TRUE;
				kl_val(ite).nFileType = TIMH;
				strTimFile = kl_val(ite).strImageFile;
			}
			else
			{
				printf(_T("Find two Tim image in downloadImageList\n"));
				kl_destroy(u32, lImageIDList);
				return FALSE;
			}
		}
		CloseFilePtr(&fpFile);
	}

	if (!bFoundTim)
	{
		printf(_T("\nA Tim image file was not supplied! Exiting program.\n"));
		kl_destroy(u32, lImageIDList);
		return FALSE;
	}


	FILE *hTimFile = NULL;
	CTIM TimHeader;
	/*if ((hTimFile = _tfopen (strTimFile.c_str(), _T("rb"))) == NULL)
	{
		printf(_T("\n_tfopen failed to open Tim file: %s.\n"),strTimFile.c_str());
		return FALSE;
	}*/
	if (!BinFileWtp_IsFileExist(&gBinFileWtp,strTimFile))
	{
		printf(_T("\n_tfopen failed to open Tim file: %s.\n"),strTimFile);
		kl_destroy(u32, lImageIDList);
		return FALSE;		
	}
	//fseek (hTimFile,0L,SEEK_SET); // Set position to SOF
	BinFileWtp_FseekBin(&gBinFileWtp,strTimFile, 0L, SEEK_SET);
	//fread (&TimHeader,sizeof(CTIM),1,hTimFile);
	BinFileWtp_ReadBinFile(&gBinFileWtp,&TimHeader, sizeof(CTIM), 1, strTimFile);
	int nImages = le32toh(TimHeader.NumImages);
#if PRINTLOG
	printf(_T("Number of Images listed in TIM: %d\n"),nImages);
#endif
	if (kl_size(stifl,kl_val(DDRDownloadIMGIter)->ImageFileList) != nImages)
	{
		printf(_T("Number of Images listed in TIM is %d, but provide image number is %d\n"),nImages,kl_size(stifl,kl_val(DDRDownloadIMGIter)->ImageFileList));
		kl_destroy(u32, lImageIDList);
		return FALSE;
	}

	
	if(le32toh(TimHeader.VersionBind.Version) >= TIM_3_1_01 && le32toh(TimHeader.VersionBind.Version) < TIM_3_2_00)
	{
		IMAGE_INFO_3_1_0 ImageInfo;
		for (int i = 0; i < nImages; i++)
		{
			//fread (&ImageInfo,sizeof(IMAGE_INFO_3_1_0),1,hTimFile);
			BinFileWtp_ReadBinFile(&gBinFileWtp,&ImageInfo,sizeof(IMAGE_INFO_3_1_0),1,strTimFile);
			*kl_pushp(u32,lImageIDList) = le32toh(ImageInfo.ImageID);
		}
	}
	else if(le32toh(TimHeader.VersionBind.Version) >= TIM_3_2_00&& le32toh(TimHeader.VersionBind.Version) < TIM_3_4_00)
	{
		IMAGE_INFO_3_2_0 ImageInfo;
		for (int i = 0; i < nImages; i++)
		{
			//fread (&ImageInfo,sizeof(IMAGE_INFO_3_2_0),1,hTimFile);
			BinFileWtp_ReadBinFile(&gBinFileWtp,&ImageInfo,sizeof(IMAGE_INFO_3_2_0),1,strTimFile);
			*kl_pushp(u32,lImageIDList) = le32toh(ImageInfo.ImageID);
		}
	}
	else if(TIM_3_4_00 == le32toh(TimHeader.VersionBind.Version))
	{
		IMAGE_INFO_3_4_0 ImageInfo;
		for (int i = 0; i < nImages; i++)
		{
			//fread (&ImageInfo,sizeof(IMAGE_INFO_3_4_0),1,hTimFile);
			BinFileWtp_ReadBinFile(&gBinFileWtp,&ImageInfo,sizeof(IMAGE_INFO_3_4_0),1,strTimFile);
			*kl_pushp(u32,lImageIDList) = le32toh(ImageInfo.ImageID);
		}
	}
	else if(TIM_3_5_00 == le32toh(TimHeader.VersionBind.Version))
	{
		IMAGE_INFO_3_5_0 ImageInfo;
		for (int i = 0; i < nImages; i++)
		{
			//fread (&ImageInfo,sizeof(IMAGE_INFO_3_5_0),1,hTimFile);
			BinFileWtp_ReadBinFile(&gBinFileWtp,&ImageInfo,sizeof(IMAGE_INFO_3_5_0),1,strTimFile);
			*kl_pushp(u32,lImageIDList) = le32toh(ImageInfo.ImageID);
		}
	}
	else
	{	
		printf(_T("\nTim Version is unknown:0X%X\n"),TimHeader.VersionBind.Version);
		kl_destroy(u32, lImageIDList);
		return FALSE;
	}

	CloseFilePtr(&hTimFile);

	//���image Id�Ƿ������TIM��
	BOOL bFoundInTim = FALSE;
	for (t_ImageFileListIter ite = kl_begin(kl_val(DDRDownloadIMGIter)->ImageFileList); ite != kl_end(kl_val(DDRDownloadIMGIter)->ImageFileList); ite = kl_next(ite))
	{
		if (TIMH == kl_val(ite).nFileType)
		{
			continue;
		}

		FILE* fpFile = NULL;//_tfopen(ite->strImageFile.c_str(), _T("rb"));
		UINT32 dwImageId;	
		//fread(&dwImageId, sizeof(UINT32), 1, fpFile);
		BinFileWtp_FseekBin(&gBinFileWtp,kl_val(ite).strImageFile,0L,SEEK_SET);
		BinFileWtp_ReadBinFile(&gBinFileWtp,&dwImageId, sizeof(UINT32), 1, kl_val(ite).strImageFile);
		dwImageId = le32toh(dwImageId);

		kl_val(ite).nFileType = dwImageId;
		CloseFilePtr(&fpFile);

		BOOL bFound = FALSE;
		for (kliter_t(u32) *imgIdIte = kl_begin(lImageIDList); imgIdIte != kl_end(lImageIDList);imgIdIte = kl_next(imgIdIte))
		{
			if (kl_val(imgIdIte) == dwImageId)
			{
				bFound = TRUE;
			}
		}	

		if (!bFound)
		{
			printf(_T("Tim don't contain ImageId 0X%X, imageFile:%s"), dwImageId,kl_val(ite).strImageFile);
			kl_destroy(u32, lImageIDList);
			return FALSE;
		}
	}

	//���TIM�а�����image�Ƿ����
	for (kliter_t(u32) * ite = kl_begin(lImageIDList); ite != kl_end(lImageIDList); ite = kl_next(ite))
	{
		BOOL bFound = FALSE;
		for (t_ImageFileListIter imgFileListIte = kl_begin(kl_val(DDRDownloadIMGIter)->ImageFileList);\
			imgFileListIte != kl_end(kl_val(DDRDownloadIMGIter)->ImageFileList);\
			imgFileListIte = kl_next(imgFileListIte))
		{
			if (kl_val(ite) == kl_val(imgFileListIte).nFileType)
			{
				bFound = TRUE;
			}
		}	

		if (!bFound)
		{
			printf(_T("Tim contains imageId 0X%X, but the image file don't exist."),*ite);
			kl_destroy(u32, lImageIDList);
			return FALSE;
		}
	}
	DDRDownloadIMGIter = kl_next(DDRDownloadIMGIter);
  }
	kl_destroy(u32, lImageIDList);
	return TRUE;
}


BOOL WtptpDownLoad_UploadDataFromTarget(struct CWtptpDownLoad *me,PDEVICE pDev)
{
    if(pDev->ThreadExit==STOPFLAG)
    {
        printf(_T("Thread is to be exit"));
        return FALSE;
    }

    _tcscpy(pDev->szCurrentMsg,_T("Enter into UploadDataFromTarget....."));
    pDev->kProState = kProcDebugLog;
    WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
    WtptpDownLoad_Report(me);
    tfprintf (pDev->hLog,_T("%s"),pDev->szCurrentMsg);

    MESSAGE_MODES currentMessageMode = DISABLED;
    WTPSTATUS WtpStatus = {0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00};
    isFastDownload (pDev->pWtpComm,SET, TRUE);
    tfprintf (pDev->hLog,_T("Enter Upload Data\n"));
    eProcessState  eProcState;
    long  uiAllimgsize=0;
    long uiUploadsize=0;
    SetPacketSize(pDev->pWtpComm,USBPACKETSIZE);
    int retryAttempts = 3;
    tfprintf (pDev->hLog,_T("\nBegin OpenUsbPort\n"));
    fflush(pDev->hLog);
    if (!OpenUsbPort (pDev->pWtpComm))
    {
        _tcscpy(pDev->szCurrentMsg,_T("Can not open USB....."));
        pDev->kProState = kProcDebugLog;
		WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
		WtptpDownLoad_Report(me);
        tfprintf (pDev->hLog,_T("%s"),pDev->szCurrentMsg);

        return FALSE;
    }
    else
        SetPortType(pDev->pWtpComm,0);//set usb port as default

    _tcscpy(pDev->szCurrentMsg,_T("Waiting for Uploading data..."));
    pDev->kProState = kProcDebugLog;
    WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
    WtptpDownLoad_Report(me);

    if(me->m_bCustPreamble)
    {
        tprintf (_T("\nCustomize Preamble Mode\n"));
    }
    else
    {
        tprintf (_T("\nOriginal Preamble Mode\n"));
    }


    t_UpLoadDataSpecIter iter;
    iter = kl_begin(*me->m_lpUpLoadDataSpecList);
    UPLOAD_DATA_SPEC* pUploadSpec = NULL;
    while ( iter != kl_end(*me->m_lpUpLoadDataSpecList) )
    {

        if (!SendPreamble(pDev->pWtpComm,me->m_bCustPreamble))
        {
            return FALSE;
        }
        else
        {

            PROTOCOL_VERSION TargetProtocolVersion;
            memset( &TargetProtocolVersion, 0, sizeof(TargetProtocolVersion) );
            if ( GetProtocolVersion (pDev->pWtpComm, &TargetProtocolVersion ) )
            {
                if ( TargetProtocolVersion.MajorVersion >= TARGET_PROTOCOL_VERSION.MajorVersion
                     && TargetProtocolVersion.MinorVersion >= TARGET_PROTOCOL_VERSION.MinorVersion
                     && TargetProtocolVersion.Build >= TARGET_PROTOCOL_VERSION.Build )
                {
                    TARGET_PARAMS TargetParams;
                    if (GetParameters(pDev->pWtpComm, &TargetParams ) )
                    {

                        pUploadSpec = kl_val(iter);
                        UINT32 OriginalUploadBytes = pUploadSpec->m_Params.DataSize;

                        tprintf (_T("\n"));
                        tprintf (_T("\n"));
                        tprintf (_T("Uploading:\n"));
                        tprintf (_T("Type: %d\n"), kl_val(iter)->m_Params.Type);
                        tprintf (_T("SubType: %d\n"), kl_val(iter)->m_Params.SubType );
                        tprintf (_T("Partition: %d\n"), kl_val(iter)->m_Params.Partition );
                        if(FLASH_EMMC==me->m_FlashType)
                        {
                            tprintf (_T("Offset: %d\n"), (kl_val(iter)->m_Params.Offset*512));
                        }
                        else
                        {
                            tprintf (_T("Offset: %d\n"), (kl_val(iter)->m_Params.Offset));
                        }
                        tprintf (_T("DataSize: %d\n"), kl_val(iter)->m_Params.DataSize);
                        tprintf (_T("Upload Save file name is: %s\n"), kl_val(iter)->strOutputFileName.s);
                        tprintf (_T("ResetUE: %d\n"), (kl_val(iter)->m_Params.ResetUE));
                        tprintf (_T("ResetTimeDelay: %d\n"), kl_val(iter)->m_Params.ResetTimeDelay);
                        tprintf (_T("\n"));
                        tprintf (_T("\n"));
                        tfprintf (pDev->hLog,_T("Uploading:\n"));
                        tfprintf (pDev->hLog,_T("Type: %d\n"), kl_val(iter)->m_Params.Type);
                        tfprintf (pDev->hLog,_T("SubType: %d\n"), kl_val(iter)->m_Params.SubType );
                        tfprintf (pDev->hLog,_T("Partition: %d\n"), kl_val(iter)->m_Params.Partition );
                        if(FLASH_EMMC==me->m_FlashType)
                        {
                            tfprintf (pDev->hLog,_T("Offset: %d\n"), (kl_val(iter)->m_Params.Offset*512));
                        }
                        else
                        {
                            tfprintf (pDev->hLog,_T("Offset: %d\n"), (kl_val(iter)->m_Params.Offset));
                        }
                        tfprintf (pDev->hLog,_T("DataSize: %d\n"), kl_val(iter)->m_Params.DataSize);
                        tfprintf (pDev->hLog,_T("ResetUE: %d\n"), (kl_val(iter)->m_Params.ResetUE));
                        tfprintf (pDev->hLog,_T("ResetTimeDelay: %d\n"), kl_val(iter)->m_Params.ResetTimeDelay);
                        fflush(pDev->hLog);
                        TCHAR szOutPutFileName[MAX_PATH] = {0};
                        TCHAR szComFileName[MAX_PATH] = {0};
                        strncpy( szOutPutFileName, pUploadSpec->strOutputFileName.s, MAX_PATH );
                        tfprintf (pDev->hLog,_T("Output File: %s\n"), szOutPutFileName);
                        //begin to save upload data into FILE
                        FILE* ofs = NULL;
                        if (pUploadSpec->bCreateNewFile)
                        {
							ofs = fopen(szOutPutFileName,"a+");
                        }
                        else
                        {
                            ofs = fopen(szOutPutFileName,"a+");
                        }
                        if ( ofs == NULL )
                        {
                            tfprintf (pDev->hLog,_T("Can't open file: %s\n"), szOutPutFileName);
                            return FALSE;
                        }

                        strncpy( szComFileName, pUploadSpec->strComparisonFileName.s, MAX_PATH);
                        tfprintf (pDev->hLog,_T("Comparison File: %s\n"), szComFileName);
                        TCHAR Msg[1024];
                        sprintf(Msg,_T("Begin to upload data from 0x%x to 0x%x to file %s"),kl_val(iter)->m_Params.Offset*512,kl_val(iter)->m_Params.Offset*512+kl_val(iter)->m_Params.DataSize,szOutPutFileName);
                        tfprintf (pDev->hLog,_T("%s"),Msg);
                        //Report(kProcDebugLog, Msg, pDev);

                        if ( UploadDataHeader(pDev->pWtpComm, &pUploadSpec->m_Params ) )
                        {
                            unsigned int  UploadBytes = pUploadSpec->m_Params.DataSize;
                            if(me->m_nFlashDataPageSize>0&&pUploadSpec->m_Params.IncludeSpareAreas==UPLOAD_WITH_SPAREAREA)
                            {
                                UploadBytes +=(((int)(UploadBytes)/me->m_nFlashDataPageSize))*(me->m_nFlashDataPageSize/32);
                            }
                            unsigned int BytesRemaining = UploadBytes;
                            tfprintf (pDev->hLog,_T("\n All Bytes to upload is %d\n"),BytesRemaining);
                            unsigned int BytesWritten = 0;
                            unsigned int uiWholesize = BytesRemaining;
                            unsigned int BytesReceived = 0;
                            unsigned int uiBufferLength = 0;
                            if(pUploadSpec->m_Params.IncludeSpareAreas==UPLOAD_WITH_SPAREAREA)
                            {
                                sprintf(Msg,_T("\nUploading data with Spare Area from 0x%x to 0x%x to file %s\n"),kl_val(iter)->m_Params.Offset*512,kl_val(iter)->m_Params.Offset*512+OriginalUploadBytes,szOutPutFileName);
                            }
                            else
                            {
                                sprintf(Msg,_T("\nUploading data from 0x%x to 0x%x to file %s\n"),kl_val(iter)->m_Params.Offset*512,kl_val(iter)->m_Params.Offset*512+OriginalUploadBytes,szOutPutFileName);
                            }

                            //Report(kProcDebugLog, Msg, pDev);
                            tprintf (_T("%s"),Msg);
                            BYTE* pUploadDataBuffer = (BYTE*) malloc(sizeof(BYTE)*8186);
                            WTPSTATUS* pWtpStatus = (WTPSTATUS*)malloc(sizeof(WTPSTATUS));
                            while ( BytesRemaining > 0 )
                            {
                                uiBufferLength = ( BytesRemaining<TargetParams.BufferSize-6?BytesRemaining:TargetParams.BufferSize-6);
                                if ( pUploadDataBuffer )
                                {
                                    memset( pUploadDataBuffer, 0, uiBufferLength);

                                    memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
                                    if ( !UploadData(pDev->pWtpComm, pUploadDataBuffer, uiBufferLength,pWtpStatus))
                                    {

                                        tprintf (_T("Error: Upload Failed!\n"));
                                        free(pUploadDataBuffer);

                                        UINT32 ReturnCode = 0;
                                        int i   ;
                                        for ( i = 0; i < 4; i++)
                                        {
                                            ReturnCode |= pWtpStatus->Data[i] << (8 * i);
                                        }
                                        if((pWtpStatus->DLEN >0))
                                        {
                                            tfprintf (pDev->hLog,_T("\nAbort in upload data because of MESSAGE ERRORCODE \n"));
                                            //ReportError(eProcState = kProcDebugLog, stBurningFlashError,_T("Upload data Error"), pDev,ReturnCode);
                                            TCHAR szMessage[1024];
                                            tprintf (_T(" ERROR CODE: %X\n"), ReturnCode );
                                            //tfprintf (pDev->hLog,szMessage);
                                            return FALSE;

                                        }
                                        return FALSE;
                                    }
                                    else
                                    {
										fwrite(pUploadDataBuffer,sizeof(BYTE),uiBufferLength,ofs);
                                        BytesWritten +=uiBufferLength;
                                        double percentage;
                                        BytesReceived  += uiBufferLength;
                                        percentage=(double)(BytesReceived)/(double)uiWholesize;
                                        int nPercent = percentage*100;
                                        tprintf (_T("Uploading file percentage is:%d\r"), nPercent);
                                        BytesRemaining -= uiBufferLength;

                                    }
                                }
                            }

                            free(pWtpStatus);
                            pWtpStatus = NULL;
                            tprintf(_T("Finish to upload data to file %s\n"),szOutPutFileName);

                            //Report(kProcDebugLog, Msg, pDev);
                            free(pUploadDataBuffer);

                            tfprintf (pDev->hLog,_T("Finish saving upload data file %s!\n"),szOutPutFileName);
                            fflush(pDev->hLog);

                        }
                        else
                        {
                            tfprintf (pDev->hLog,_T("UploadDataheader Failed!\n"));
                            tprintf (_T("UploadDataheader Failed!\n"));
                            return FALSE;
                        }

                        fclose(ofs);

                        iter = kl_next(iter);
                        if(!Done(pDev->pWtpComm))
                        {
                            tprintf(_T("Done CMD failed in Upload\n"));
                            break;
                        }


                    }
                    else
                    {
                        tfprintf (pDev->hLog,_T("GetParameters failed.....\n"));
                        tprintf(_T("GetParameters failed.....\n"));
                        return FALSE;

                    }
                }

            }
            else
            {
                tfprintf (pDev->hLog,_T("GetProtocolVersion failed.....\n"));
                tprintf(_T("GetProtocolVersion failed.....\n"));
                return FALSE;
            }
        }
    }
    tfprintf (pDev->hLog ,_T("Upload procedure finished\n"));
    fflush(pDev->hLog);
    tprintf (_T("Upload procedure finished\n"));
    WTPSTATUS WTPStatus = {0x00, 0x00, 0x00, 0x01, 0x00, 0x00};
    Disconnect(pDev->pWtpComm,&WTPStatus);

    return TRUE;
}



UINT32 WtptpDownLoad_GetWTPTPMSGReturnCode(struct CWtptpDownLoad *me,WTPSTATUS *pWtpStatus)
{
    UINT32 ReturnCode = 0;
    int i   ;
    for ( i = 0; i < 4; i++)
    {
        ReturnCode |= pWtpStatus->Data[i+2] << (8 * i);
    }
    return ReturnCode;
}
BOOL WtptpDownLoad_ValidateWTPTPMSGReport(struct CWtptpDownLoad *me,PDEVICE pDev, WTPSTATUS *pWtpStatus, UINT32 *ReturnCode)
{
    *ReturnCode = 0;
    int i   ;
    for ( i = 0; i < 4; i++)
    {
        *ReturnCode |= pWtpStatus->Data[i+2] << (8 * i);
    }

    if(pWtpStatus->Data[0]== WTPTPNOTIFICATION)
    {
        BOOL bFound = FALSE;
        for (i = 0; i < MAXNOTIFICATIONSCODES; i++)
        {
            if (WTPTPNotificationMsg[i].NotificationCode == *ReturnCode)
            {
#ifndef COMPRESSDATA
                tfprintf (pDev->hLog,_T("\nWTPTP Notification: %s ,Notification code is :0x%X\n"),WTPTPNotificationMsg[i].Description,*ReturnCode);
#else
                tfprintf (pDev->hLog,_T("\nWTPTP Notification code is :0x%X\n"),*ReturnCode);
#endif
                fflush(pDev->hLog);
                bFound = TRUE;
                break;;
            }

        }
        if(!bFound)
        {
            TCHAR Msg[1024];
            sprintf(Msg,_T("\nNotification Code: 0x%X\n"),*ReturnCode);
            tfprintf (pDev->hLog,_T("%s"),Msg);
            fflush(pDev->hLog);
        }

        if((*ReturnCode == PlatformEraseAllFlash)&&(!me->m_bEraseAllFlash))
        {
            
            tfprintf (pDev->hLog,_T("\n Do unexpected erase all flash in OBM\n"));
            fflush(pDev->hLog);
            return FALSE;

        }

        if((*ReturnCode == PlatformResetBBT)&&(!me->m_bResetBBT))
        {
          
            tfprintf (pDev->hLog,_T("\n Do unexpected ResetBBT in OBM\n"));
            fflush(pDev->hLog);
            return FALSE;

        }
        return TRUE;
    }
    else if(pWtpStatus->Data[0]== WTPTPERRORREPORT)
    {
        TCHAR szMessage[1024];
        BOOL bFound = FALSE;
        for (i = 0; i < MAXNOTIFICATIONSCODES; i++)
        {
            if (WTPTPErrorCodes[i].ErrorCode == *ReturnCode)
            {
				#ifndef COMPRESSDATA
                sprintf (szMessage,_T("\nWTPTP Error: %s 0x%X\n"),WTPTPErrorCodes[i].Description,*ReturnCode );
                #else
				sprintf (szMessage,_T("\nWTPTP Error: 0x%X\n"),*ReturnCode );
				#endif
                tfprintf (pDev->hLog,_T("%s"),szMessage);
                fflush(pDev->hLog);
                bFound = TRUE;
                break;
            }
        }
        tfprintf (pDev->hLog,_T("%s"),szMessage);
        return FALSE;

    }
    return TRUE;
}

BOOL    WtptpDownLoad_WTPTPDownLoad(struct CWtptpDownLoad *me,PDEVICE pDev)
{
#if PRINTLOG
    tprintf(_T("Enter into WTPTPDownLoad\n"));
#endif
    if(pDev->ThreadExit==STOPFLAG)
    {
        tfprintf(pDev->hLog,_T("Thread is to be exit"));
        fflush(pDev->hLog);
        return FALSE;
    }
	
    pDev->kProState = kProcDebugLog;
    _tcscpy(pDev->szCurrentMsg,_T("Enter into WTPTPDownLoad...."));
    WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
    WtptpDownLoad_Report(me);
    tfprintf (pDev->hLog,_T("%s"),pDev->szCurrentMsg);

    MESSAGE_MODES currentMessageMode = DISABLED;
    WTPSTATUS WtpStatus = {0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00};
    isFastDownload (pDev->pWtpComm,SET, TRUE);
    tfprintf (pDev->hLog,_T("Enter WTPTPDownload\n"));
    fflush(pDev->hLog);
    if(me->m_bEraseAllFlash)
    {
        tfprintf (pDev->hLog,_T("Erase all flag FBF file\n"));
    }
    if(me->m_bResetBBT)
    {
        tfprintf (pDev->hLog,_T("Reset flag in FBF file\n"));
    }
    if(me->m_bGetBadBlk)
    {
        tfprintf (pDev->hLog,_T("Flash bad block report is enabled in FBF file\n"));
    }
    if(me->m_bImageCrcEnable)
    {
        tfprintf (pDev->hLog,_T("Image Crc report is enabled in FBF file\n"));
    }
    t_ImageFileList *pimgfilesList;
    if(pDev->nDevType == kBootLoader)
    {
        pimgfilesList = me->m_plBootLoaderImageList;
    }
    else if(pDev->nDevType == kBootRom)
    {
        pimgfilesList = me->m_plBootRomImageList;
    }
    else
    {
        return FALSE;
    }
	
    FILE* hFile;
    eProcessState  eProcState;
    TCHAR szFileName[MAX_PATH];
    UINT64 uiAllimgsize=0;
    UINT64 uidownloadsize=0;
    UINT32 uiCurrentFileSize = 0;
	for (t_ImageFileListConstIter ite = kl_begin(*pimgfilesList); ite != kl_end(*pimgfilesList); ite = kl_next(ite))
	{  
		if(TIMH == kl_val(ite).nFileType)
		{
			//uiAllimgsize += GetFileSize(ite->strImageFile.c_str());
			uiAllimgsize += BinFileWtp_GetFileSize(&gBinFileWtp,kl_val(ite).strImageFile);
		}
		else
		{
			//uiAllimgsize += GetFileSize(ite->strImageFile.c_str()) - IMAGEID_LEN;
			uiAllimgsize += BinFileWtp_GetFileSize(&gBinFileWtp,kl_val(ite).strImageFile) - IMAGEID_LEN;
		}
	}
	
    SetPacketSize(pDev->pWtpComm,USBPACKETSIZE);

    //FileIndex = nImages; // Just in case user supplies more files than required
    BOOL retry=TRUE;
    int retryAttempts = 3;
    tfprintf (pDev->hLog,_T("\nBegin OpenUsbPort\n"));
    SetPortType(pDev->pWtpComm,0);//set usb port as default


    pDev->kProState = kProcDebugLog;
    _tcscpy(pDev->szCurrentMsg,_T("Start Image Downloading..."));
    WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
    WtptpDownLoad_Report(me);
    tfprintf (pDev->hLog,_T("%s"),pDev->szCurrentMsg);

    if(me->m_bCustPreamble)
    {
        tfprintf (pDev->hLog,_T("\nCustomize Preamble Mode\n"));
    }
    else
    {
        tfprintf (pDev->hLog,_T("\nOriginal Preamble Mode\n"));
    }
    fflush(pDev->hLog);	

	int nImageNum = kl_size(stifl,*pimgfilesList);
    for (int i = 0; i < nImageNum; ++i)
    {
        if(pDev->ThreadExit == STOPFLAG)
        {
            return FALSE;
        }

        if(0 != GetLinuxDev(pDev->pWtpComm)->hDevHandle)
        {
            char strDownloadImgName[256];
            if (WtptpDownLoad_DownloadImage (me,pDev,i, pimgfilesList,uiAllimgsize,&uidownloadsize,nImageNum,strDownloadImgName) == FALSE)
            {                
              
                 tfprintf (pDev->hLog,_T("\nRetry to DownloadImage: %s\n"),strDownloadImgName);
				  return FALSE;
            }
            else //Download completed
            {       

                if(i!=0&&pDev->nDevType == kBootLoader)
                {

                    WTPSTATUS *pWtpStatus = (WTPSTATUS*)malloc(sizeof(WTPSTATUS));
                    hFile = NULL;//_tfopen(strDownloadImgName.c_str(),_T("rb"));
                    double npercent;
                    BOOL bIsEraseAllDone = FALSE;
                    BOOL bIsEraseAllOnlyDone = FALSE;
                    //fseek (hFile,0L,SEEK_END);
					BinFileWtp_FseekBin(&gBinFileWtp,strDownloadImgName,0L,SEEK_END);
                    if(i==0)
                        {
                        	uiCurrentFileSize = BinFileWtp_GetFileSize(&gBinFileWtp,strDownloadImgName);
                        	//uiCurrentFileSize = ftell(hFile);
                    	}
                    else
                        {
                        	uiCurrentFileSize = BinFileWtp_GetFileSize(&gBinFileWtp,strDownloadImgName) - 4;
                        	//uiCurrentFileSize = ftell(hFile)-4;
                    	}
                    long uiDownloadSize = 0;
                    UINT32 WtptpReturnCode = 0;
                    UINT32 uiBurntSize = 4096;//  first sector is no need to burnt to falsh , so add this size
                    //fclose(hFile);

                     tfprintf (pDev->hLog,_T("\nBegin Buring image %s,size %d\n"),strDownloadImgName,uiCurrentFileSize);

                    pWtpStatus->Status = ACK;

                    switch(me->m_ePlatformType)
                    {
                        case PLAT_PXA92x:
                        {
                            tfprintf (pDev->hLog,_T("\n PXA92x burning flash.... \n"));
                            fflush(pDev->hLog);
                            while (pWtpStatus->Status == ACK)
                            {


                                if(pDev->ThreadExit == STOPFLAG)
                                {
                                    pDev->kProState = kProcAborting;
									WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
									WtptpDownLoad_Report(me);
									free(pWtpStatus);
									pWtpStatus = NULL;
                                    return FALSE;
                                }
                                if (! GetWtpMessage (pDev->pWtpComm,pWtpStatus))
                                {
                                    break;
                                }
                                else
                                {

                                    if(pWtpStatus->Data[0]>ERRORFLAG)
                                    {
                                        tfprintf (pDev->hLog,_T("\nAbort becasue of MESSAGE ERRORCODE \n"));
                                        TCHAR szMessage[1024];
                                        sprintf (szMessage,_T(" ERROR CODE: %X\n"), pWtpStatus->Data[0]  );
                                        tfprintf (pDev->hLog,_T("%s"),szMessage);
                                        fflush(pDev->hLog);
										free(pWtpStatus);
										pWtpStatus = NULL;
                                        return FALSE;
                                    }
                                }
                                // This is to add a delay for WTPTP while the flash is being erased by DKB.
                                if (pWtpStatus->Data[0] == PXA92x_PlatformBusy )
                                {
                                    pDev->kProState = kProcDebugLog;
                                    _tcscpy(pDev->szCurrentMsg,_T("Begin Burning flash..."));
									WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
									WtptpDownLoad_Report(me);
                                    tfprintf (pDev->hLog,_T("%s"),pDev->szCurrentMsg);
                                    fflush(pDev->hLog);
                                    pDev->kProState=kProcBurningFlash;
                                    unsigned long int DelayTime_tmp = 0;
                                    do
                                    {

                                       GetWtpMessage( pDev->pWtpComm,pWtpStatus);
                                        if(pWtpStatus->Data[0]>ERRORFLAG)
                                        {
                                            tfprintf (pDev->hLog,_T("\nAbort becasue of MESSAGE ERRORCODE \n"));
                                            TCHAR szMessage[1024];
                                            sprintf (szMessage,_T(" ERROR CODE: %X\n"), pWtpStatus->Data[0]  );
                                            tfprintf (pDev->hLog,_T("%s"),szMessage);
                                            fflush(pDev->hLog);
											free(pWtpStatus);
										    pWtpStatus = NULL;
                                            return FALSE;
                                        }
                                        if ( pWtpStatus->Data[0] == PXA92x_PlatformDisconnect )
                                            break;
                                        if(pDev->ThreadExit == STOPFLAG)
                                        {
                                            pDev->kProState = kProcAborting;
											WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
											WtptpDownLoad_Report(me);
											free(pWtpStatus);
										    pWtpStatus = NULL;
                                            return FALSE;
                                        }

                                        if(DelayTime_tmp>2000*5000)
                                        {
                                            tfprintf (pDev->hLog,_T("\nBurning flash timeout\n"));
                                            fflush(pDev->hLog);
                                            break;
                                        }
                                        usleep(1000000);
                                        npercent= (double)uiDownloadSize*100/(double)uiCurrentFileSize;
                                        uiDownloadSize +=me->m_nBurningSpeed*1000;

                                        pDev->kProState = kProcBurningFlash;
                                        pDev->npercent = (int)npercent;
										WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
										WtptpDownLoad_Report(me);
                                        DelayTime_tmp += 1000;
                                    }
                                    while(pWtpStatus->Data[0] != PXA92x_PlatformReady);
                                }
                                if ( pWtpStatus->Data[0] == PXA92x_PlatformDisconnect )
                                {
                                    tfprintf (pDev->hLog,_T("\nAbort in Burnning flash\n"));
                                    fflush(pDev->hLog);
                                    pDev->kProState = kProcDebugLog;
                                    _tcscpy(pDev->szCurrentMsg,_T("Abort in Burnning flash"));
									WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
									WtptpDownLoad_Report(me);
									free(pWtpStatus);
									pWtpStatus = NULL;
                                    return FALSE;
                                }

                                if ( pWtpStatus->Data[0] == PXA92x_PlatformReady )
                                {
                                    npercent = 100;
                                    pDev->kProState = kProcBurningFlash;
                                    pDev->npercent = (int)npercent;
									WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
									WtptpDownLoad_Report(me);
                                    tfprintf (pDev->hLog,_T("\nBurnning flash Successfully\n"));
                                    fflush(pDev->hLog);

                                    break;
                                }

                            }
                        }
                        break;
                        default:
                        {

                            while (pWtpStatus->Status == ACK)
                            {

                                if(pDev->ThreadExit == STOPFLAG)
                                {
                                    pDev->kProState = kProcAborting;
									WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
									WtptpDownLoad_Report(me);
									free(pWtpStatus);
									pWtpStatus = NULL;
                                    return FALSE;
                                }


                                if (! GetWtpMessage (pDev->pWtpComm,pWtpStatus))
                                {
                                    tfprintf (pDev->hLog,_T("\nGetWtpMessage failed before burning flash\n"));
                                    fflush(pDev->hLog);
                                    break;
                                    if((pWtpStatus->DLEN >0))
                                    {
                                        if(! WtptpDownLoad_ValidateWTPTPMSGReport(me,pDev,pWtpStatus,&WtptpReturnCode))
                                        {
                                        	free(pWtpStatus);
										    pWtpStatus = NULL;
                                            return FALSE;
                                        }
                                    }
                                }
                                // This is to add a delay for WTPTP while the flash is being erased by DKB.
                                if (WtptpDownLoad_GetWTPTPMSGReturnCode(me,pWtpStatus)== PlatformBusy )
                                {

                                    pDev->kProState = kProcDebugLog;
                                    _tcscpy(pDev->szCurrentMsg,_T("Begin Burning flash..."));
									WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
									WtptpDownLoad_Report(me);
                                    tfprintf (pDev->hLog,_T("%s"),pDev->szCurrentMsg);
                                    fflush(pDev->hLog);



                                    pDev->kProState=kProcBurningFlash;
                                    unsigned long int DelayTime_tmp = 0;
                                    UINT32 FlashSize = 0;
                                    do
                                    {

                                        if(pDev->ThreadExit == STOPFLAG)
                                        {
                                            pDev->kProState = kProcAborting;
											WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
											WtptpDownLoad_Report(me);
											free(pWtpStatus);
										    pWtpStatus = NULL;
                                            return FALSE;
                                        }

                                        if(!GetWtpMessage(pDev->pWtpComm,pWtpStatus))
                                        {
                                            tfprintf (pDev->hLog,_T("\nGetWtpMessage failed\n"));
                                            fflush(pDev->hLog);
											free(pWtpStatus);
										    pWtpStatus = NULL;
                                            return FALSE;
                                        }
                                        else
                                        {

                                            if((pWtpStatus->DLEN >0))
                                            {
                                                if(!WtptpDownLoad_ValidateWTPTPMSGReport(me,pDev,pWtpStatus,&WtptpReturnCode))
                                                {
                                                	free(pWtpStatus);
										            pWtpStatus = NULL;
                                                    return FALSE;
                                                }

                                                else
                                                {
                                                    if(pWtpStatus->Data[0]== WTPTPNOTIFICATION_BURNTSIZE)
                                                    {                                          
                                                        uiBurntSize+=WtptpReturnCode;
                                                        // make a round to burnt size to multiple of 4096(FBF_Sector size)
                                                        if(uiBurntSize%4096)
                                                        {
                                                            uiBurntSize+=((4096-(uiBurntSize%4096)));
                                                        }
                                                        WtptpReturnCode = 0;
                                                        npercent= (double)uiBurntSize/(double)uiCurrentFileSize;
														npercent = npercent*100;
                                                        uiDownloadSize =uiBurntSize;

                                                        pDev->npercent = (int)npercent;
														WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
														WtptpDownLoad_Report(me);
                                                    }
                                                    if((WtptpReturnCode == PlatformEraseAllFlashDone))
                                                    {
                                                        bIsEraseAllDone = TRUE;

                                                    }

                                                    if((WtptpReturnCode == PlatformEraseAllFlashWithoutBurnDone))
                                                    {
                                                        bIsEraseAllOnlyDone = TRUE;

                                                    }



                                                }

                                            }

                                        }

                                        if(DelayTime_tmp>2000*5000)
                                        {
                                            tfprintf (pDev->hLog,_T("\nBurning flash timeout\n"));
                                            fflush(pDev->hLog);
                                            break;
                                        }
                                        usleep(1000000);
                                        DelayTime_tmp += 1000;

                                        if(me->m_bEraseAllFlash&&(!bIsEraseAllDone)&&(i==1))
                                        {

                                            if(FLASH_SPINOR==me->m_FlashType)
                                            {
                                                if(FlashSize == 0x2000000)//32M
                                                    npercent+=SPINOR_32M_ERASE_SPEED;
                                                else
                                                    npercent+=SPINOR_16M_ERASE_SPEED;
                                            }
                                            else if(FLASH_EMMC == me->m_FlashType)
                                            {
                                                npercent+=EMMC_ERASE_SPPED;
                                            }
                                            else if(FLASH_SPINAND==me->m_FlashType)
                                            {
                                                npercent+=EMMC_ERASE_SPPED;
                                            }
                                            else
                                                npercent+=NAND_ERASE_SPPED;
                                            pDev->kProState = kProcEraseAllFlash;
                                            pDev->npercent = (int)npercent;
                                            WtptpDownLoad_AddDisplayInfoDevice(me,pDev);

                                        }

                                        if(me->m_bEraseAllFlashOnly&&(!bIsEraseAllOnlyDone)&&(i==1))
                                        {


                                            if(FLASH_SPINOR==me->m_FlashType)
                                            {
                                                if(FlashSize == 0x2000000)//32M
                                                    npercent+=SPINOR_32M_ERASE_SPEED;
                                                else
                                                    npercent+=SPINOR_16M_ERASE_SPEED;
                                            }
                                            else if(FLASH_EMMC == me->m_FlashType)
                                            {
                                                npercent+=EMMC_ERASE_SPPED;
                                            }
                                            else if(FLASH_SPINAND==me->m_FlashType)
                                            {
                                                npercent+=EMMC_ERASE_SPPED;
                                            }
                                            else
                                                npercent+=NAND_ERASE_SPPED;
                                            pDev->kProState = kProcEraseAllFlash;
                                            pDev->npercent = (int)npercent;
                                            WtptpDownLoad_AddDisplayInfoDevice(me,pDev);

                                        }


                                        else
                                        {                 
                                            npercent= (double)uiDownloadSize*100/(double)uiCurrentFileSize;
                                            uiDownloadSize +=me->m_nBurningSpeed*1000;

                                            pDev->kProState = kProcBurningFlash;
                                            pDev->npercent = (int)npercent;
                                            WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
                                        }
                                        WtptpDownLoad_Report(me);

                                        if ( WtptpDownLoad_GetWTPTPMSGReturnCode(me,pWtpStatus) == PlatformDisconnect )
                                            break;

                                    }
                                    while(WtptpDownLoad_GetWTPTPMSGReturnCode(me,pWtpStatus) != PlatformReady);
                                }
                                if ( WtptpDownLoad_GetWTPTPMSGReturnCode(me,pWtpStatus) == PlatformDisconnect )
                                {
                                    tfprintf (pDev->hLog,_T("\nPlatformDisconnect\n"));
                                    fflush(pDev->hLog);
                                    pDev->kProState = kProcDebugLog;
                                    _tcscpy(pDev->szCurrentMsg,_T("PlatformDisconnect"));
                                    WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
                                    WtptpDownLoad_Report(me);
                                    tfprintf (pDev->hLog,_T("%s"),pDev->szCurrentMsg);
                                    fflush(pDev->hLog);
									free(pWtpStatus);
									pWtpStatus = NULL;
                                    return FALSE;
                                }

                                if ( WtptpDownLoad_GetWTPTPMSGReturnCode(me,pWtpStatus) == PlatformReady )
                                {

                                    npercent = 100;
                                    pDev->kProState = kProcBurningFlash;
                                    pDev->npercent = (int)npercent;
                                    WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
                                    WtptpDownLoad_Report(me);


                                    tfprintf (pDev->hLog,_T("\nBurnning flash Successfully\n"));
                                    fflush(pDev->hLog);
                                    break;
                                }

                            }
                        }
                        break;
                    }

                    free(pWtpStatus);
                    pWtpStatus = NULL;
                }
            }

        }
        else
        {
            tfprintf (pDev->hLog,_T("\nIOThead is not exist\n"));
            fclose (pDev->hLog);
            return FALSE;
        }
    }

    WTPSTATUS WTPStatus = {0x00, 0x00, 0x00, 0x01, 0x00, 0x00};

    if(me->m_bImageCrcEnable && (!me->m_bEraseAllFlashOnly))
    {
        tfprintf (pDev->hLog,_T("\nGetting ImageCrc...\n"));
        fflush(pDev->hLog);

        if (!GetImageCrc(pDev->pWtpComm,&WTPStatus))
        {
            _tcscpy(pDev->szCurrentMsg,_T("CRCERROR"));
            pDev->kProState = kProcBurningFlash;
			WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
			WtptpDownLoad_Report(me);

            tfprintf (pDev->hLog,_T("Error:  GetImageCrc failed!\n"));
            fflush(pDev->hLog);
            //return FALSE;//Don't interrupt here, can do it in the mainfrm.cpp
        }
        else
        {
            pImageCRCInfo pImageCrc = (pImageCRCInfo)WTPStatus.Data;
            memset(&pDev->DevImageCrc, 0, sizeof(ImageCRCInfo));
            memcpy(&pDev->DevImageCrc, pImageCrc, sizeof(ImageCRCInfo));              
            _tcscpy(pDev->szCurrentMsg,_T("CRCS"));
            pDev->kProState = kProcBurningFlash;
			WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
			WtptpDownLoad_Report(me);

            fprintf(pDev->hLog, _T("\n MCPID: 0x%x, ImageNum: %d, "),le32toh(pImageCrc->MCPID), le32toh(pImageCrc->ImageNum));
            for(UINT32 i = 0; i < le32toh(pImageCrc->ImageNum); i++)
                fprintf(pDev->hLog, _T("\n ImageID: 0x%x, CrcData: 0x%08X"),le32toh(pImageCrc->ImageCRC[i].ImageID), le32toh(pImageCrc->ImageCRC[i].CRC32));

        }
    }

    tfprintf (pDev->hLog,_T("\nBegin to disconnect\n"));
    Disconnect(pDev->pWtpComm,&WTPStatus);

	if(kBootRom==  pDev->nDevType && PLAT_EDEN_A0 ==  me->m_ePlatformType)
    {
        usleep(100000); //100ms
    }

    tfprintf (pDev->hLog,_T("\nFinish to disconnect\n"));
    fflush(pDev->hLog);

    _tcscpy(pDev->szCurrentMsg,_T("Finish to disconnect"));
    pDev->kProState = kProcDebugLog;
	WtptpDownLoad_AddDisplayInfoDevice(me,pDev);
	WtptpDownLoad_Report(me);

    return TRUE;
}




BOOL WtptpDownLoad_TerminateBL(struct CWtptpDownLoad *me)
{
    if(!me->m_binitFlag)  // there is no InitializeBL
        return TRUE;
#if PRINTLOG
    tprintf(_T("\nTerminateBL.....\n"));
#endif
	pthread_mutex_lock(&me->Quit_mutex);
    me->m_bTerminateDownload = TRUE;
    me->m_bTerminateUSBDetect = TRUE;
    pthread_mutex_unlock(&me->Quit_mutex);
	
	// kill all download thread for all device
	usleep(2000000);
	pthread_mutex_lock(&me->DeviceList_mutex);					
	for(t_DeviceIter iter = kl_begin(me->m_WtptpDeviceList);iter != kl_end(me->m_WtptpDeviceList); iter = kl_next(iter))
	{
        if((kl_val(iter)) != NULL)
        {
            (kl_val(iter))->ThreadExit = STOPFLAG;
            SetExitHandle((kl_val(iter))->pWtpComm,1);   
            usleep(2000000);
            CloseUsbPort((kl_val(iter))->pWtpComm);
            free((kl_val(iter))->pWtpComm);
            (kl_val(iter))->pWtpComm = NULL;
            free(kl_val(iter));
        }
	}
	pthread_mutex_unlock(&me->DeviceList_mutex);  
#if PRINTLOG
    tprintf(_T("\nplease wait .....\n"));
#endif
	usleep(100000);
	BinFileWtp_CloseBinFIle(&gBinFileWtp);
    return TRUE;
}

#if 0
BOOL WtptpDownLoadInitializeBLEx(struct CWtptpDownLoad *me,PInstanceParams pInstParam,const TCHAR * pszBLFfileName ,const TCHAR * pszFBFTimFile,const TCHAR * pszFBFfileName)
{
#ifdef PCIEDOWNLOAD
    _tprintf(_T("\nInitializeBLEx parameter.....\n"));

    if(_tcslen(pszBLFfileName)==0)
    {
        _tprintf(_T("\nblf file is empty.....\n"));
        return FALSE;
    }
    else
    {
        if(_taccess(pszBLFfileName,0)!=0)
        {
            _tprintf(_T("\n%s is not exist.....\n"),pszBLFfileName);
            return FALSE;
        }

    }


    if(_tcslen(pszFBFTimFile)==0)
    {
        _tprintf(_T("\nFBF tim file is empty.....\n"));
        return FALSE;
    }
    else
    {
        if(_taccess(pszFBFTimFile,0)!=0)
        {
            _tprintf(_T("\n%s is not exist.....\n"),pszFBFTimFile);
            return FALSE;
        }

    }

    if(_tcslen(pszFBFfileName)==0)
    {
        _tprintf(_T("\nFBF file is empty.....\n"));
        return FALSE;
    }
    else
    {
        if(_taccess(pszFBFfileName,0)!=0)
        {
            _tprintf(_T("\n%s is not exist.....\n"),pszFBFfileName);
            return FALSE;
        }

    }
    me->m_bOnlyOBMDownload = TRUE;

    CParser blfparser;
    me->m_ePlatformType =  blfparser.GetPlatFormType(pszBLFfileName);
    me->m_FlashType = blfparser.GetFlashType(pszBLFfileName);
    pInstParam->PlaformType = me->m_ePlatformType;
    pInstParam->FlashType = me->m_FlashType;
    // m_nFlashDataPageSize = pInstParam->FlashPageSize;

    /*tstring ss = pszFBFTimFile;
    m_ImageList.push_back(ss);
    ss = pszFBFfileName;
    m_ImageList.push_back(ss);*/
	DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC* lpDdrFlashDLImgInfoSpec = new DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC();
	lpDdrFlashDLImgInfoSpec->pImagelist->push_back(new string(pszFBFTimFile));
	lpDdrFlashDLImgInfoSpec->pImagelist->push_back(new string(pszFBFfileName));
	pInstParam->pDownloadImagesList = new t_DdrFlashDownloadImgInfoList();
	pInstParam->pDownloadImagesList->push_back(lpDdrFlashDLImgInfoSpec);

    pInstParam->pszDKBbin = NULL;
    pInstParam->pszDKBTim = NULL;
    pInstParam->pszWTMFile =  NULL;
    pInstParam->pszOBMFile =  NULL;
   
    pInstParam->PlaformType = (unsigned int)m_ePlatformType;
    pInstParam->FlashType = (unsigned int)m_FlashType;

    eEraseAllMode m_eEraseAllFlash = (eEraseAllMode)blfparser.GetBlfInt(pszFLASH_OPTIONS,pszERASE_ALL_FLASH,0,pszBLFfileName);
    BOOL m_bResetBBT = blfparser.GetBlfInt(pszFLASH_OPTIONS,pszRESET_BBT,-1,pszBLFfileName);

    unsigned int nCommand = 0;
    if(m_eEraseAllFlash==ERASE_ALL_BEFOREBURNING)
    {
        nCommand|=DLCMD_DO_ERASE_ALL_FLASH_MSK;
    }
    if(m_bResetBBT)
    {
        nCommand|=DLCMD_DO_RESETBBT_MSK;
    }
    if(m_eEraseAllFlash==ERASE_ALL_WIHTOUTBURNING)
    {
        nCommand|=DLCMD_DO_ERASE_ALL_FLASH_ONLY_MSK;
    }

    pInstParam->Commands =nCommand;


    WtptpDownLoad_InitializeBL(me,pInstParam);
#endif
    return TRUE;
}
#endif


BOOL WtptpDownLoad_InitializeBL(struct CWtptpDownLoad *me,PInstanceParams pInstParam)
{
    int iBootRomFileIndex = 0,iBootLoaderFileIndex=0;
    me->m_nBootRomDevNum = 0;
    me->m_nBootLoaderDevNum = 0;
    readlink ("/proc/self/exe", me->m_szSWDPath, MAX_FILE_LENGTH);
    TCHAR *p = _tcsrchr( me->m_szSWDPath,'/');
    if(p) *p = 0;
#if PRINTLOG
    tprintf(_T("SWD Path is %s \n"),me->m_szSWDPath);
    //getwd(m_szSWDPath);
    tprintf(_T("Begin to initialize WTPTPDownload parameter\n"));
#endif
	if (strlen(g_LogPath) > 0)
	{
		strncpy(me->m_szSWDPath,g_LogPath,_countof(me->m_szSWDPath));
	}
    int res = pthread_mutex_init(&me->DeviceList_mutex,NULL);
    if(res!=0)
    {
#if PRINTLOG
        perror(_T("DeviceList_mutex initialization failed"));
#endif
		exit(EXIT_FAILURE);
    }
    /*res = pthread_mutex_init(&Device_mutex,NULL);
    if(res!=0)
    {
        perror(_T("Device Mutex initialization failed"));
        exit(EXIT_FAILURE);
    }*/

    res = pthread_mutex_init(&me->Quit_mutex,NULL);
    if(res!=0)
    {
#if PRINTLOG
        perror(_T("Quit_mutex initialization failed"));
#endif
		exit(EXIT_FAILURE);
    }

    res = pthread_mutex_init(&me->callback_mutex,NULL);
    if(res!=0)
    {
#if PRINTLOG
        perror(_T("callback_mutex initialization failed"));
#endif
		exit(EXIT_FAILURE);
    }


    kl_clear(pdisl,me->m_DisplayInfoList);
    me->m_lpInstParam = pInstParam;
    me->m_nFlashDataPageSize = pInstParam->FlashPageSize;
    me->m_ePlatformType = (ePlatForm)pInstParam->PlaformType;
    me->m_FlashType = (eFlashType)pInstParam->FlashType;
  
    if(me->m_FlashType==FLASH_NAND)
    {
        me->m_nBurningSpeed = NAND_BURNNING_SPEED;
    }
    else if(me->m_FlashType==FLASH_EMMC)
    {
        me->m_nBurningSpeed = EMMC_BURNNING_SPEED;
    }
    else
    {
        me->m_nBurningSpeed = SPINOR_BURNNING_SPEED;
    }

    me->m_bEraseAllFlash   = (((pInstParam->Commands)&DLCMD_DO_ERASE_ALL_FLASH_MSK) ==DLCMD_DO_ERASE_ALL_FLASH_MSK)?TRUE:FALSE;
    me->m_bEraseAllFlashOnly = (((pInstParam->Commands)&DLCMD_DO_ERASE_ALL_FLASH_ONLY_MSK) ==DLCMD_DO_ERASE_ALL_FLASH_ONLY_MSK)?TRUE:FALSE;
    me->m_bResetBBT        = (((pInstParam->Commands)&DLCMD_DO_RESETBBT_MSK) == DLCMD_DO_RESETBBT_MSK)?TRUE:FALSE;
    me->m_bSingleDownload = (pInstParam->DownloadMode==1)?TRUE:FALSE;
	me->m_bGetBadBlk			= (pInstParam->GetBadBlk==1)?TRUE:FALSE;
	me->m_bImageCrcEnable		= (pInstParam->ImageCrcEn==1)?TRUE:FALSE;
    memset(me->m_szPrimaryDkbPath,0,sizeof(me->m_szPrimaryDkbPath));
    memset(me->m_szPrimTimPath,0,sizeof(me->m_szPrimTimPath));
    memset(me->m_szOBMPath, 0, sizeof(me->m_szOBMPath));
    memset(me->m_szWTMPath, 0, sizeof(me->m_szWTMPath));
    memset(me->m_szTZIPath, 0 ,sizeof(me->m_szTZIPath));

    me->m_lpUpLoadDataSpecList = me->m_lpInstParam->pUploadSpecs;
    me->m_bDumpFlash  = (((pInstParam->Commands)&DLCMD_DO_UPLOAD_DATA_MSK) ==DLCMD_DO_UPLOAD_DATA_MSK)?TRUE:FALSE;
	me->m_uFlashBadBlockRate	= pInstParam->ReservedVal[0];//坏块率门限

	
	if(me->m_bDumpFlash)
	{
		if (!WtptpDownLoad_prepareDumpFlashParam(me,pInstParam))
		{
			printf (_T("prepareDumpFlashParam failed.\n"));
			return FALSE;
		}
	}	
	else if(me->m_bEnabledJtag)
	{
		if (!WtptpDownLoad_prepareEnabledJtagImg(me,pInstParam))
		{
			printf(_T("Prepare enabledJtag images failed.\n"));
			return FALSE;
		}				
	} 
	else
	{
		BinFileWtp_InitParameter(&gBinFileWtp);
		if (!WtptpDownLoad_prepareDownloadImg(me,pInstParam))
		{
#if PRINTLOG
			printf(_T("Prepared download image failed."));
#endif
			return FALSE;
		}
#if PRINTLOG
		printf(_T("\nParse DKB Tim image.\n"));
#endif
		BinFileWtp_InitRead(&gBinFileWtp);
		if (!WtptpDownLoad_ParseTim(me,&me->m_lBootRomImageWithDDRList))
		{
			printf(_T("Parse DKB Tim failed.\n"));
			return FALSE;
		}
#if PRINTLOG
		printf(_T("\nParse FBF Tim image.\n"));
#endif
		if (!WtptpDownLoad_ParseTim(me,&me->m_lBootLoaderImageWithDDRList))
		{
			printf(_T("Parse FBF Tim failed.\n"));
			return FALSE;
		}
	}

	
	me->m_binitFlag = TRUE;
#if PRINTLOG
    tprintf(_T("\nComplete to Initilize parameter\n"));
#endif
	fflush(stdout);

    res = pthread_create(&me->DetectThread, NULL,WtptpDownLoad_WtptpDeviceDetectThread ,me);
    if(res!=0)
    {
#if PRINTLOG
        perror (_T("\nThread creation failed\n"));
#endif
        return FALSE;
    }
    else
    {
#if PRINTLOG
        tprintf(_T("\nBegin to detect wtptp device....\n"));	
#endif
    }	
	fflush(stdout);
    return TRUE;
}


BOOL WtptpDownLoad_prepareDumpFlashParam(struct CWtptpDownLoad *me,const PInstanceParams pInstParam)
{
#if PRINTLOG
	printf(_T("Prepare UpLoadDataSpecList for dump flash\n"));
#endif
	if(NULL == pInstParam->pUploadSpecs || kl_size(pudsl,*pInstParam->pUploadSpecs)==0)
	{
		printf(_T(" Upload area list is NULL"));
		return FALSE;
	}		


	me->m_lpUpLoadDataSpecList = (t_UpLoadDataSpecList*)malloc(sizeof(t_UpLoadDataSpecList));
	(*me->m_lpUpLoadDataSpecList) = kl_init(pudsl);
	for (t_UpLoadDataSpecIter iter = kl_begin(*pInstParam->pUploadSpecs);
		iter != kl_end(*pInstParam->pUploadSpecs);
		iter = kl_next(iter))
	{
		pUPLOAD_DATA_SPEC pTmp;
		pTmp = (UPLOAD_DATA_SPEC*)malloc(sizeof(UPLOAD_DATA_SPEC));
		*kl_pushp(pudsl,*me->m_lpUpLoadDataSpecList) = pTmp;
		NewUPLOAD_DATA_SPEC(pTmp,kl_val(iter));
	}		

	return TRUE;
}

BOOL WtptpDownLoad_prepareEnabledJtagImg(struct CWtptpDownLoad *me,const PInstanceParams pInstParam)
{
#if PRINTLOG
	printf(_T("Prepare BR images for enabled Jtag\n"));
#endif
	int nJtagEnabledImgIdx = 0;
	if (pInstParam->pszDKBTim)	//check if user enter any security file path.
	{		
		if (!IsFileExist(pInstParam->pszDKBTim))
		{  
		    tprintf(_T("DKBTim file %s is not exist"),pInstParam->pszDKBTim);	
			return FALSE;
		}	
		struct stImageFile stTmp;
		stTmp.nFileType = TIMH;
		stTmp.strImageFile = pInstParam->pszDKBTim;
		*kl_pushp(stifl,*me->m_plJtagEnabledImageList) = stTmp;
	}
	else
	{
	     tprintf(_T("Miss Timheader image in re-enabled jtag."));		
		 return FALSE;
	}

	if (pInstParam->pszDKBbin)
	{
		if (!IsFileExist(pInstParam->pszDKBbin))
		{  
		    tprintf(_T("DKB file %s is not exist"),pInstParam->pszDKBbin);	
			return FALSE;
		}
		struct stImageFile stTmp;
		stTmp.nFileType = OBMI;
		stTmp.strImageFile = pInstParam->pszDKBbin;
		*kl_pushp(stifl,*me->m_plJtagEnabledImageList) = stTmp;	
	}
	else
	{
	    tprintf(_T("Miss OBM image in re-enabled jtag."));	
		return FALSE;
	}

	if (pInstParam->pszTZIIFile)
	{
		if (!IsFileExist(pInstParam->pszTZIIFile))
		{  
			tprintf(_T("TZII file %s is not exist"),pInstParam->pszTZIIFile);		
			return FALSE;
		}
		struct stImageFile stTmp;
		stTmp.nFileType = TZII;
		stTmp.strImageFile = pInstParam->pszTZIIFile;
		*kl_pushp(stifl,*me->m_plJtagEnabledImageList) = stTmp;		
	}

	for (t_ImageFileListIter ite = kl_begin(*me->m_plJtagEnabledImageList); ite != kl_end(*me->m_plJtagEnabledImageList); ite = kl_next(ite))
	{
		if (!IsFileExist(kl_val(ite).strImageFile))
		{
			tprintf(_T("%s image don't exist:%s"),stringer(kl_val(ite).nFileType),kl_val(ite).strImageFile);
			return FALSE;
		}
	}



/*	if (pInstParam->pszJTAGKeyFile)	// check if user enter any security file path.
	{
		if (!IsFileExist(pInstParam->pszJTAGKeyFile))
		{  
			tprintf(_T("JTAGKeyFile file %s is not exist "),pInstParam->pszJTAGKeyFile);		
			return FALSE;
		}
		m_strJtagKeyFile = pInstParam->pszJTAGKeyFile;
	}
	else
	{
		tprintf(_T("Miss JtagKeyFile in re-enabled jtag."));	
		return FALSE;
	}*/
	return TRUE;
}

BOOL WtptpDownLoad_prepareDownloadImg(struct CWtptpDownLoad *me,const PInstanceParams pInstParam)
{
 	BOOL bIsBootRomlistPrepared = FALSE;
	if(0==kl_size(dfdil,*pInstParam->pDownloadImagesList))
		return FALSE;

	
	t_DdrFlashDownloadImgInfoIter DDRDownloadIMGIter = kl_begin(*pInstParam->pDownloadImagesList);
		while(DDRDownloadIMGIter!= kl_end(*pInstParam->pDownloadImagesList))
		{
			
			struct stImageFileByDDR *pImageFileByDDRBL = (struct stImageFileByDDR*)malloc(sizeof(struct stImageFileByDDR));
			memset(pImageFileByDDRBL,0,sizeof(struct stImageFileByDDR));
			New_stImageFileByDDR(pImageFileByDDRBL);
			t_stringListIter imageiter = kl_begin(*kl_val(DDRDownloadIMGIter)->pImagelist);
			me->m_uTotalDDRTypeNum = kl_val(DDRDownloadIMGIter)->TotalVendorDDRTypeNum;
			me->m_uTotalFlashTypeNum =kl_val(DDRDownloadIMGIter)->TotalFlashTypeNum;

			while(imageiter!=kl_end(*kl_val(DDRDownloadIMGIter)->pImagelist))
			{
				//if (!IsFileExist((*imageiter)->c_str()))
				if (!BinFileWtp_IsFileExist(&gBinFileWtp,kl_val(imageiter)->s))
				{
					tprintf(_T("File %s can't exist\n"),kl_val(imageiter)->s);
					return FALSE;
				}
				struct stImageFile stiTmp;
				stiTmp.nFileType = 0;
				stiTmp.strImageFile = kl_val(imageiter)->s;
				*kl_pushp(stifl,pImageFileByDDRBL->ImageFileList) = stiTmp;
				imageiter = kl_next(imageiter);
			}
			
			pImageFileByDDRBL->sDDRVendorID = (kl_val(DDRDownloadIMGIter))->sVendorDDRId;
			pImageFileByDDRBL->sFlashInfo = (kl_val(DDRDownloadIMGIter))->sFlashInfo;
			*kl_pushp(stifdl,me->m_lBootLoaderImageWithDDRList) = pImageFileByDDRBL;

			if(bIsBootRomlistPrepared)
			{
				DDRDownloadIMGIter = kl_next(DDRDownloadIMGIter);
				continue;
			}
			
			 bIsBootRomlistPrepared = TRUE;
			 struct stImageFileByDDR *pImageFileByDDRBR = (struct stImageFileByDDR*)malloc(sizeof(struct stImageFileByDDR));
			 memset(pImageFileByDDRBR,0,sizeof(struct stImageFileByDDR));
			 New_stImageFileByDDR(pImageFileByDDRBR);
             pImageFileByDDRBR->sDDRVendorID = kl_val(DDRDownloadIMGIter)->sVendorDDRId;
			 pImageFileByDDRBR->sFlashInfo = kl_val(DDRDownloadIMGIter)->sFlashInfo;
            

			if (pInstParam->pszDKBTim)	// check if user enter any security file path.
			{
				//if (!IsFileExist(pInstParam->pszDKBTim))
				if (!BinFileWtp_IsFileExist(&gBinFileWtp,pInstParam->pszDKBTim))
				{
					tprintf(_T("DKB Tim header file %s is not exist "),pInstParam->pszDKBTim);
					return FALSE;
				}				
				struct stImageFile stiTmp;
				stiTmp.nFileType = TIMH;
				stiTmp.strImageFile = pInstParam->pszDKBTim;
				*kl_pushp(stifl,pImageFileByDDRBR->ImageFileList) = stiTmp;
			}

			if(pInstParam->pszDKBbin)
			{
				//if (!IsFileExist(pInstParam->pszDKBbin))
				if (!BinFileWtp_IsFileExist(&gBinFileWtp,pInstParam->pszDKBbin))
				{
					tprintf(_T("DKB Bin file %s is not exist "),pInstParam->pszDKBbin);
					return FALSE;
				}
				struct stImageFile stiTmp;
				stiTmp.nFileType = DKBI;
				stiTmp.strImageFile = pInstParam->pszDKBbin;
				*kl_pushp(stifl,pImageFileByDDRBR->ImageFileList) = stiTmp;
			}

			if (PLAT_MMP2 == me->m_ePlatformType)
			{
				if(pInstParam->pszOBMFile)
				{
					//if (!IsFileExist(pInstParam->pszOBMFile))
					if (!BinFileWtp_IsFileExist(&gBinFileWtp,pInstParam->pszOBMFile))
					{
						tprintf(_T("OBM Bin file %s is not exist "),pInstParam->pszOBMFile);
						return FALSE;
					}
					struct stImageFile stiTmp;
					stiTmp.nFileType = OBMI;
					stiTmp.strImageFile = pInstParam->pszOBMFile;
					*kl_pushp(stifl,pImageFileByDDRBR->ImageFileList) = stiTmp;
				}
			}

			if (PLAT_MMP2 == me->m_ePlatformType 
				|| PLAT_MMP3 == me->m_ePlatformType
				|| PLAT_EDEN== me->m_ePlatformType 
				|| PLAT_EDEN_A0 == me->m_ePlatformType
				|| PLAT_HELAN2== me->m_ePlatformType
				|| PLAT_HELAN3== me->m_ePlatformType
				|| PLAT_HELAN4== me->m_ePlatformType)
			{
				if(pInstParam->pszWTMFile)
				{
					//if (!IsFileExist(pInstParam->pszWTMFile))
					if (!BinFileWtp_IsFileExist(&gBinFileWtp,pInstParam->pszWTMFile))
					{
						tprintf(_T("WTM Bin file %s is not exist "),pInstParam->pszWTMFile);
					}		
					struct stImageFile stiTmp;
					stiTmp.nFileType = WTMI;
					stiTmp.strImageFile = pInstParam->pszWTMFile;
					*kl_pushp(stifl,pImageFileByDDRBR->ImageFileList) = stiTmp;
				}
			}

			if (PLAT_EDEN== me->m_ePlatformType 
				|| PLAT_EDEN_A0 == me->m_ePlatformType
				|| PLAT_HELAN2== me->m_ePlatformType 
				|| PLAT_ULC1 == me->m_ePlatformType
				|| PLAT_HELAN3== me->m_ePlatformType
        		|| PLAT_HELAN4== me->m_ePlatformType
				|| PLAT_ULC2== me->m_ePlatformType)
			{
				if(pInstParam->pszTZIIFile)
				{
					//if (!IsFileExist(pInstParam->pszTZIIFile))
					if (!BinFileWtp_IsFileExist(&gBinFileWtp,pInstParam->pszTZIIFile))
					{
						tprintf(_T("TZI Bin file %s is not exist "),pInstParam->pszTZIIFile);
						return FALSE;
					}
					struct stImageFile stiTmp;
					stiTmp.nFileType = TZII;
					stiTmp.strImageFile = pInstParam->pszTZIIFile;
					*kl_pushp(stifl,pImageFileByDDRBR->ImageFileList) = stiTmp;
				}
			}

			*kl_pushp(stifdl,me->m_lBootRomImageWithDDRList) = pImageFileByDDRBR;
			
			DDRDownloadIMGIter = kl_next(DDRDownloadIMGIter);
		}
	
	
		t_ImageFileByDDRIter Iter = kl_begin(me->m_lBootRomImageWithDDRList);
		me->m_plBootRomImageList = &((kl_val(Iter))->ImageFileList);
#if PRINTLOG
		printf("Prepared download image\n");
#endif
	return TRUE;
}

void WtptpDownLoad_ResetParameter(struct CWtptpDownLoad *me)
{
	me->m_plBootRomImageList=NULL; 
	me->m_plBootLoaderImageList=NULL; 
	me->m_plJtagEnabledImageList=NULL;

	t_ImageFileByDDRIter DDRDownloadIMGIter = kl_begin(me->m_lBootRomImageWithDDRList);
	while(DDRDownloadIMGIter!= kl_end(me->m_lBootRomImageWithDDRList))
	{
	  free(kl_val(DDRDownloadIMGIter));
	  DDRDownloadIMGIter = kl_next(DDRDownloadIMGIter);
	}
	kl_clear(stifdl,me->m_lBootRomImageWithDDRList);

	 DDRDownloadIMGIter = kl_begin(me->m_lBootLoaderImageWithDDRList);
	while(DDRDownloadIMGIter!= kl_end(me->m_lBootLoaderImageWithDDRList))
	{
	  free(kl_val(DDRDownloadIMGIter));
	  DDRDownloadIMGIter = kl_next(DDRDownloadIMGIter);
	}
	kl_clear(stifdl,me->m_lBootLoaderImageWithDDRList);

	DDRDownloadIMGIter = kl_begin(me->m_lJtagEnabledImageWithDDRList);
	while(DDRDownloadIMGIter!= kl_end(me->m_lJtagEnabledImageWithDDRList))
	{
	  free(kl_val(DDRDownloadIMGIter));
	  DDRDownloadIMGIter = kl_next(DDRDownloadIMGIter);
	}
	kl_clear(stifdl,me->m_lJtagEnabledImageWithDDRList);

}

eDDREMMCMatchResult WtptpDownLoad_HandleDownloadImagesByDDRIDandEMMCSize(struct CWtptpDownLoad *me,UINT32 uiDdrVendorId, UINT32 uiDdrUnitSize,UINT32 uiEMMCSize)
{
	if(kl_size(stifdl,me->m_lBootLoaderImageWithDDRList)>1)
	{
		//Verify�Ƿ���map������ֱ�ӱ���
		//verify�ǲ�������׼����DDR�б�����ڣ���ֱ�ӱ������ڣ�����m_lBootRomImageList/m_lBootLoaderImageList/m_lJtagEnabledImageList
		BOOL IsVendorIDisknown = FALSE;
		for (int idx = 0; idx < MAX_DDR_VENDOR_NUM; ++idx)		
		{					
			if (vendorDdrPidNameMap[idx].nDdrVendorID == uiDdrVendorId)			
			{				
				IsVendorIDisknown = TRUE;				
				break;			
			}				
		}

		if(!IsVendorIDisknown)
			return kDDRMismatchError;


		BOOL bIsDDRFileispreparedBL = FALSE;
		BOOL bIsEMMCFileispreparedBL = FALSE;
		UINT32 uiDdrPid = (uiDdrVendorId<<8)|uiDdrUnitSize;
		t_ImageFileByDDRIter Iter = kl_begin(me->m_lBootLoaderImageWithDDRList);
		while(Iter!=kl_end(me->m_lBootLoaderImageWithDDRList))
		{
	
			if(me->m_uTotalDDRTypeNum>0&&1==me->m_uTotalFlashTypeNum)//Multiple DDR and Single EMMC size type 
			{
				if(Str2Uint32((kl_val(Iter))->sDDRVendorID.s) == uiDdrPid)
				{
					bIsDDRFileispreparedBL = TRUE;
					bIsEMMCFileispreparedBL = TRUE;
					me->m_plBootLoaderImageList = &(kl_val(Iter))->ImageFileList;
					break;
				}
			}
			else if(me->m_uTotalDDRTypeNum==0&&me->m_uTotalFlashTypeNum>1)//Single DDR and Multiple EMMC size type 
			{
				UINT32 uiEMMCSizecfg = TranslateEx((kl_val(Iter))->sFlashInfo)/UNIT_GB;
				//��(*Iter)->sEMMCSizeת��Ϊ����֮���512M��������֮�Ƚ�
				if( uiEMMCSizecfg== uiEMMCSize)
				{
					bIsDDRFileispreparedBL = TRUE;
					bIsEMMCFileispreparedBL = TRUE;
					me->m_plBootLoaderImageList = &(kl_val(Iter))->ImageFileList;
					break;
				}

			}
			else if(me->m_uTotalFlashTypeNum>1&&me->m_uTotalDDRTypeNum>0)//Multiple DDR and Multiple EMMC size type 
			{
				UINT32 uiEMMCSizecfg = TranslateEx((kl_val(Iter))->sFlashInfo)/UNIT_GB;
				if(uiEMMCSizecfg == uiEMMCSize&& Str2Uint32((kl_val(Iter))->sDDRVendorID.s) == uiDdrPid)
				{
					bIsDDRFileispreparedBL = TRUE;
					bIsEMMCFileispreparedBL = TRUE;
					me->m_plBootLoaderImageList = &(kl_val(Iter))->ImageFileList;
					break;
				}
			}
			else
			{
				return kImagePreparationError; //total DDR num and EMMCSize num maybe error
			}
			Iter = kl_next(Iter);
		}
		if(me->m_uTotalDDRTypeNum>0&&!bIsDDRFileispreparedBL)
			return kDDRMismatchError;
		if(me->m_uTotalFlashTypeNum>1&&!bIsDDRFileispreparedBL)
			return kDDRMismatchError;

	}
	else
	{
		t_ImageFileByDDRIter Iter = kl_begin(me->m_lBootLoaderImageWithDDRList); 
		me->m_plBootLoaderImageList = &((kl_val(Iter))->ImageFileList);
	}

  return kMatchNoError;
}

eDDREMMCMatchResult WtptpDownLoad_HandleNandDLImgByDDRID(struct CWtptpDownLoad *me,UINT32 uiDdrVendorId, UINT32 uiDdrUnitSize)
{
	if(kl_size(stifdl,me->m_lBootLoaderImageWithDDRList)>1)
	{
		BOOL bFound = FALSE;
		for (int idx = 0; idx < MAX_DDR_VENDOR_NUM; ++idx)		
		{			
			if (vendorDdrPidNameMap[idx].nDdrVendorID == uiDdrVendorId)			
			{				
				bFound = TRUE;				
				break;			
			}				
		}

		if(!bFound)
		{
			return kDDRMismatchError;
		}

		UINT32 uiDdrPid = (uiDdrVendorId<<8)|uiDdrUnitSize;
		BOOL bFoundNandId = FALSE;		
		for(t_ImageFileByDDRIter ite = kl_begin(me->m_lBootLoaderImageWithDDRList); ite != kl_end(me->m_lBootLoaderImageWithDDRList); ite = kl_next(ite))
		{			
			if(Str2Uint32((kl_val(ite))->sDDRVendorID.s) == uiDdrPid)
			{
				me->m_plBootLoaderImageList = &(kl_val(ite))->ImageFileList;
				bFoundNandId = TRUE;
				break;
			}
		}

		if(!bFoundNandId)
		{
			return kDDRMismatchError;
		}
	}
	else
	{
		t_ImageFileByDDRIter Iter = kl_begin(me->m_lBootLoaderImageWithDDRList); 
		me->m_plBootLoaderImageList = &((kl_val(Iter))->ImageFileList);
	}

	return kMatchNoError;
}

   
char*  WtptpDownLoad_replace_all(char* str,const char*  old_value,const char* new_value)     
{     
	char buf[256]={0};
	char *p = NULL,*pstr = str;
	int lo = strlen(old_value);
	p = strstr(pstr, old_value);
	while (p)
	{
		strncat(buf, pstr, p-pstr);
		strcat(buf, new_value);
		pstr = p + lo;
		p = strstr(pstr,old_value);
	}
	strcat(buf,pstr);
	strcpy(str, buf);
    return   str;     
}     


EDeviceType WtptpDownLoad_GetDeviceType(struct CWtptpDownLoad *me,ePlatForm ePlatfromType,const char* strDate,const char* strVersion ,const char* strProcessor)
{
	for (int idx = 0; idx < sizeof(gstFlatformBLInfoSet)/sizeof(gstFlatformBLInfoSet[0]); ++idx)
	{
		if (gstFlatformBLInfoSet[idx].ePlatFormType == ePlatfromType)
		{
			if((NULL != strstr(strDate, gstFlatformBLInfoSet[idx].strBLDate))
				&&(NULL != strstr(strProcessor,gstFlatformBLInfoSet[idx].strBLProcessor) )
				&&(NULL != strstr(strVersion,gstFlatformBLInfoSet[idx].strBLVersion)) ) 
			{
				return kBootLoader;
			}
			else
			{
				return kBootRom;
			}
		}
	}
	return kNone;
}



