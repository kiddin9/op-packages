#include <errno.h>

#include "CommonFun.h"
#include "downloader.h"
#include "WtptpDownLoad.h"
#include <sys/time.h>
#include "ParaDefine.h"
#include "BinFileWtp.h"
#include "kstring.h"
#include "fbfdownload.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <syslog.h>
#include <sys/stat.h>
#include <endian.h>

#define SUCCEED   0
#define FAILED	  1

#define  MIN_ARGS   3

#define FBF_TIMHEADER 'i'
#define FBF_FILE	'f'
#define DKB_TIMHEADER 't'
#define DKB_FILE	'd'
#define BIN_FILE	'b'
#define LOG_PATH	'p'
// #define PLATFORM_TYPE 'p'

#define MAX_FILE_LENGTH 256


kstring_t g_DkbTimPath={0,0,NULL}, g_DkbFilePath={0,0,NULL}, g_BinFilePath={0,0,NULL};

kstring_t strDeviceDetectFile={0,0,NULL};
BOOL bDownload = TRUE;
BOOL bUpload = FALSE;
BOOL bSingle = TRUE;
BOOL btimeoutset = FALSE;
BOOL bIgnoreBlankLines = TRUE;
int  exit_code = -1;
int  timeout = 0;

pthread_mutex_t mutex;
pthread_cond_t cond;

int g_nDownloadPercent = 0;
int g_nBurnPercent = 0;

const TCHAR* pszSWDReleaseDate = _T("2020-6-19");
const TCHAR* pszSWDReleaseVersion = _T("4.9.0.7");

//char SWDLOCKFILE[255] = "/var/run/swdlinux.pid";
char SWDLOCKFILE[255] = "./fbfdownloader.pid";
extern char g_LogPath[255];

#define LOCKMODE (S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH)

#if DEBUG_MODE
BOOL bDebugTrace = TRUE;
#else
BOOL bDebugTrace = FALSE;
#endif


int lockfile(int fd)
{
	struct flock fl;

	fl.l_type = F_WRLCK;
	fl.l_start = 0;
	fl.l_whence = SEEK_SET;
	fl.l_len = 0;
	return(fcntl(fd, F_SETLK, &fl));
}

int already_running(void)
{
	int     fd;
	if (strlen(g_LogPath) > 0)
	{
		strncpy(SWDLOCKFILE,g_LogPath,_countof(SWDLOCKFILE));
		strncat(SWDLOCKFILE,"/fbfdownloader.pid",_countof(SWDLOCKFILE));
	}
	fd = open(SWDLOCKFILE, O_RDWR | O_CREAT, LOCKMODE);
	if (fd < 0) {
		//syslog(LOG_ERR, "can't open %s: %s", SWDLOCKFILE, strerror(errno));
#if PRINTLOG
		printf("can't open %s: %s", SWDLOCKFILE, strerror(errno));
#endif
		exit(1);
	}
	if (lockfile(fd) < 0) {
		if (errno == EACCES || errno == EAGAIN) {
			close(fd);
			return(1);
		}
		//syslog(LOG_ERR, "can't lock %s: %s", SWDLOCKFILE, strerror(errno));
#if PRINTLOG
		printf("can't lock %s: %s", SWDLOCKFILE, strerror(errno));
#endif
		exit(1);
	}
	//close(fd);
	return(0);
}

