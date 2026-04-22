#include "kstring.h"
#include "CommonFun.h"
#include <stdarg.h>
#ifdef _WINDOWS
#include <direct.h>
#endif
#define MAX_FILE_LENGTH  1024
#pragma warning ( disable : 4996) 
#ifdef MACDOWNLOAD
#include <mach-o/dyld.h>
#endif

kstring_t GetAppPath()
{   
	kstring_t strRet = { 0, 0, NULL };
	TCHAR exeFullPath[MAX_FILE_LENGTH] = {0};
    TCHAR exeAbsFullPath[MAX_FILE_LENGTH] = {0};
#ifdef LINUX
#ifdef MACDOWNLOAD
    UINT32 size = MAX_FILE_LENGTH;
    _NSGetExecutablePath(exeFullPath, &size);
    //exeFullPath[size] = '\0';
    realpath(exeFullPath,exeAbsFullPath);
    TCHAR *p = _tcsrchr(exeAbsFullPath,'/');
    if(p) *p = 0;
#if PRINTLOG
    tprintf(_T("GetAppPath: %s.....\n\n"),exeAbsFullPath);
#endif
	kputs(exeAbsFullPath,&strRet);
	return strRet;
#else
     
    readlink ("/proc/self/exe", exeFullPath, MAX_FILE_LENGTH);
	TCHAR *p = _tcsrchr(exeFullPath,'/');
	if(p) *p = 0;
	kputs(exeFullPath,&strRet);
	return strRet;
#endif  
	
#else
	kstring_t strAppPath = {0,0,NULL};
	TCHAR szFullExeName[MAX_FILE_LENGTH];
	DWORD nResult = ::GetModuleFileName(NULL, szFullExeName, MAX_FILE_LENGTH);
	kstring_t strFullFileName= {0,0,NULL};
	kputs(szFullExeName,&strFullFileName);
	char* cPos = strrchr(szFullExeName,'\\');
	*cPos = 0;
	kputs(szFullExeName,&strAppPath);
	return strAppPath;
#endif
	
}




void DelFile(const TCHAR* pszFile)
{
	if (ACCESS_FILE_EXIST != taccess(pszFile,ACCESS_FILE_EXIST))
	{
		return;
	}	
#ifdef LINUX
	chmod(pszFile,0777);
	TCHAR szBuffer[MAX_FILE_LENGTH];
	memset(szBuffer,0,sizeof(TCHAR)*MAX_FILE_LENGTH);
	tsnprintf(szBuffer,sizeof(szBuffer),_T("rm -f %s"),pszFile);
	system(szBuffer);
#else
	SetFileAttributes(pszFile,FILE_ATTRIBUTE_NORMAL);
	DeleteFile(pszFile);
#endif
}



BOOL IsFileExist(const TCHAR *pFileName)
{
	if(taccess(pFileName,0)!=0)   
	{   
		return FALSE;
	}   
	return TRUE;
}



unsigned int Str2Uint32 (const TCHAR* pValue)
{
	unsigned int iRetVal = 0;
	if (pValue[0]== _T('0') && (pValue[1]== _T('x') || pValue[1]== _T('X')))
		tsscanf( pValue, _T("%x"), &iRetVal );
	else
		tsscanf( pValue, _T("%i"), &iRetVal );
	return iRetVal;
}


UINT64 TranslateEx (kstring_t sValue)
{
	int *fields,n;
	if(strstr(sValue.s,_T("0xffffffffff"))!=NULL||
		strstr(sValue.s,_T("0xFFFFFFFFFF"))!=NULL)
	{
       UINT64 iRetVal = 0xFFFFFFFFFFll;
	   return iRetVal;
	}
	if(strstr(sValue.s,_T("0xffffffff"))!=NULL||
		strstr(sValue.s,_T("0xFFFFFFFF"))!=NULL)
	{
	   return 0xFFFFFFFF;
	}


	UINT64 iRetVal = 0;
	// remove leading whitespace
	// remove any trailing whitespace
	fields = ksplit(&sValue, 0, &n);
	kstrcpy(&sValue,sValue.s+fields[0]);
	free(fields);

	if(strstr(sValue.s,_T("0x"))!=NULL || strstr(sValue.s,_T("0X"))!=NULL)
	{
		tsscanf( sValue.s, _T("%llx"), &iRetVal );
	}
	else
	{
		tsscanf( sValue.s, _T("%lli"), &iRetVal );
	}

	return iRetVal;
}


