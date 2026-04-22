#include "CommonFun.h"
#include "BinFileWtp.h"
#include <endian.h>
#define BINFILE _T("BinFile.bin")



BOOL BinFileWtp_OpenBinFile(struct CBinFileWtp *me, const TCHAR *strOpenMode)
{

	if (me->m_fBinFile)
		BinFileWtp_CloseBinFIle(me);
	me->m_fBinFile = _tfopen((const TCHAR *)me->m_strBinFilePath, strOpenMode);
	if (NULL == me->m_fBinFile)
	{
		printf("Open BinFile.bin Failed!\n");
		return FALSE;
	}
	else
	{
		printf("Open BinFile.bin Successed!\n");
		return TRUE;
	}
}

UINT32 BinFileWtp_ReadBinFile(struct CBinFileWtp *me, void *buffer, size_t size, size_t count, const TCHAR *pszBinFile)
{
	UINT32 ret = 0;
	UINT32 uRemain = 0;
	UINT32 uRPos = 0;
	khiter_t kfs, kfp;
	kfs = kh_get(str2fs, me->m_mapFile2Struct, pszBinFile);
	if (kfs == kh_end(me->m_mapFile2Struct))
		return ret;
	uRemain = size * count;
	kfp = kh_get(str2n, me->m_mapFile2PointPos, pszBinFile);
	uRPos = kh_value(me->m_mapFile2PointPos, kfp);
	if (0 == kh_value(me->m_mapFile2Struct, kfs).Head2 && 0 == kh_value(me->m_mapFile2Struct, kfs).Mid1 && 0 == kh_value(me->m_mapFile2Struct, kfs).Mid2 && 0 == kh_value(me->m_mapFile2Struct, kfs).Tail1)
	{
		fseek(me->m_fBinFile, uRPos, SEEK_SET);
		ret = fread(buffer, size, count, me->m_fBinFile);
		kh_value(me->m_mapFile2PointPos, kfp) += size * count;
	}
	else //分段读取情况
	{
		fseek(me->m_fBinFile, uRPos, SEEK_SET);
		if (uRPos >= kh_value(me->m_mapFile2Struct, kfs).Head1 && uRPos < kh_value(me->m_mapFile2Struct, kfs).Head2)
		{
			if (uRemain < kh_value(me->m_mapFile2Struct, kfs).Head2 - uRPos)
			{
				ret += fread(buffer, sizeof(BYTE), uRemain, me->m_fBinFile);
				kh_value(me->m_mapFile2PointPos, kfp) += uRemain;
				uRemain = 0;
			}
			else
			{
				ret += fread(buffer, sizeof(BYTE), kh_value(me->m_mapFile2Struct, kfs).Head2 - uRPos, me->m_fBinFile);
				uRemain -= (kh_value(me->m_mapFile2Struct, kfs).Head2 - uRPos);
				buffer = (void *)((char *)buffer + kh_value(me->m_mapFile2Struct, kfs).Head2 - uRPos);
				uRPos = kh_value(me->m_mapFile2Struct, kfs).Mid1;
				kh_value(me->m_mapFile2PointPos, kfp) = uRPos;
				fseek(me->m_fBinFile, uRPos, SEEK_SET);
			}
		}
		if (uRPos >= kh_value(me->m_mapFile2Struct, kfs).Mid1 && uRPos < kh_value(me->m_mapFile2Struct, kfs).Mid2)
		{
			if (uRemain < kh_value(me->m_mapFile2Struct, kfs).Mid2 - uRPos)
			{
				ret += fread(buffer, sizeof(BYTE), uRemain, me->m_fBinFile);
				uRPos += uRemain;
				kh_value(me->m_mapFile2PointPos, kfp) = uRPos;
				uRemain = 0;
			}
			else
			{
				ret += fread(buffer, sizeof(BYTE), kh_value(me->m_mapFile2Struct, kfs).Mid2 - uRPos, me->m_fBinFile);
				uRemain -= (kh_value(me->m_mapFile2Struct, kfs).Mid2 - uRPos);
				buffer = (void *)((char *)buffer + kh_value(me->m_mapFile2Struct, kfs).Mid2 - uRPos);
				uRPos = kh_value(me->m_mapFile2Struct, kfs).Tail1;
				kh_value(me->m_mapFile2PointPos, kfp) = uRPos;
				fseek(me->m_fBinFile, uRPos, SEEK_SET);
			}
		}
		if (uRPos >= kh_value(me->m_mapFile2Struct, kfs).Tail1 && uRPos < kh_value(me->m_mapFile2Struct, kfs).Tail2)
		{
			ret += fread(buffer, sizeof(BYTE), uRemain, me->m_fBinFile);
			kh_value(me->m_mapFile2PointPos, kfp) += uRemain;
			uRemain = 0;
		}
	}
	return ret;
}

