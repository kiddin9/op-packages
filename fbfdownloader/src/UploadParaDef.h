#pragma once
#include "Macrodef.h"

#pragma pack(push,1)
typedef struct _UPLOAD_DATA_PARAMS
{
	BYTE Type;
	BYTE SubType;
	BYTE Partition;
	BYTE Times;// Total Number of upload Areas
	unsigned int Offset;
	unsigned int DataSize;
	BYTE IncludeSpareAreas; // indicate this upload include spare areas or not
	BYTE ResetUE;
	BYTE ResetTimeDelay;
	BYTE Reserved2; // 用来存放DataSize的高32位，支持一次性upload大于4GB的内容
	
} UPLOAD_DATA_PARAMS; 
static void NEW_UPLOAD_DATA_PARAMS(UPLOAD_DATA_PARAMS *me){me->Reserved2 = 0;}
static void COPY_UPLOAD_DATA_PARAMS(UPLOAD_DATA_PARAMS *me,UPLOAD_DATA_PARAMS* UpLoadDataPara)
	{
		me->Type = UpLoadDataPara->Type;
		me->SubType = UpLoadDataPara->SubType;
		me->Partition = UpLoadDataPara->Partition;
		me->Times = UpLoadDataPara->Times;
		me->Offset = UpLoadDataPara->Offset;
		me->DataSize = UpLoadDataPara->DataSize;
		me->IncludeSpareAreas = UpLoadDataPara->IncludeSpareAreas; // indicate this upload include spare areas or not
		me->ResetUE = UpLoadDataPara->ResetUE;
		me->ResetTimeDelay = UpLoadDataPara->ResetTimeDelay;
		me->Reserved2 = UpLoadDataPara->Reserved2;
	}
#pragma pack(pop)


#pragma pack(push,1)
typedef struct _UPLOAD_DATA_SPEC
{
	UPLOAD_DATA_PARAMS m_Params;
	kstring_t    strOutputFileName;
	kstring_t   strComparisonFileName;
	BOOL	   bCreateNewFile;
} UPLOAD_DATA_SPEC,*pUPLOAD_DATA_SPEC; 
static void NewUPLOAD_DATA_SPEC(pUPLOAD_DATA_SPEC me,struct _UPLOAD_DATA_SPEC* UpLoadDataSpec)
	{  
		me->m_Params = UpLoadDataSpec->m_Params;
		me->strOutputFileName = UpLoadDataSpec->strOutputFileName;
		me->strComparisonFileName = UpLoadDataSpec->strComparisonFileName;
		me->bCreateNewFile = UpLoadDataSpec->bCreateNewFile;
	}
#pragma pack(pop)



#define __uds_free(x)

KLIST_INIT(pudsl,UPLOAD_DATA_SPEC*,__uds_free)



typedef klist_t(pudsl)* t_UpLoadDataSpecList;
typedef kliter_t(pudsl)* t_UpLoadDataSpecIter;