void EndianConvertMasterBlockHeader(MasterBlockHeader *mbHeader)
{
	int i;
	for (i = 0; i < NUM_OF_SUPPORTED_FLASH_DEVS; i++){
		mbHeader->Flash_Device_Spare_Area_Size[i] = le16toh(mbHeader->Flash_Device_Spare_Area_Size[i]);
	}
	mbHeader->Format_Version = le16toh(mbHeader->Format_Version);
	mbHeader->Size_of_Block = le16toh(mbHeader->Size_of_Block);
	mbHeader->Bytes_To_Program = le32toh(mbHeader->Bytes_To_Program);
	mbHeader->Bytes_To_Verify = le32toh(mbHeader->Bytes_To_Verify);
	mbHeader->Number_of_Bytes_To_Erase = le32toh(mbHeader->Number_of_Bytes_To_Erase);
	mbHeader->Main_Commands = le32toh(mbHeader->Main_Commands);
	mbHeader->nOfDevices = le32toh(mbHeader->nOfDevices);
	mbHeader->DLerVersion = le32toh(mbHeader->DLerVersion);
	for (i = 0; i < MAX_NUMBER_OF_FLASH_DEVICES_IN_MASTER_HEADER; i++){
		mbHeader->deviceHeaderOffset[i] = le32toh(mbHeader->deviceHeaderOffset[i]);
	}
}

void EndianConvertDeviceHeader_V11(DeviceHeader_V11 *pDeviceHeader)
{
	int i;
	pDeviceHeader->DeviceFlags = le32toh(pDeviceHeader->DeviceFlags);
	for (i = 0; i < 16; i++){
		pDeviceHeader->DeviceParameters[i] = le32toh(pDeviceHeader->DeviceParameters[i]);
	}
	pDeviceHeader->FlashOpt.EraseAll = le32toh(pDeviceHeader->FlashOpt.EraseAll);
	pDeviceHeader->FlashOpt.ResetBBT = le32toh(pDeviceHeader->FlashOpt.ResetBBT);
	pDeviceHeader->FlashOpt.NandID = le32toh(pDeviceHeader->FlashOpt.NandID);
	for (i = 0; i < MAX_RESEVERD_LEN-1; i++){
		pDeviceHeader->FlashOpt.Reserved[i] = le32toh(pDeviceHeader->FlashOpt.Reserved[i]);
	}
	pDeviceHeader->FlashOpt.Skip_Blocks_Struct.Total_Number_Of_SkipBlocks = le32toh(pDeviceHeader->FlashOpt.Skip_Blocks_Struct.Total_Number_Of_SkipBlocks);
	for (i = 0; i < MAX_NUM_SKIP_BLOCKS; i++){
		pDeviceHeader->FlashOpt.Skip_Blocks_Struct.Skip_Blocks[i] = le32toh(pDeviceHeader->FlashOpt.Skip_Blocks_Struct.Skip_Blocks[i]);
	}
	pDeviceHeader->ProductionMode = le32toh(pDeviceHeader->ProductionMode);
	for (i = 0; i < MAX_RESEVERD_LEN-2; i++){
		pDeviceHeader->Reserved[i] = le32toh(pDeviceHeader->Reserved[i]);
	}
	pDeviceHeader->nOfImages = le32toh(pDeviceHeader->nOfImages);
	for (i = 0; i < MAX_NUMBER_OF_IMAGE_STRUCTS_IN_DEVICE_HEADER; i++){
		pDeviceHeader->imageStruct[i].Image_ID = le32toh(pDeviceHeader->imageStruct[i].Image_ID);
		pDeviceHeader->imageStruct[i].Image_In_TIM = le32toh(pDeviceHeader->imageStruct[i].Image_In_TIM);
		pDeviceHeader->imageStruct[i].Flash_partition = le32toh(pDeviceHeader->imageStruct[i].Flash_partition);
		pDeviceHeader->imageStruct[i].Flash_erase_size = le32toh(pDeviceHeader->imageStruct[i].Flash_erase_size);
		pDeviceHeader->imageStruct[i].commands = le32toh(pDeviceHeader->imageStruct[i].commands);
		pDeviceHeader->imageStruct[i].First_Sector = le32toh(pDeviceHeader->imageStruct[i].First_Sector);
		pDeviceHeader->imageStruct[i].length = le32toh(pDeviceHeader->imageStruct[i].length);
		pDeviceHeader->imageStruct[i].Flash_Start_Address = le32toh(pDeviceHeader->imageStruct[i].Flash_Start_Address);
		for (int j = 0; j < MAX_RESEVERD_LEN; j++){
			pDeviceHeader->imageStruct[i].Reserved[j] = le32toh(pDeviceHeader->imageStruct[i].Reserved[j]);
		}
		pDeviceHeader->imageStruct[i].ChecksumFormatVersion2 = le32toh(pDeviceHeader->imageStruct[i].ChecksumFormatVersion2);
	}
}
