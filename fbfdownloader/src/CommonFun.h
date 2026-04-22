#pragma once

#include "Typedef.h"
#include <errno.h>
#if !defined(LINUX)
#include "StdAfx.h"
#include <afxmt.h>
#include <io.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "Shlwapi.h"
#else
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
#include "downloader.h"
#define _countof(array) (sizeof(array) / sizeof(array[0]))

kstring_t GetAppPath();
void DelFile(const TCHAR* pszFile);

unsigned int Str2Uint32 (const TCHAR* pValue);
UINT64 TranslateEx (kstring_t sValue);
BOOL IsFileExist(const TCHAR *pFileName);

//inline function
inline int CloseFilePtr(FILE** fpFile)
{
	int ret = 0;
	if (NULL != *fpFile)
	{
		ret = fclose(*fpFile);
		*fpFile = NULL;
	}	
	return ret;
}

void EndianConvertMasterBlockHeader(MasterBlockHeader *mbHeader);

void EndianConvertDeviceHeader_V11(DeviceHeader_V11 *pDeviceHeader);