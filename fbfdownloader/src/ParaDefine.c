#include "ParaDefine.h"
#include "BinFileWtp.h"
#include "WtptpDownloader.h"

extern kstring_t 	strDeviceDetectFile, g_DkbFilePath,g_DkbTimPath,g_BinFilePath;
void Copy_NotifyStatus(PProcInfo me,struct _NotifyStatus* rhs)
{
	me->nDevice = rhs->nDevice;
	me->nDevType = rhs->nDevType;
	me->nDownloadedPercent = rhs->nDownloadedPercent;
	me->lpBadBlk = rhs->lpBadBlk;
	me->lpImageCrc = rhs->lpImageCrc;
	me->eProcState = rhs->eProcState;
	me->eProcStatus = rhs->eProcStatus;
	me->nErrorCode = rhs->nErrorCode;
	memcpy(&me->pszProcMsg,&rhs->pszProcMsg,sizeof(me->pszProcMsg));
	memcpy(&me->pszUSBPortAddress,&rhs->pszUSBPortAddress,sizeof(me->pszUSBPortAddress));
}

void New_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC me)
{
	  me->pImagelist = (t_stringList*)malloc(sizeof(t_stringList));
	  *me->pImagelist = kl_init(pstrl);
	  ks_release(&me->sVendorDDRId);
	  ks_release(&me->sFlashInfo);
	  me->TotalVendorDDRTypeNum = 0;
	  me->TotalFlashTypeNum = 1;
}

void Del_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC me)
{

	if( me->pImagelist!=NULL)
	{
		t_stringListIter ImagesIter = kl_begin(*me->pImagelist);
		while(ImagesIter!= kl_end(*me->pImagelist) )
		{
			if (kl_val(ImagesIter)->s)
				free(kl_val(ImagesIter)->s);
			free(kl_val(ImagesIter));
			ImagesIter = kl_next(ImagesIter);
		}
		kl_destroy(pstrl, *me->pImagelist);
		free(me->pImagelist);
		me->pImagelist = NULL;
	}
	if (me->sFlashInfo.s)
		free(me->sFlashInfo.s);
	if (me->sVendorDDRId.s)
		free(me->sVendorDDRId.s);
	ks_release(&me->sFlashInfo);
	ks_release(&me->sVendorDDRId);
}

void Copy_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC me,struct _DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC* DDRFlashDownloadImageInfo)
{  
	#define KNEWSTR(ps,src) 								\
		ps = (kstring_t*)malloc(sizeof(kstring_t));	\
		ps->s = NULL;ps->l = ps->m = 0; 				\
		kstrcpy(ps, src);
	for(t_stringListIter ite = kl_begin(*me->pImagelist); ite != kl_end(*me->pImagelist); ite = kl_next(ite))
	{
		if (kl_val(ite)->s)
			free(kl_val(ite)->s);
		free( kl_val(ite));
	}
	kl_clear(pstrl,*me->pImagelist);
	
	me->sVendorDDRId = DDRFlashDownloadImageInfo->sVendorDDRId; 
	me->sFlashInfo = DDRFlashDownloadImageInfo->sFlashInfo;
	me->TotalVendorDDRTypeNum = DDRFlashDownloadImageInfo->TotalVendorDDRTypeNum;
	me->TotalFlashTypeNum = DDRFlashDownloadImageInfo->TotalFlashTypeNum;
	t_stringListIter ImagesIter = 	kl_begin(*DDRFlashDownloadImageInfo->pImagelist);
	while(ImagesIter!= kl_end(*DDRFlashDownloadImageInfo->pImagelist) )
	{
		kstring_t *kps;
		KNEWSTR(kps,kl_val(ImagesIter)->s);
		*kl_pushp(pstrl,*me->pImagelist) = kps;
		ImagesIter = kl_next(ImagesIter);
	}
	#undef KNEWSTR
}


