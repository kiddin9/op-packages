#pragma once

#include "Macrodef.h"
#include "ApplicationINI.h"
#include "ParaDefine.h"
#include <fcntl.h>
#include <sys/types.h>
#include "khash.h"
#include "klist.h"

typedef struct _FileStruct
{
	UINT32 Head1, Head2;
	UINT32 Mid1, Mid2;
	UINT32 Tail1, Tail2;
} FileStruct;

KHASH_MAP_INIT_STR(str2n,UINT32)
KHASH_MAP_INIT_STR(str2fs,FileStruct)
#define BINFILE _T("BinFile.bin")


typedef khash_t(str2n) *t_FilePathWriteOffsetMap;

typedef khash_t(str2fs)* t_FileNameFileStructMap;

BOOL BinFileWtp_OpenBinFile(struct CBinFileWtp *me,const TCHAR* strOpenMode);
UINT32 BinFileWtp_ReadBinFile(struct CBinFileWtp *me,void *buffer, size_t size, size_t count, const TCHAR* pszBinFile);
int BinFileWtp_FseekBin(struct CBinFileWtp *me,const TCHAR* pszBinFile,long _Offset,int _Origin);
BOOL BinFileWtp_IsFileExist(struct CBinFileWtp *me,const TCHAR *pFileName);
UINT32 BinFileWtp_GetFileSize(struct CBinFileWtp *me,const TCHAR* pszBinFile);
BOOL BinFileWtp_InitParameter2(struct CBinFileWtp *me,const TCHAR *pBinFilePath, struct StringList*);
void BinFileWtp_InitParameter(struct CBinFileWtp *me);
void BinFileWtp_CloseBinFIle(struct CBinFileWtp *me);
void BinFileWtp_FreshBinOffset(struct CBinFileWtp *me);
void BinFileWtp_ResetPara(struct CBinFileWtp *me);
void BinFileWtp_InitRead(struct CBinFileWtp *me);
void BinFileWtp_DelMe(struct CBinFileWtp *me);


struct CBinFileWtp
{
	FILE* m_fBinFile;
	t_FileNameFileStructMap		m_mapFile2Struct;
	t_FilePathWriteOffsetMap m_mapFile2PointPos;//文件指针位置 相对起始
	UINT32		m_uFileOffset;//Bin文件总偏移
	TCHAR		m_strBinFilePath[MAX_FILE_LENGTH];
	BOOL		m_bHaveInitForFbfDown;
};

extern struct CBinFileWtp gBinFileWtp;