BOOL ParseCommandLine(int argc, char* argv[])
{
	int currentOption = 1;
	BYTE Option = 0;

	while (currentOption < argc)
	{

		if (*argv[currentOption] == '-')
		{
			Option = *++argv[currentOption++];

			switch (Option)
			{
			case FBF_FILE:
			{
/*
				TCHAR szFbfPath[MAX_FILE_LENGTH];
				memset(szFbfPath, 0, sizeof(TCHAR)*MAX_FILE_LENGTH);
				_tcscpy(szFbfPath, argv[currentOption]);
				tstring strFbfPath(szFbfPath);

				g_lpFbfImageList->push_back(strFbfPath);
*/
			}
			break;
			case FBF_TIMHEADER:
			{
				/*
				TCHAR szFbfTimPath[MAX_FILE_LENGTH];
				memset(szFbfTimPath, 0, sizeof(TCHAR)*MAX_FILE_LENGTH);
				_tcscpy(szFbfTimPath, argv[currentOption]);
				tstring strFbfTimPath(szFbfTimPath);

				g_lpFbfImageList->push_front(strFbfTimPath);
				*/
			}
			break;
			case DKB_FILE:
			{
			//	g_DkbFilePath = argv[currentOption];
			}
			break;
			case DKB_TIMHEADER:
			{
			//	g_DkbTimPath = argv[currentOption];
			}
			break;
			case BIN_FILE:
			{
				kstrcpy(&g_BinFilePath, argv[currentOption]);
			}
			break;
			case LOG_PATH:
			{
				strncpy(g_LogPath,argv[currentOption],_countof(g_LogPath));

				if (strlen(g_LogPath) >0 && g_LogPath[strlen(g_LogPath)-1] == '/')
				{
					g_LogPath[strlen(g_LogPath)-1] = 0;
				}
			}
			break;
			default:
			{
#if PRINTLOG
				printf("\n  Error: Command line option -%c is invalid!\n", Option);
#endif
				return FALSE;
			}
			break;
			}
		}
		else
		{
			currentOption++;
		}
	}

	return TRUE;
}