void Copy_WTPTPREAMBLECOMMAND(pWTPTPREAMBLECOMMAND me,struct _WTPTPREAMBLECOMMAND* WTPCMD)
{
	me->CMD = WTPCMD->CMD;
	me->SEQ = WTPCMD->SEQ;
	me->CID = WTPCMD->CID;
	me->Flags = WTPCMD->Flags;
	me->LEN = WTPCMD->LEN;
	memcpy(WTPCMD->Data,me->Data,CMDDATALENGTH);
}


void DelInstanceParams(PInstanceParams me)
{
	if (NULL != me->pszDKBbin) {free((void*)me->pszDKBbin);me->pszDKBbin = NULL;}
	if (NULL != me->pszDKBTim) {free((void*)me->pszDKBTim);me->pszDKBTim = NULL;}
	if (NULL != me->pszOBMFile) {free((void*)me->pszOBMFile);me->pszOBMFile = NULL;}
	if (NULL != me->pszWTMFile) {free((void*)me->pszWTMFile);me->pszWTMFile = NULL;}
	if (NULL != me->pszJTAGKeyFile) {free((void*)me->pszJTAGKeyFile);me->pszJTAGKeyFile = NULL;}
	if (NULL != me->pszTZIIFile) {free((void*)me->pszTZIIFile);me->pszTZIIFile = NULL;}
	if (NULL != me->pWtptpPreaCmd){free((void*)me->pWtptpPreaCmd); me->pWtptpPreaCmd = NULL;}
	if (NULL != me->pUploadSpecs)
	{
		for (t_UpLoadDataSpecIter iter = kl_begin(*me->pUploadSpecs);iter != kl_end(*me->pUploadSpecs);iter = kl_next(iter))
		{
			free( kl_val(iter));
		}
		free( me->pUploadSpecs);
		me->pUploadSpecs = NULL;
	}

	if (NULL != me->pDownloadImagesList)
	{
		for (t_DdrFlashDownloadImgInfoIter iter = kl_begin(*me->pDownloadImagesList);iter != kl_end(*me->pDownloadImagesList);iter = kl_next(iter))
		{
			Del_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(kl_val(iter));
			free( kl_val(iter));
		}
	}
	kl_destroy(dfdil, *me->pDownloadImagesList);
	free( me->pDownloadImagesList);
	DelCWtptpDownLoad(&gWtptpDownload);
	BinFileWtp_DelMe(&gBinFileWtp);

	//global var
	free(strDeviceDetectFile.s);
	free(g_DkbFilePath.s);
	free(g_DkbTimPath.s);
	free(g_BinFilePath.s);
}
void NewInstanceParams(PInstanceParams me) 
{
	me->pszDKBbin=NULL;
	me->pszDKBTim= NULL;
	me->CallbackProc=NULL; 
	me->pszOBMFile=NULL;
	me->pszWTMFile=NULL;
	me->pszJTAGKeyFile=NULL;
	me->pszTZIIFile=NULL;
	me->pUploadSpecs=NULL;
	me->pWtptpPreaCmd=NULL;
	me->Commands=0;
	me->FlashType=5;
	me->PlaformType=4;
	me->FlashPageSize=0;
	me->DownloadMode=0;
	me->ProductionMode=0;
	me->GetBadBlk=0;
	me->ImageCrcEn=0;
	me->ReservedVal[0] = BADBLOCKRATE_BASE*100;//坏块率默认值
	me->pDownloadImagesList = (t_DdrFlashDownloadImgInfoList*)malloc(sizeof(t_DdrFlashDownloadImgInfoList));
	(*me->pDownloadImagesList) = kl_init(dfdil);
	memset(&gBinFileWtp, 0, sizeof(struct CBinFileWtp));
	BinFileWtp_ResetPara(&gBinFileWtp);
	memset(&gWtptpDownload, 0, sizeof(struct CWtptpDownLoad));
	NewCWtptpDownLoad(&gWtptpDownload);
}

