
#include "WtptpDownLoad.h"
#include "WtptpDownloader.h"

struct CWtptpDownLoad   gWtptpDownload;
BOOL InitializeBL(PInstanceParams pInstParam)
{
	return WtptpDownLoad_InitializeBL(&gWtptpDownload,pInstParam);

}
#if 0
BOOL InitializeBLEx(PInstanceParams pInstParam,const TCHAR* pszBlfFile,const TCHAR* pszFBFTimfile, const TCHAR* pszFBFFile)
{
	return WtptpDownLoad_InitializeBLEx(&gWtptpDownload,pInstParam,pszBlfFile,pszFBFTimfile,pszFBFFile);

}
#endif
BOOL TerminateBL()
{
	 return WtptpDownLoad_TerminateBL(&gWtptpDownload);
}