void  CallbackProc(PProcInfo  pNotifyInfo)
{
	//tprintf(_T("CallbackProc......\n"));

	if (!bIgnoreBlankLines)
	{
#if PRINTLOG
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
#endif
	}


	switch ((eProcessState)pNotifyInfo->eProcState)
	{
	case kProcConnecting:
	{
		g_nDownloadPercent = 0;
#if PRINTLOG
		tprintf(_T("|%s:Add an device               |\n"), pNotifyInfo->pszUSBPortAddress);
#endif
	}
	break;
	case kProcDownloading:
	{
		if (!bIgnoreBlankLines)
		{
#if PRINTLOG
			tprintf(_T("|%s:Download percentage is:%d  |\r"), pNotifyInfo->pszUSBPortAddress, pNotifyInfo->nDownloadedPercent);
#endif
		}
		else if (pNotifyInfo->nDownloadedPercent > g_nDownloadPercent)
		{
#if PRINTLOG
			tprintf(_T("|%s:Download percentage is:%d  |\r"), pNotifyInfo->pszUSBPortAddress, pNotifyInfo->nDownloadedPercent);
#endif
			g_nDownloadPercent = pNotifyInfo->nDownloadedPercent;
		}

		if ( _tcscmp(pNotifyInfo->pszProcMsg, _T("BadBlkNum") ) == 0 )
		{
			kstring_t g_strBBPath = GetAppPath();
			kstring_t strBBFile ={0,0,NULL};
			kputs(_T("/bbcs.txt"),&g_strBBPath);
			FILE* BbcLogFile = _tfopen(g_strBBPath.s,_T("w"));
			tfprintf (BbcLogFile,_T("%lf"),le32toh(pNotifyInfo->lpBadBlk.TotalBadBlocks)/le32toh(pNotifyInfo->lpBadBlk.TotalBlocks));
			fflush(BbcLogFile);
			fclose(BbcLogFile);
			free(g_strBBPath.s);
	//		tprintf(_T("\rFlash Info: TotalBadBlocks = %d, Total Blocks = %d"),
	//		le32toh(pNotifyInfo->lpBadBlk.TotalBadBlocks),  le32toh(pNotifyInfo->lpBadBlk.TotalBlocks));

			//To do your code, you can abort the download at certain bad blocks number.
	/* 		if(((pNotifyInfo->lpBadBlk.TotalBadBlocks)*50) > pNotifyInfo->lpBadBlk.TotalBlocks)
	 		{
				tprintf(_T("|%s:Too many bad blocks          |\n"), pNotifyInfo->pszUSBPortAddress);
				exit_code = FAILED;
				pthread_cond_signal(&cond);
	 		}
	 */
		}
	}
	break;
	case kProcAborting:
	{
#if PRINTLOG
		tprintf(_T("\n|%s:Abort in download          |"), pNotifyInfo->pszUSBPortAddress);
#endif
		exit_code = FAILED;
		pthread_cond_signal(&cond);

	}
	break;
	case kProcCompleted:
	{
		if (bUpload)
		{
#if PRINTLOG
			tprintf(_T("|%s:Upload Successfully                |\n"), pNotifyInfo->pszUSBPortAddress);
#endif
		}
		else
		{
#if PRINTLOG
			tprintf(_T("|%s:Burn Successfully                |\n"), pNotifyInfo->pszUSBPortAddress);
#endif
		}

		exit_code = SUCCEED;
		pthread_cond_signal(&cond);
	}
	break;
	case kProcBurningFlash:
	{
		if (!bIgnoreBlankLines)
		{
#if PRINTLOG
			tprintf(_T("|%s:Burning Flash percentage is:%d  |\r"), pNotifyInfo->pszUSBPortAddress, pNotifyInfo->nDownloadedPercent);
#endif
		}
		else if (pNotifyInfo->nDownloadedPercent > g_nBurnPercent && pNotifyInfo->nDownloadedPercent <= 100)
		{
#if PRINTLOG
			tprintf(_T("|%s:Burning Flash percentage is:%d  |\r"), pNotifyInfo->pszUSBPortAddress, pNotifyInfo->nDownloadedPercent);
#endif
			g_nBurnPercent = pNotifyInfo->nDownloadedPercent;
		}

		if ( _tcscmp(pNotifyInfo->pszProcMsg, _T("CRCS") ) == 0 )
		{
// 			tprintf(_T("\t\nBurning, Devices: MCPID: 0x%x, ImageNum: %d\n"),
// 				le32toh(pNotifyInfo->lpImageCrc.MCPID),  le32toh(pNotifyInfo->lpImageCrc.ImageNum));
			kstring_t g_strAppPath = GetAppPath();
			kputs(_T("/crcs.txt"),&g_strAppPath);
			FILE* CrcLogFile = _tfopen(g_strAppPath.s,_T("w"));
			for(UINT32 i = 0; i < le32toh(pNotifyInfo->lpImageCrc.ImageNum); i++)
			{
// 				tprintf(_T("ImageID: 0x%x, CrcData: 0x%8X\n"),
// 				le32toh(pNotifyInfo->lpImageCrc.ImageCRC[i].ImageID),  le32toh(pNotifyInfo->lpImageCrc.ImageCRC[i].CRC32));
				if(i !=  le32toh(pNotifyInfo->lpImageCrc.ImageNum) -1)
					tfprintf (CrcLogFile,_T("0x%08x-"),le32toh(pNotifyInfo->lpImageCrc.ImageCRC[i].CRC32));
				else
					tfprintf (CrcLogFile,_T("0x%08x"),le32toh(pNotifyInfo->lpImageCrc.ImageCRC[i].CRC32));
			}
			free(g_strAppPath.s);
			fflush(CrcLogFile);
			fclose(CrcLogFile);
		}

	}
	break;
	case kProcUploadingData:
	{
#if PRINTLOG
		tprintf(_T("|%s:Uploading percentage is:%d      |\r"), pNotifyInfo->pszUSBPortAddress, pNotifyInfo->nDownloadedPercent);
#endif
	}
	break;
	case kProcDebugLog:
	{
#if PRINTLOG
            tprintf(_T("|%s:  %s   |\n"),pNotifyInfo->pszProcMsg,pNotifyInfo->pszUSBPortAddress);
#endif
	}
	break;
	case kProcEraseAllFlash:
	{
#if PRINTLOG
		tprintf(_T("|%s:Erasing all flash percentage is:%d      |\r"), pNotifyInfo->pszUSBPortAddress, pNotifyInfo->nDownloadedPercent);
#endif
	}
	break;
	default:
		break;

	}
#if PRINTLOG
	if (!bIgnoreBlankLines)
	{
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
		tprintf(_T("\n"));
	}
#endif
	fflush(stdout);
}