int BinFileWtp_FseekBin(struct CBinFileWtp *me, const TCHAR *pszBinFile, long _Offset, int _Origin)
{
	int ret;
	khint_t kfs, kfp;
	kfp = kh_get(str2n, me->m_mapFile2PointPos, pszBinFile);
	kfs = kh_get(str2fs, me->m_mapFile2Struct, pszBinFile);
	if (kfp == kh_end(me->m_mapFile2PointPos) || kfs == kh_end(me->m_mapFile2Struct))
		return -1;
	if (SEEK_SET == _Origin)
	{
		ret = fseek(me->m_fBinFile, kh_value(me->m_mapFile2Struct, kfs).Head1 + _Offset, SEEK_SET);
		kh_value(me->m_mapFile2PointPos, kfp) = kh_value(me->m_mapFile2Struct, kfs).Head1 + _Offset;
	}
	else if (SEEK_END == _Origin)
	{
		ret = fseek(me->m_fBinFile, kh_value(me->m_mapFile2Struct, kfs).Tail2 + _Offset, SEEK_SET);
		kh_value(me->m_mapFile2PointPos, kfp) = kh_value(me->m_mapFile2Struct, kfs).Tail2 + _Offset;
	}
	else
	{
		fseek(me->m_fBinFile, kh_value(me->m_mapFile2PointPos, kfp) + _Offset, SEEK_SET);
	}
	return ret;
}

UINT32 BinFileWtp_GetFileSize(struct CBinFileWtp *me, const TCHAR *pszBinFile)
{
	khiter_t kfs;
	kfs = kh_get(str2fs, me->m_mapFile2Struct, pszBinFile);
	if (kh_end(me->m_mapFile2Struct) == kfs)
		return 0;
	else
	{
		return kh_value(me->m_mapFile2Struct, kfs).Head2 - kh_value(me->m_mapFile2Struct, kfs).Head1 + kh_value(me->m_mapFile2Struct, kfs).Mid2 - kh_value(me->m_mapFile2Struct, kfs).Mid1 + kh_value(me->m_mapFile2Struct, kfs).Tail2 - kh_value(me->m_mapFile2Struct, kfs).Tail1;
	}
}

void BinFileWtp_CloseBinFIle(struct CBinFileWtp *me)
{
	if (NULL != me->m_fBinFile)
	{
		fclose(me->m_fBinFile);
		me->m_fBinFile = NULL;
	}
}

void BinFileWtp_FreshBinOffset(struct CBinFileWtp *me)
{
	fseek(me->m_fBinFile, 0, SEEK_END);
	me->m_uFileOffset = ftell(me->m_fBinFile);
}

void BinFileWtp_ResetPara(struct CBinFileWtp *me)
{
	me->m_bHaveInitForFbfDown = FALSE;
	me->m_uFileOffset = 0;
	me->m_fBinFile = NULL;
	if (me->m_mapFile2PointPos)
		kh_destroy(str2n, me->m_mapFile2PointPos);
	if (me->m_mapFile2Struct)
		kh_destroy(str2fs, me->m_mapFile2Struct);
	me->m_mapFile2PointPos = kh_init(str2n);
	me->m_mapFile2Struct = kh_init(str2fs);
}

void BinFileWtp_InitRead(struct CBinFileWtp *me)
{
	khiter_t kfs, kfp;
	int ret;
	for (kfs = kh_begin(me->m_mapFile2Struct); kfs != kh_end(me->m_mapFile2Struct); ++kfs)
		if (kh_exist(me->m_mapFile2Struct, kfs))
		{
			kfp = kh_put(str2n, me->m_mapFile2PointPos, kh_key(me->m_mapFile2Struct, kfs), &ret);
			kh_value(me->m_mapFile2PointPos, kfp) = kh_value(me->m_mapFile2Struct, kfs).Head1;
		}
}

