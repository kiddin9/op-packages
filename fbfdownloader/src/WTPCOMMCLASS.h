// WTPCOMMCLASS.h: interface for the CWtpComm class.
//
//////////////////////////////////////////////////////////////////////

#if !defined(AFX_WTPCOMMCLASS_H__EFECE7AD_7863_476C_A5A5_65A1D728610A__INCLUDED_)
#define AFX_WTPCOMMCLASS_H__EFECE7AD_7863_476C_A5A5_65A1D728610A__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000
#include <string.h>
#include "define.h"
#include "WTPdef.h"
#include "ParaDefine.h"
#include "ConvetEdian.h"
#include "ApplicationINI.h"
#include "BulkDevNonDrv_Linux.h"

static const PROTOCOL_VERSION TARGET_PROTOCOL_VERSION = {0x01, 0x01, 0x0000}; 

struct CWtpComm
{
	/*void GetCustomizePreambleCmd(pWTPTPREAMBLECOMMAND pCustCmd);*/
		struct CConvertLT2B MyConvertLT2B;
		

		
        

		USB_HANDLE * m_pLinuxUsb;
	    int m_PortType;
		int m_iPortNumber;
		BYTE m_iSequence;
		size_t m_BytesWritten, m_BytesRead;
		long int m_liTimeout;
		TCHAR m_szMessage[1024];
		BOOL m_bVerbose;
		BOOL m_bLogFile;
		BOOL m_bMsg;
		volatile int  m_ThreadExit;
		MESSAGE_MODES MessageMode;
		BOOL m_bBaudRateSet;
		TCHAR m_szInterfaceName[256];
		TCHAR m_szDeviceName[256];
		BOOL m_bInterfaceSpecified;
		unsigned int m_uiPacketSize;
		BOOL m_bXDB_BREAKPOINT_RETRY;
		//pWTPTPREAMBLECOMMAND m_pCustPreambleCmd;
		FILE *m_hLog;
		BOOL m_bfastDownload ;
		BOOL m_blastData ;
		BOOL m_bIsNonNewWTPTP;
		BOOL m_bDebugTrace;
		EDeviceType m_DeviceType;
		ePlatForm   m_PlatformType;
	
};
void NewCWtpComm (struct CWtpComm *me);
void SetPortType (struct CWtpComm *me,int iSelect);
int GetPortType (struct CWtpComm *me);
void SetUsbPortTimeout (struct CWtpComm *me,long int lTimeout);
int OpenUsbPort (struct CWtpComm *me);
BOOL CloseUsbPort (struct CWtpComm *me);
BOOL SendPreamble (struct CWtpComm *me,BOOL bIsCustPreamble);
BOOL GetVersion (struct CWtpComm *me,WTPSTATUS *pWtpStatus);
BOOL GetBadBlockInfo(struct CWtpComm *me,WTPSTATUS *pWtpStatus);
BOOL GetImageCrc(struct CWtpComm *me,WTPSTATUS *pWtpStatus);
BOOL SelectImage (struct CWtpComm *me,UINT32 *pImageType);
BOOL VerifyImage (struct CWtpComm *me,BYTE AckOrNack);
BOOL DataHeader (struct CWtpComm *me,unsigned int uiRemainingData,WTPSTATUS *pWtpStatus, BOOL bFastDownload);
BOOL Data (struct CWtpComm *me,PBYTE pData,UINT32 Length);
BOOL DebugBoot (struct CWtpComm *me,PBYTE pFlashType);
BOOL Done (struct CWtpComm *me);
BOOL Disconnect (struct CWtpComm *me,WTPSTATUS *pWtpStatus);
BOOL PublicKey (struct CWtpComm *me);
BOOL Password (struct CWtpComm *me,WTPSTATUS *pWtpStatus);
BOOL SignedPassword (struct CWtpComm *me);
BOOL GetWtpMessage (struct CWtpComm *me,WTPSTATUS *pWtpStatus);
BOOL GetTargetMessage (struct CWtpComm *me,WTPSTATUS *pWtpStatus);
void SetFlashType (struct CWtpComm *me,BYTE FlashCode);
BYTE GetFlashType (struct CWtpComm *me);
BOOL OtpView (struct CWtpComm *me);
void SetLogFileMode (struct CWtpComm *me,BOOL bLogOnOff);
void SetInterfaceName (struct CWtpComm *me,TCHAR* pInterfaceName);
void SetMessageMode (struct CWtpComm *me,MESSAGE_MODES MessageModeOnOff);
BOOL WaitForHostReply (struct CWtpComm *me,WTPSTATUS *pWtpStatus,int nCharsRead,int nTotalChars);
void SetPacketSize(struct CWtpComm *me, unsigned short uiSize );
unsigned short GetPacketSize(struct CWtpComm *me);
void SetLogFile(struct CWtpComm *me,FILE *hLog);
FILE * GetLogFile(struct CWtpComm *me);
int GetUSBPort(struct CWtpComm *me);
void SetExitHandle(struct CWtpComm *me,int ThreadExit);
BOOL GetWTPTPFlag(struct CWtpComm *me);
void SetWTPTPFlag(struct CWtpComm *me,BOOL IsNonNewWTPTP);
void HandlePendingMessages(struct CWtpComm *me,WTPSTATUS *pWtpStatus);
BOOL isLastData(struct CWtpComm *me,BOOL mode, BOOL value);   //added to set/get the last data condition.
BOOL WriteUSB (struct CWtpComm *me,WTPCOMMAND* pWtpCmd,size_t dwSize);
BOOL WriteUSBWithNoRsp (struct CWtpComm *me,BYTE *pData,size_t dwSize);
BOOL ReadUSB (struct CWtpComm *me,WTPSTATUS *WtpStatus,size_t dwSize);
BOOL isFastDownload(struct CWtpComm *me,BOOL mode, BOOL value); 	
// features added to support upload
BOOL GetProtocolVersion (struct CWtpComm *me, PROTOCOL_VERSION* pTargetProtocolVersion );
BOOL GetParameters (struct CWtpComm *me, TARGET_PARAMS* pTargetParams );
BOOL UploadDataHeader (struct CWtpComm *me, UPLOAD_DATA_PARAMS* pUploadDataParams );
BOOL UploadData(struct CWtpComm *me, PBYTE pData, unsigned int Length , WTPSTATUS* pWtpStatus);
BOOL HandleUploadDataPacket(struct CWtpComm *me, PBYTE pData, unsigned int Length );
void HandleTraceLog(struct CWtpComm *me,const TCHAR* format,...);
void CWtpCommSetBootDeviceType(struct CWtpComm *me,EDeviceType eType);
void SetPlatformType(struct CWtpComm *me,ePlatForm ePlatformType);
void SetLinuxDev(struct CWtpComm *me,USB_HANDLE* pLinuxDev);
USB_HANDLE* GetLinuxDev(struct CWtpComm *me);

#endif // !defined(AFX_WTPCOMMCLASS_H__EFECE7AD_7863_476C_A5A5_65A1D728610A__INCLUDED_)