BOOL InitInstanceParams(PInstanceParams lpInstanceParam, struct StringList* pFbfList)
{
#define KNEWSTR(ps,src) 								\
		ps = (kstring_t*)malloc(sizeof(kstring_t));	\
		ps->s = NULL;ps->l = ps->m = 0; 				\
		kstrcpy(ps, src);

		
		//提取Dkb和DKBTimeheader
		for (int i = 0; i < pFbfList->nSize; i++)
		{
			const char * strFile = pFbfList->strL[i];
			printf("Init %s\n",strFile);
			if (strstr(strFile,_T("DKB_timheader.bin")) != NULL || strstr(strFile,_T("DKB_ntimheader.bin")) != NULL)
			{
				kstrcpy(&g_DkbTimPath,strFile);
				for (int j = i; j < pFbfList->nSize-1; j++)
					pFbfList->strL[j] = pFbfList->strL[j+1];
				i--;
				pFbfList->nSize--;
			} else if (strstr(strFile,_T("Dkb.bin")))
			{
				kstrcpy(&g_DkbFilePath,strFile);
				for (int j = i; j < pFbfList->nSize-1; j++)
					pFbfList->strL[j] = pFbfList->strL[j+1];
				i--;
				pFbfList->nSize--;
			}
		}
#if PRINTLOG
		tprintf(_T("DKB_timheader is %s  DKB is %s\n"),g_DkbTimPath.s, g_DkbFilePath.s);
#endif
		//g_lpFbfImageList->sort();
		for (int i = 0; i < pFbfList->nSize-1; i++)
			for (int j = i+1; j < pFbfList->nSize; j++)
				if (strcmp(pFbfList->strL[i], pFbfList->strL[j]) > 0)
				{
					const char *strTmp = pFbfList->strL[i];
					pFbfList->strL[i] = pFbfList->strL[j];
					pFbfList->strL[j] = strTmp;
				}
		int ite = 0;
		if (strstr(pFbfList->strL[ite],_T("0x")) != NULL )
		{
			//Multi DDR case
			while(ite!=pFbfList->nSize)
			{
				const char*	tpos = strstr(pFbfList->strL[ite],_T("0x"));
				if (tpos!= NULL)
				{
					DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC *pDDRFlashImagInfo = (pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC)malloc(sizeof(DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC));
					New_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDRFlashImagInfo);
					char buf[32];
					int ite2 = ite;
					memset(buf, 0, sizeof(buf));
					strncpy(buf,tpos,6);
					kstrcpy(&pDDRFlashImagInfo->sVendorDDRId,buf);
					//pDDRFlashImagInfo->sVendorDDRId = ite->substr(tpos,6);
					strncpy(buf,tpos+6,6);
					
					kstrcpy(&pDDRFlashImagInfo->sFlashInfo,buf);
					//pDDRFlashImagInfo->sFlashInfo = ite->substr(tpos+6,6);
					//tstring sDdrFlashInfo = ite->substr(tpos,12);
					ite2++;
					printf("VendorDDRId:%s FlashInfo:%s\n",pDDRFlashImagInfo->sVendorDDRId.s,pDDRFlashImagInfo->sFlashInfo.s);
					if (strstr(pFbfList->strL[ite],_T("header")) != NULL)
					{
						kstring_t *kps;
						KNEWSTR(kps,pFbfList->strL[ite2])
						*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
						KNEWSTR(kps,pFbfList->strL[ite])
						*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
						//pDDRFlashImagInfo->pImagelist->push_front(new tstring(*ite2));	
						//pDDRFlashImagInfo->pImagelist->push_front(new tstring(*ite));
#if PRINTLOG
						printf("FBF head:%s FBF:%s\n",pFbfList->strL[ite],pFbfList->strL[ite2]);
#endif
					} else
					{
						kstring_t *kps;
						KNEWSTR(kps,pFbfList->strL[ite])
						*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
						KNEWSTR(kps,pFbfList->strL[ite2])
						*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
#if PRINTLOG
						printf("FBF head:%s FBF:%s\n",pFbfList->strL[ite2],pFbfList->strL[ite]);
#endif
					}
					//g_lpFbfImageList->erase(ite++);
					//g_lpFbfImageList->erase(ite2++);
					for (int k = ite; k < pFbfList->nSize-3; k+=2)
					{
						pFbfList->strL[k] = pFbfList->strL[k+2];
						pFbfList->strL[k+1] = pFbfList->strL[k+3];
					}
					pFbfList->nSize -= 2;
					pDDRFlashImagInfo->TotalFlashTypeNum = 1;
					pDDRFlashImagInfo->TotalVendorDDRTypeNum = 1;
					*kl_pushp(dfdil,*lpInstanceParam->pDownloadImagesList)=pDDRFlashImagInfo;
				}
				//pDDRFlashImagInfo->pImagelist->push_back(new tstring(*ite));
				ite = 0;
			}		
		} else	
		{
			DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC *pDDRFlashImagInfo = (pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC)malloc(sizeof(DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC));
			New_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDRFlashImagInfo);
			kstrcpy(&pDDRFlashImagInfo->sVendorDDRId,"Reserve");
			kstrcpy(&pDDRFlashImagInfo->sFlashInfo,"Reserve");
			int ite2 = ite;
			ite2++;
			kstring_t *kps;
			if (strstr(pFbfList->strL[ite],_T("header")) != NULL )
			{
				KNEWSTR(kps,pFbfList->strL[ite2])
				*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
				KNEWSTR(kps,pFbfList->strL[ite])
				*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
#if PRINTLOG				
				printf("FBF head:%s FBF:%s\n",pFbfList->strL[ite],pFbfList->strL[ite2]);
#endif
			} else{
				KNEWSTR(kps,pFbfList->strL[ite])
				*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
				KNEWSTR(kps,pFbfList->strL[ite2])
				*kl_pushf(pstrl, *pDDRFlashImagInfo->pImagelist) = kps;
#if PRINTLOG				
				printf("FBF head:%s FBF:%s\n",pFbfList->strL[ite2],pFbfList->strL[ite]);
#endif
			}
			for (int k = ite; k < pFbfList->nSize-4; k+=2)
			{
				pFbfList->strL[k] = pFbfList->strL[k+2];
				pFbfList->strL[k+1] = pFbfList->strL[k+3];
			}
			pFbfList->nSize -= 2;

			pDDRFlashImagInfo->TotalFlashTypeNum = 1;
			pDDRFlashImagInfo->TotalVendorDDRTypeNum = 1;
			*kl_pushp(dfdil,*lpInstanceParam->pDownloadImagesList) = pDDRFlashImagInfo;
		}
	
	
	
		TCHAR* pszTimFile = (TCHAR*)malloc(sizeof(TCHAR)*(g_DkbTimPath.l + 1));
		memset(pszTimFile, 0, (g_DkbTimPath.l + 1) * sizeof(TCHAR));
		memcpy(pszTimFile, g_DkbTimPath.s, g_DkbTimPath.l * sizeof(TCHAR));
		lpInstanceParam->pszDKBTim = pszTimFile;
	
		TCHAR* pszDkbFile = (TCHAR*)malloc(sizeof(TCHAR)*(g_DkbFilePath.l + 1));
		memset(pszDkbFile, 0, (g_DkbFilePath.l + 1) * sizeof(TCHAR));
		memcpy(pszDkbFile, g_DkbFilePath.s, g_DkbFilePath.l * sizeof(TCHAR));
		lpInstanceParam->pszDKBbin = pszDkbFile;
		//lpInstanceParam->pDownloadImagesList->front()->pImagelist->back();
		kstring_t strFbfFile = *(*kl_back(pstrl, *kl_val(kl_begin(*lpInstanceParam->pDownloadImagesList))->pImagelist));
		BinFileWtp_OpenBinFile(&gBinFileWtp,_T("rb"));
	//	FILE* fpFile = _tfopen(strFbfFile.c_str(),_T("rb"));
	//	if (NULL == fpFile)
	//	{
	//		tprintf(_T("Open file failed:%s"),strFbfFile.c_str());
	//		return FALSE;
	//	}
	
		MasterBlockHeader masterBlkHeader;
		BinFileWtp_FseekBin(&gBinFileWtp,strFbfFile.s,4L,SEEK_SET);
		BinFileWtp_ReadBinFile(&gBinFileWtp,&masterBlkHeader,sizeof(MasterBlockHeader),1,strFbfFile.s);
		EndianConvertMasterBlockHeader(&masterBlkHeader);
		printf("MasterBlkHeader.SizeOfBlock=%x\n",masterBlkHeader.Size_of_Block);
	//	fseek(fpFile,4,SEEK_SET);
	//	fread(&masterBlkHeader,sizeof(MasterBlockHeader),1,fpFile);
		
		DeviceHeader_V11 deviceHeaderBuf;
		BinFileWtp_FseekBin(&gBinFileWtp,strFbfFile.s,masterBlkHeader.deviceHeaderOffset[0] + 4,SEEK_SET);
		BinFileWtp_ReadBinFile(&gBinFileWtp,&deviceHeaderBuf,sizeof(DeviceHeader_V11),1,strFbfFile.s);
		EndianConvertDeviceHeader_V11(&deviceHeaderBuf);
		printf("deviceHeaderBuf.DeviceFlags=%x\n",deviceHeaderBuf.DeviceFlags);
	//	fseek(fpFile,masterBlkHeader.deviceHeaderOffset[0] + 4,SEEK_SET);
	//	fread(&deviceHeaderBuf,sizeof(DeviceHeader_V11),1,fpFile);
	
		lpInstanceParam->PlaformType = deviceHeaderBuf.ChipID;
		lpInstanceParam->Commands |= (deviceHeaderBuf.FlashOpt.EraseAll?1:0);
		lpInstanceParam->Commands |= (deviceHeaderBuf.FlashOpt.ResetBBT? (1<<2):0);
		if (deviceHeaderBuf.FlashOpt.NandID)
		{
			lpInstanceParam->FlashType = 0;
		}
		/*Note: the BBCS and CRCS on/off are controlled by the blf via which fbf file was created.
		 Here for fbfdownloader pc side, just assume both are ON in order to avoid extract the information from TIMH.
		 The CallbackProc only try to read the infos when BBCS or CRCS success although the on/off at PC are always set to ON
		 lpInstanceParam->GetBadBlk = 1;
		 lpInstanceParam->ImageCrcEn = 1;
		  */
		lpInstanceParam->GetBadBlk = deviceHeaderBuf.BBCS_EN;
		lpInstanceParam->ImageCrcEn = deviceHeaderBuf.CRCS_EN;
	
		BinFileWtp_CloseBinFIle(&gBinFileWtp);
	//	fclose(fpFile);
		return TRUE;