void BinFileWtp_InitParameter(struct CBinFileWtp *me)
{
	TCHAR buffer[1024];
	khiter_t kfp, kfs;
	char *pstr;
	int ret;
	if (me->m_bHaveInitForFbfDown)
		return;
	BinFileWtp_ResetPara(me);
#if !defined(LINUX)
	memset(me->m_strBinFilePath, 0x00, sizeof(me->m_strBinFilePath));
	tsnprintf(me->m_strBinFilePath, sizeof(me->m_strBinFilePath), _T("%s\\temp\\%s"), (pstr = GetAppPath().s), BINFILE);
	free(pstr);
#else
	memset(me->m_strBinFilePath, 0x00, sizeof(me->m_strBinFilePath));
	tsnprintf(me->m_strBinFilePath, sizeof(me->m_strBinFilePath), _T("%s/temp/%s"), (pstr = GetAppPath().s), BINFILE);
	free(pstr);
#endif

	UINT32 uValue;
	BinFileWtp_OpenBinFile(me, _T("rb"));
	fseek(me->m_fBinFile, -1L * sizeof(UINT32), SEEK_END);
	//读FBF文件最后的偏移，之后的为map信息
	fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
	printf("Read from File Value is %x\n", uValue);
	uValue = le32toh(uValue);
	printf("After Convert Value is %x\n", uValue);
	fseek(me->m_fBinFile, uValue, SEEK_SET);
	//读map size
	fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
	uValue = le32toh(uValue);
	unsigned int i = uValue;
	while (i)
	{
		i--;
		memset(buffer, 0, sizeof(buffer));
		//读路径文件长度
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		//读路径文件
		uValue = le32toh(uValue);
		fread(buffer, 1, uValue, me->m_fBinFile);
		kfs = kh_put(str2fs, me->m_mapFile2Struct, buffer, &ret);
		kfp = kh_put(str2n, me->m_mapFile2PointPos, buffer, &ret);
		//读Head1
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Head1 = uValue;
		kh_value(me->m_mapFile2PointPos, kfp) = uValue;
		//读Head2
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Head2 = uValue;
		//读Mid1
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Mid1 = uValue;
		//读Mid2
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Mid2 = uValue;
		//读Tail1
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Tail1 = uValue;
		//读Tail2
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Tail2 = uValue;
	}
}
BOOL BinFileWtp_InitParameter2(struct CBinFileWtp *me, const TCHAR *pBinFilePath, struct StringList *pFbfList)
{
	TCHAR buffer[1024];
	int ret, nPosBuf;
	khiter_t kfp, kfs;
	if (me->m_bHaveInitForFbfDown)
		return TRUE;
	BinFileWtp_ResetPara(me);
	me->m_bHaveInitForFbfDown = TRUE;

#if !defined(LINUX)
	memset(me->m_strBinFilePath, 0x00, sizeof(me->m_strBinFilePath));
	tsnprintf(me->m_strBinFilePath, sizeof(me->m_strBinFilePath), _T("%s"), pBinFilePath);
#else
	memset(me->m_strBinFilePath, 0x00, sizeof(me->m_strBinFilePath));
	tsnprintf(me->m_strBinFilePath, sizeof(me->m_strBinFilePath), _T("%s"), pBinFilePath);
#endif

	UINT32 uValue = 0;
	if (FALSE == BinFileWtp_OpenBinFile(me, _T("rb")))
	{
		return FALSE;
	}
	fseek(me->m_fBinFile, -1L * sizeof(UINT32), SEEK_END);
	//读FBF文件最后的偏移，之后的为map信息
	fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
	printf("Read from File Value is %x\n", uValue);
	uValue = le32toh(uValue);
	printf("Convert Value is %x\n", uValue);
	fseek(me->m_fBinFile, uValue, SEEK_SET);
	printf("Offset of Map is %u\n", uValue);
	//读map size
	fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
	uValue = le32toh(uValue);
	printf("Size of Map is %u\n", uValue);
	unsigned int i = uValue;

	while (i)
	{
		i--;
		memset(buffer, 0, sizeof(buffer));
		//读路径文件长度
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		//读路径文件
		fread(buffer, 1, uValue, me->m_fBinFile);
#ifndef UNICODE
		nPosBuf = 0;
		for (int j = 0; j < uValue; j++)
		{
			if (buffer[j] != 0)
			{
				buffer[nPosBuf] = buffer[j];
				++nPosBuf;
			}
			buffer[nPosBuf] = 0;
		}
#endif
		const char *buf2 = strdup(buffer);
		printf("Find image name:%s\n", buf2);
		kfp = kh_put(str2n, me->m_mapFile2PointPos, buf2, &ret);
		kfs = kh_put(str2fs, me->m_mapFile2Struct, buf2, &ret);

		//读Head1
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Head1 = uValue;
		kh_value(me->m_mapFile2PointPos, kfp) = uValue;

		//读Head2
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Head2 = uValue;
		//读Mid1
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Mid1 = uValue;
		//读Mid2
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Mid2 = uValue;
		//读Tail1
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Tail1 = uValue;
		//读Tail2
		fread(&uValue, sizeof(UINT32), 1, me->m_fBinFile);
		uValue = le32toh(uValue);
		kh_value(me->m_mapFile2Struct, kfs).Tail2 = uValue;
		pFbfList->strL[pFbfList->nSize++] = buf2;
	}
	return TRUE;
}

BOOL BinFileWtp_IsFileExist(struct CBinFileWtp *me, const TCHAR *pFileName)
{
	khiter_t k;
	k = kh_get(str2fs, me->m_mapFile2Struct, pFileName);
	if (k == kh_end(me->m_mapFile2Struct))
		return FALSE;
	else
		return TRUE;
}

void BinFileWtp_DelMe(struct CBinFileWtp *me)
{
	khiter_t k;
	for (k = kh_begin(me->m_mapFile2PointPos); k != kh_end(me->m_mapFile2PointPos); ++k)
		if (kh_exist(me->m_mapFile2PointPos, k))
		{
			free((void *)kh_key(me->m_mapFile2PointPos, k));
		}
}