#undef KNEWSTR
}


#ifdef STATICLIB_FBFDOWNLOAD
int fbfdownload(char * strBinFilePath, int nTimeout)
{
	struct StringList g_lpFbfImageList;
	int i = 0;
	BOOL bIsInProcess = FALSE;
	memset(&g_lpFbfImageList,0,sizeof(struct StringList));
	//SetDebugMode(bDebugTrace);
	pthread_mutex_init(&mutex, NULL);
	pthread_cond_init(&cond, NULL);
	
#if PRINTLOG
	printf("\n\nfbfdownloader version: %s\n", pszSWDReleaseVersion);
	printf("fbfdownloader date: %s\n\n", pszSWDReleaseDate);
#endif	
	//remove wtptp.ko
	//system("rmmod wtptp.ko");
	if (nTimeout <= 0)
	{
		btimeoutset = FALSE;
	}else
	{
		btimeoutset = TRUE;
		timeout = nTimeout;
	}
	kstrcpy(&g_BinFilePath, strBinFilePath);
	if (!IsFileExist(strBinFilePath))
	{
		tprintf("BinFilePath Error\n");
		return 1;
	}

	PInstanceParams lpInstanceParam = (PInstanceParams)malloc(sizeof(InstanceParams));
	if (NULL == lpInstanceParam)
	{
#if PRINTLOG
		tprintf("malloc memory failed.\n");
#endif
		return 1;
	}
	NewInstanceParams(lpInstanceParam);
	if (g_BinFilePath.l > 0)
	{
		BinFileWtp_InitParameter2(&gBinFileWtp,g_BinFilePath.s, &g_lpFbfImageList);
	}

	strDeviceDetectFile = GetAppPath();
	kputs("/swdl_linux_wtptp_device_detect.log", &strDeviceDetectFile);


	if (bDownload)
	{
		if (InitInstanceParams(lpInstanceParam,&g_lpFbfImageList))
		{
			lpInstanceParam->CallbackProc = CallbackProc;
			if (bSingle)
			{
				lpInstanceParam->DownloadMode = 1;
			}
			if (!InitializeBL(lpInstanceParam))
			{
#if PRINTLOG				
				printf("InitializeBL failed , please check failed root cause....\n");
#endif
				DelInstanceParams(lpInstanceParam);
				free(lpInstanceParam);
				return 1;
			}
			bIsInProcess = TRUE;
		}
		else
		{
			DelInstanceParams(lpInstanceParam);
			free(lpInstanceParam);
			return 1;
		}


	}

	if (bIsInProcess)
	{
		if (bSingle)
		{
			if (btimeoutset)
			{
				struct timespec to;
				pthread_mutex_lock(&mutex);
				to.tv_sec = time(NULL) + timeout;
				to.tv_nsec = 0;
				if (ETIMEDOUT == pthread_cond_timedwait(&cond, &mutex, &to))
				{
					exit_code = FAILED;
					printf("swdl_linux timeout exit\n");
					printf("current timeout time is %d seconds, please increase timeout time to retry.\n", timeout);
				}

				TerminateBL();
			}
			else
			{
				pthread_mutex_lock(&mutex);
				pthread_cond_wait(&cond, &mutex);
				TerminateBL();
			}
			printf("FBFDownloader EXIT.....\n");
		}
		else
		{
			if (btimeoutset)
			{
				struct timespec to;
				pthread_mutex_lock(&mutex);
				to.tv_sec = time(NULL) + timeout;
				to.tv_nsec = 0;
				if (ETIMEDOUT == pthread_cond_timedwait(&cond, &mutex, &to))
				{
					exit_code = FAILED;
					printf("swdl_linux timeout exit\n");
					printf("current timeout time is %d seconds, please increase timeout time to retry.\n", timeout);
				}
				TerminateBL();
			}
			else
			{

				while (1)
				{
					sleep(2);
					if (tolower(getchar()) == (int)'q')
					{
						TerminateBL();
						DelFile(strDeviceDetectFile.s);
						DelInstanceParams(lpInstanceParam);
						free(lpInstanceParam);
						return 1;
					}
				}
			}
		}
	}
	DelFile(strDeviceDetectFile.s);
	DelInstanceParams(lpInstanceParam);
	free(lpInstanceParam);
	return exit_code;
}
#else
int main(int argc, char *argv[])
{
	struct StringList g_lpFbfImageList;
	memset(&g_lpFbfImageList,0,sizeof(struct StringList));
	if (!ParseCommandLine(argc, argv))
	{
#if PRINTLOG
		printf("Command line error.\n");
#endif

		return 1;
	}
	if (already_running() == 1)
	{	
		printf("\n\nthere is already an fbfdownloader is running, you can't run it again.\n\n");
		return 1;
	}
	int i = 0;
	BOOL bIsInProcess = FALSE;
	//SetDebugMode(bDebugTrace);
	pthread_mutex_init(&mutex, NULL);
	pthread_cond_init(&cond, NULL);

#if PRINTLOG
	printf("\n\nfbfdownloader version: %s\n", pszSWDReleaseVersion);
	printf("fbfdownloader date: %s\n\n", pszSWDReleaseDate);
#endif	
	if (argc < MIN_ARGS)
	{
#if PRINTLOG		
		tprintf(_T("Invalid parameters\n"));
		tprintf(_T("Function:  Do Remote or automatically Software Download to board\n"));
		tprintf(_T("CommandLine:  fbfdownloader -b BinFile [-p  path of Log File]\n"));
		tprintf(_T("Usage:  FBFDownloader -b BinFile.bin \n\n"));
#endif		
		fflush(stdout);

		return 1;
	}

	//remove wtptp.ko
	//system("rmmod wtptp.ko");


	if (!IsFileExist(g_BinFilePath.s))
	{
		tprintf("BinFilePath Error\n");
		return 1;
	}

	

	PInstanceParams lpInstanceParam = (PInstanceParams)malloc(sizeof(InstanceParams));
	if (NULL == lpInstanceParam)
	{
#if PRINTLOG
		tprintf("malloc memory failed.\n");
#endif
		return 1;
	}
	NewInstanceParams(lpInstanceParam);
	printf("BinFilePath is :%s\n",g_BinFilePath.s);
	if (g_BinFilePath.l > 0)
	{
		if (FALSE == BinFileWtp_InitParameter2(&gBinFileWtp,g_BinFilePath.s, &g_lpFbfImageList))
		{
			printf("BinFileWtp_InitParameter2 Faile!\n");
			return FAILED;
		} else
		{
			printf("BinFileWtp_InitParameter2 Success!\n");
		}
	}
	strDeviceDetectFile = GetAppPath();
	//kputs("/swdl_linux_wtptp_device_detect.log", &strDeviceDetectFile);
	printf("AppPath is :%s\n",strDeviceDetectFile.s);
	if (bDownload)
	{
		if (InitInstanceParams(lpInstanceParam, &g_lpFbfImageList))
		{
			lpInstanceParam->CallbackProc = CallbackProc;
			if (bSingle)
			{
				lpInstanceParam->DownloadMode = 1;
			}
			if (!InitializeBL(lpInstanceParam))
			{
#if PRINTLOG				
				printf("InitializeBL failed , please check failed root cause....\n");
#endif
				DelInstanceParams(lpInstanceParam);
				free(lpInstanceParam);
				return 1;
			}
			bIsInProcess = TRUE;
		}
		else
		{
			DelInstanceParams(lpInstanceParam);
			free(lpInstanceParam);
			return 1;
		}


	}

	if (bIsInProcess)
	{
		if (bSingle)
		{
			if (btimeoutset)
			{
				struct timespec to;
				pthread_mutex_lock(&mutex);
				to.tv_sec = time(NULL) + timeout;
				to.tv_nsec = 0;
				if (ETIMEDOUT == pthread_cond_timedwait(&cond, &mutex, &to))
				{
					exit_code = FAILED;
					printf("swdl_linux timeout exit\n");
					printf("current timeout time is %d seconds, please increase timeout time to retry.\n", timeout);
				}

				TerminateBL();
			}
			else
			{
				pthread_mutex_lock(&mutex);
				pthread_cond_wait(&cond, &mutex);
				TerminateBL();
			}
			printf("FBFDownloader EXIT.....\n");
		}
		else
		{
			if (btimeoutset)
			{
				struct timespec to;
				pthread_mutex_lock(&mutex);
				to.tv_sec = time(NULL) + timeout;
				to.tv_nsec = 0;
				if (ETIMEDOUT == pthread_cond_timedwait(&cond, &mutex, &to))
				{
					exit_code = FAILED;
					printf("swdl_linux timeout exit\n");
					printf("current timeout time is %d seconds, please increase timeout time to retry.\n", timeout);
				}
				TerminateBL();
			}
			else
			{

				while (1)
				{
					sleep(2);
					if (tolower(getchar()) == (int)'q')
					{
						TerminateBL();
						DelFile(strDeviceDetectFile.s);
						DelInstanceParams(lpInstanceParam);
						free(lpInstanceParam);
						return 1;
					}
				}
			}
		}
	}
	DelFile(strDeviceDetectFile.s);
	DelInstanceParams(lpInstanceParam);
	free(lpInstanceParam);
	return exit_code;
}
#endif
