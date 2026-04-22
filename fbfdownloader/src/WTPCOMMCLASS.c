// WTPCOMMCLASS.cpp: implementation of the CWtpComm class.
//
//////////////////////////////////////////////////////////////////////
#include "./Macrodef.h"
#include <stddef.h>
#include "WTPCOMMCLASS.h"
#include <ctype.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include "WTPIOCTL.h"

#include "ErrorCode.h"
#include <errno.h>
#include <stdarg.h>


const short PACKET_SIZE = 16376;  // plus command makes 4096
#define OPEN_RETRY      10
//////////////////////////////////////////////////////////////////////
// Construction/Destruction
//////////////////////////////////////////////////////////////////////

void NewCWtpComm (struct CWtpComm *me)
{
	NewCConvertLT2B(&(me->MyConvertLT2B));
	me->m_PortType = UNKNOWNPORT;
	me->m_iPortNumber = 1;
	me->m_ThreadExit = 0;
	me->m_liTimeout = 0;
	me->m_bVerbose = FALSE;
	me->m_bMsg = FALSE;
	me->MessageMode = DISABLED;
	me->m_bBaudRateSet = FALSE;
	me->m_bInterfaceSpecified = FALSE;
	me->m_hLog = NULL;
	me->m_uiPacketSize = PACKET_SIZE;
	me->m_bfastDownload = GET;
	me->m_blastData = GET;
	me->m_bIsNonNewWTPTP = FALSE;
#if DEBUG_MODE
	me->m_bDebugTrace = TRUE;
#else
	me->m_bDebugTrace = FALSE;
#endif

}


void CWtpCommSetBootDeviceType(struct CWtpComm *me,EDeviceType eType)
{
	me->m_DeviceType = eType;
}

void SetPlatformType(struct CWtpComm *me,ePlatForm ePlatformType)
{
	me->m_PlatformType = ePlatformType;
}

void SetPortType (struct CWtpComm *me,int iSelect)
{
	switch (iSelect)
	{
	case USB:
		me->m_PortType = USB;
		break;

	case SERIALPORT:
		me->m_PortType = SERIALPORT;
		break;

	default:
		me->m_PortType = UNKNOWNPORT;
		break;
	}
}

int GetPortType (struct CWtpComm *me)
{
	return me->m_PortType;
}

void SetInterfaceName (struct CWtpComm *me,TCHAR* pInterfaceName)
{
	_tcscpy( me->m_szInterfaceName, pInterfaceName );
	me->m_bInterfaceSpecified = TRUE;
}


void SetUsbPortTimeout (struct CWtpComm *me,long int lTimeout)
{
	me->m_liTimeout = lTimeout;
}

void SetPacketSize(struct CWtpComm *me, unsigned short uiSize )
{
	me->m_uiPacketSize = (((uiSize+63)/64) * 64)-8;
}

unsigned short GetPacketSize(struct CWtpComm *me)
{
	return me->m_uiPacketSize;
}


void SetMessageMode (struct CWtpComm *me,MESSAGE_MODES MessageModeOnOff)
{
	me->MessageMode = MessageModeOnOff;
}

void HandleTraceLog(struct CWtpComm *me,const TCHAR* format,...)
{
	if(me->m_bDebugTrace)
	{	
		char szBuffer[1024];
		va_list pArgs;
		va_start (pArgs, format);
		vsprintf (szBuffer, format, pArgs);
		va_end (pArgs);
		printf(szBuffer);
		fprintf(me->m_hLog, szBuffer);
	}
}
BOOL SendPreamble (struct CWtpComm *me,BOOL bIsCustPreamble)
{
	BOOL IsOk = TRUE;
	WTPSTATUS* pWtpStatus = (WTPSTATUS*)malloc(sizeof(WTPSTATUS));
	memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
	me->m_iSequence = 0x00;

	HandleTraceLog(me,_T("SendPreamble command\n"));

	WTPCOMMAND WtpCmd = {PREAMBLE,0xD3,0x02,0x2B,htole32(0x00D3022B)};
	IsOk = WriteUSB(me,&WtpCmd,4);
	if(IsOk)
	{
		if(!ReadUSB (me,pWtpStatus,4+34))
		{
			IsOk = FALSE;
		}

		if (pWtpStatus->CMD != PREAMBLE && pWtpStatus->SEQ != 0xD3 && pWtpStatus->CID != 0x02)
		{
			IsOk = FALSE;
#if PRINTLOG
			printf("SendPreamble returned a wrong status\n");
#endif
			fprintf(me->m_hLog, "SendPreamble returned a wrong status\n");
		}
		if (pWtpStatus->Status == NACK)
		{
			IsOk = FALSE;
#if PRINTLOG			
			printf("Error: SendPreamble returned a NACK!\n");
#endif
			fprintf(me->m_hLog,"Error: SendPreamble returned a NACK!\n");
		}


		HandleTraceLog(me,"ReadUSB is ok in sending preamble...\n");


	}
	free( pWtpStatus);
	return IsOk;
}

BOOL GetVersion (struct CWtpComm *me,WTPSTATUS *pWtpStatus)
{
	HandleTraceLog(me,_T("GetVersion command......\n"));
	BOOL IsOk = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {GETVERSION,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
	pWtpStatus->Flags = 0x01;
	HandlePendingMessages(me,pWtpStatus);

	HandleTraceLog(me,_T("WriteUSB in GetVersion command\n"));
	IsOk = WriteUSB (me,&WtpCmd,8);

	if(IsOk)
	{
		IsOk = FALSE;
		HandleTraceLog(me,_T("ReadUSB in GetVersion command\n"));
		IsOk = ReadUSB(me,pWtpStatus,30);
		if(!IsOk)
		{
			HandleTraceLog(me,_T("ReadUSB failed in GetVersion command\n"));
			return FALSE;
		}
		if (IsOk && pWtpStatus->Status == NACK)
		{
			IsOk = FALSE;
#if PRINTLOG
			printf("Error: GetVersion returned a NACK!\n");
#endif
			fprintf(me->m_hLog,"Error: GetVersion returned a NACK!\n");
		}

	}
	else
	{
		HandleTraceLog(me,_T("WriteUSB failed in GetVersion command\n"));
		return FALSE;
	}

	HandleTraceLog(me,_T("GetVersion command return\n"));
	return IsOk;
}

BOOL GetBadBlockInfo(struct CWtpComm *me,WTPSTATUS *pWtpStatus)
{
	BOOL IsOk = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {GETBADBLOCK,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	
	if (kBootLoader == me->m_DeviceType)
	{
		memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
		pWtpStatus->Flags = 0x01;

		HandlePendingMessages(me, pWtpStatus );

		HandleTraceLog(me,_T("WriteUSB in GetBadBlockInfo command\n"));
		IsOk = WriteUSB (me,&WtpCmd,8);

		if(IsOk)
			
		{
			IsOk = FALSE;
			HandleTraceLog(me,_T("ReadUSB in GetBadBlockInfo command\n"));
			IsOk = ReadUSB(me,pWtpStatus,6+sizeof(BadBlockData));
			if(!IsOk)
			{
				HandleTraceLog(me,_T("ReadUSB failed in GetBadBlockInfo command\n"));
				return FALSE;
			}			
		}
		else
		{
			HandleTraceLog(me,_T("WriteUSB failed in GetBadBlockInfo command\n"));
			return FALSE;
		}

		if (pWtpStatus->Status == NACK)
		{
			IsOk = FALSE;
#if PRINTLOG
			printf("Error: GetVersion returned a NACK!\n");
#endif

			tfprintf(me->m_hLog,"Error: GetVersion returned a NACK!\n");
		}

		fflush(me->m_hLog);
	}
	return IsOk;
}

BOOL GetImageCrc(struct CWtpComm *me,WTPSTATUS *pWtpStatus)
{
	BOOL IsOk = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {GETIMAGECRC,me->m_iSequence,0x00,0x00,htole32(0x00000000)};

	if (kBootLoader == me->m_DeviceType)
	{
		memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
		pWtpStatus->Flags = 0x01;

		HandlePendingMessages(me, pWtpStatus );

		HandleTraceLog(me,_T("WriteUSB in GetImageCrc command\n"));
		IsOk = WriteUSB (me,&WtpCmd,8);

		if(IsOk)
			
		{
			IsOk = FALSE;
			HandleTraceLog(me,_T("ReadUSB in GetImageCrc command\n"));
			IsOk = ReadUSB(me,pWtpStatus,6+sizeof(ImageCRCInfo));
			if(!IsOk)
			{
				HandleTraceLog(me,_T("ReadUSB failed in GetImageCrc command\n"));
				return FALSE;
			}			
		}
		else
		{
			HandleTraceLog(me,_T("WriteUSB failed in GetImageCrc command\n"));
			return FALSE;
		}

		if (pWtpStatus->Status == NACK)
		{
			IsOk = FALSE;
			tfprintf(me->m_hLog,_T("Error: GetImageCrc returned a NACK!\n"));
		}

		fflush(me->m_hLog);
	}
	return IsOk;
}


BOOL SelectImage (struct CWtpComm *me,UINT32 *pImageType)
{
	HandleTraceLog(me,_T("SelectImage command\n"));
	WTPCOMMAND WtpCmd = {SELECTIMAGE,0x00,0x00,0x00,htole32(0x00000000)};
	WTPSTATUS* pWtpStatus = (WTPSTATUS*)malloc(sizeof(WTPSTATUS));
	memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
	BOOL Isok = TRUE;
	HandlePendingMessages(me, pWtpStatus );

			if (WriteUSB (me,&WtpCmd,8) == FALSE)
				Isok = FALSE;
			if (Isok)
			{            
				if(ReadUSB (me,pWtpStatus,10) == FALSE)
				{
					Isok = FALSE;
				}
				else
				{
					if (pWtpStatus->Status == NACK)
					{
						Isok = FALSE;
#if PRINTLOG						
						printf("Error: SelectImage returned a NACK!\n");
#endif
						fprintf(me->m_hLog,"Error: SelectImage returned a NACK!\n");
					}
					if(me->m_bDebugTrace)
					{					
						for(int i =0; i<4; i++)
							tprintf(_T("pWtpStatus->Data[%d] =%c\n"),i,pWtpStatus->Data[i]);
					}
					*pImageType = pWtpStatus->Data[0];
					*pImageType |= pWtpStatus->Data[1] << 8;
					*pImageType |= pWtpStatus->Data[2] << 16;
					*pImageType |= pWtpStatus->Data[3] << 24;

				}
			}

	HandlePendingMessages(me, pWtpStatus );
	free( pWtpStatus);
	pWtpStatus = NULL;

	HandleTraceLog(me,_T("SelectImage command return\n"));
	return Isok;
}


BOOL VerifyImage (struct CWtpComm *me,BYTE AckOrNack)
{
	HandleTraceLog(me,_T("VerifyImage command\n"));

	BOOL IsOk = TRUE, EnableMessages = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {VERIFYIMAGE,me->m_iSequence,0x00,0x00,htole32(0x00000001),AckOrNack};
	WTPSTATUS* pWtpStatus = (WTPSTATUS*)malloc(sizeof(WTPSTATUS));
	DWORD BytesRead = 0;
	memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
	//HandlePendingMessages( pWtpStatus );

			if (WriteUSB (me,&WtpCmd,9) == FALSE)
				IsOk = FALSE;
			if(IsOk)
			{
				if (ReadUSB (me,pWtpStatus,6) == FALSE)
				{
					IsOk = FALSE;
				}
			}

	if (AckOrNack == NACK)
	{
		IsOk = FALSE;
#if PRINTLOG		
		printf(_T("\nError: Image asked for by target does not exist!"));
#endif
		tfprintf (me->m_hLog,_T("\nError: Image asked for by target does not exist!"));
	}
	if (pWtpStatus->Status == NACK)
	{
		IsOk = FALSE;
#if PRINTLOG
		printf(_T("\nError: VerifyImage returned a NACK!"));		
#endif
		tfprintf (me->m_hLog,_T("\nError: VerifyImage returned a NACK!"));		
	}

	HandlePendingMessages(me,pWtpStatus );
	free( pWtpStatus);
	pWtpStatus = NULL;

	HandleTraceLog(me,_T("VerifyImage command return\n"));
	return IsOk;
}

BOOL DataHeader (struct CWtpComm *me,unsigned int uiRemainingData,WTPSTATUS *pWtpStatus,BOOL bFastDownload)
{
	HandleTraceLog(me,_T("DataHeader command\n"));

	BOOL IsOk = TRUE;
	WTPCOMMAND WtpCmd = {DATAHEADER,++me->m_iSequence,0x00,0x00,htole32(4)};
	DWORD BytesRead = 0, StatusLength = 0;
	/* Fix me please. getFastDownload is buggy*/
	if(me->m_bDebugTrace)
	{
		tfprintf (me->m_hLog,_T("\nDataHeader command, uiRemainingData size:%d\n"),uiRemainingData);        
	}

	//if (isFastDownload(GET, FDMODE))
	if (bFastDownload)
		WtpCmd.Flags = 0x4;

	HandlePendingMessages(me, pWtpStatus );
	WtpCmd.Data[0] = uiRemainingData & 0x000000FF;
	WtpCmd.Data[1] = (uiRemainingData & 0x0000FF00) >> 8;
	WtpCmd.Data[2] = (uiRemainingData & 0x00FF0000) >> 16;
	WtpCmd.Data[3] = (uiRemainingData & 0xFF000000) >> 24;
	pWtpStatus->Status = ACK;

			if (WriteUSB (me,&WtpCmd,12) == FALSE)
				IsOk = FALSE;
			if(IsOk)
			{     
				//make workaround for helan2 bootrom download,05/06/2014,llzhou
				if(PLAT_HELAN2 == me->m_PlatformType)
				{
					usleep(20000); 
				}

				if (ReadUSB (me,pWtpStatus,10) == FALSE)
				{
					IsOk = FALSE;
				}
				else
				{
					if (pWtpStatus->Status == NACK)
					{
						IsOk = FALSE;
#if PRINTLOG
						printf("Error: DataHeader returned a NACK!\n");
#endif
						fprintf(me->m_hLog,"Error: DataHeader returned a NACK!\n");
					}
					if(me->m_bDebugTrace)
					{
						for(int i =0; i<4; i++)
							tprintf(_T("pWtpStatus->Data[%d] =%d\n"),i,pWtpStatus->Data[i]);
					}

				}
			}

	HandlePendingMessages(me, pWtpStatus );

	HandleTraceLog(me,_T("DataHeader command return\n"));

	return IsOk;
}

BOOL Data (struct CWtpComm *me,PBYTE pData,UINT32 Length)
{
	HandleTraceLog(me,_T("Data command\n"));

	BOOL IsOk = TRUE;
	WTPCOMMAND WtpCmd = {DATA,++me->m_iSequence,0x00,0x00,htole32(Length)};
	WTPSTATUS* pWtpStatus = (WTPSTATUS*)malloc(sizeof(WTPSTATUS));
	DWORD BytesRead = 0;
	unsigned int tmp = 0;
	BOOL bFoundChar = TRUE;

	memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
	//  HandlePendingMessages( pWtpStatus );
			if (isFastDownload (me,GET, FDMODE))
			{
				HandleTraceLog(me,_T("Begin WriteUSBWithNoRsp\n"));
				if (WriteUSBWithNoRsp (me,pData,(DWORD)Length) )
				{
					HandleTraceLog(me,_T("Finish WriteUSBWithNoRsp\n"));
					if (isLastData(me,GET, FDMODE))
					{       
						HandleTraceLog(me,_T("Begin ReadUSB\n"));
						if(!ReadUSB (me,pWtpStatus,6))
						{
							free( pWtpStatus);
							return FALSE;
						}
						HandleTraceLog(me,_T("Finish ReadUSB\n"));

						if(pWtpStatus->CMD!=WtpCmd.CMD&&pWtpStatus->Status == NACK)
						{
							free( pWtpStatus);
							return FALSE;
						}

						if(me->m_bDebugTrace)
						{
							tprintf (_T("\nBytesRead : %lu GetWTPMESSAGE:%x %x %x %x %x %x \n"),
								BytesRead,
								pWtpStatus->CMD,
								pWtpStatus->SEQ,
								pWtpStatus->CID,
								pWtpStatus->Status,
								pWtpStatus->Flags,
								pWtpStatus->DLEN);
						}

					}
				}
				else
				{
					IsOk = FALSE;
				}

			}
			else
			{
				memcpy(WtpCmd.Data,pData,Length);
				HandleTraceLog(me,_T("Begin WriteUSB\n"));
				if (WriteUSB (me,&WtpCmd,8 + (DWORD)Length) == FALSE)
				{
					IsOk = FALSE;
				}
				else
				{
					HandleTraceLog(me,_T("Begin ReadUSB\n"));
					if (ReadUSB (me,pWtpStatus,6) == FALSE)
					{
						IsOk = FALSE;
					}
				}

			}

	HandlePendingMessages(me, pWtpStatus );
	free( pWtpStatus);
	pWtpStatus = NULL;

	HandleTraceLog(me,_T("Data command return\n"));

	return IsOk;

}

BOOL Done (struct CWtpComm *me)
{

	HandleTraceLog(me,_T("Done command\n"));

	BOOL IsOk = TRUE, EnableMessages = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {DONE,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	WTPSTATUS* pWtpStatus = (WTPSTATUS*)malloc(sizeof(WTPSTATUS));
	DWORD BytesRead = 0;

	memset( pWtpStatus, 0, sizeof(WTPSTATUS) );
	pWtpStatus->Flags = 0x01;
	HandlePendingMessages(me, pWtpStatus );
			if (WriteUSB (me,&WtpCmd,8) == FALSE)
				IsOk = FALSE;
			if (ReadUSB(me,pWtpStatus,6) == FALSE)
			{
				IsOk = FALSE;
			}
			else
			{
				if(pWtpStatus->CMD!=DONE)
				{
					if (WriteUSB (me,&WtpCmd,8) == FALSE)
						IsOk = FALSE;
					else
					{
						if (ReadUSB(me,pWtpStatus,6) == FALSE)
						{
							IsOk = FALSE;
						}
						//  Sleep(100);
						if (ReadUSB(me,pWtpStatus,6) == FALSE)
						{
							IsOk = FALSE;
						}

						if(pWtpStatus->CMD!=DONE)
						{
							IsOk = FALSE;
						}

						if (pWtpStatus->Status == NACK)
						{
							IsOk = FALSE;	
#if PRINTLOG
							printf ("Error: Done returned a NACK!");
#endif
							fprintf (me->m_hLog,"Error: Done returned a NACK!");
						}
					}

				}
			}
	HandlePendingMessages(me, pWtpStatus );

	free( pWtpStatus);
	pWtpStatus = NULL;

	HandleTraceLog(me,_T("Done command return\n"));

	return IsOk;
}

BOOL Disconnect (struct CWtpComm *me,WTPSTATUS* pWtpStatus)
{

	BOOL IsOk = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {DISCONNECT,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	DWORD BytesRead;
	HandlePendingMessages(me, pWtpStatus );

	HandleTraceLog(me,_T("Disconnect command\n"));


			if (!WriteUSB (me,&WtpCmd,8))
			{
				IsOk = FALSE;
			}
			else
			{
				if (ReadUSB (me,pWtpStatus,6) == FALSE)
				{
					IsOk = FALSE;
				}
				if (pWtpStatus->Status == NACK)
				{
					//now try disconnect once more
					pWtpStatus->Status = ACK;

					HandlePendingMessages(me, pWtpStatus );
					if (WriteUSB(me,&WtpCmd,8) == FALSE)
						IsOk = FALSE;
					if(IsOk)
					{
						if (ReadUSB(me,pWtpStatus,6) == FALSE)
						{
							IsOk = FALSE;
						}
					}

				}
			}
	HandlePendingMessages(me, pWtpStatus );


	if(IsOk == FALSE)
		pWtpStatus->Status = NACK;


	HandleTraceLog(me,_T("Disconnect command return\n"));

	return IsOk;

}



BOOL GetWtpMessage (struct CWtpComm *me,WTPSTATUS *pWtpStatus)
{
	//tfprintf (m_hLog,_T("\n GetWtpMessage..........\n"));
	BOOL IsOk = TRUE, bFoundChar = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {MESSAGE,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	DWORD StatusLength, BytesRead;
	TCHAR WtpMessage[MESSAGELENGTH];
	int i;

	memset (WtpMessage,'\0',MESSAGELENGTH);

	pWtpStatus->Status = NACK;
	switch (me->m_PortType)
	{
	case USB:
		{
			if (!WriteUSB(me,&WtpCmd,8))
			{
				IsOk = FALSE;
				tfprintf (me->m_hLog,_T("\nWriteUsb failed in GetWtpMessage\n"));
			}
			else
			{
				if (pWtpStatus->DLEN > 0)
				{
					pWtpStatus->Status = ACK;
					//	IsOk = FALSE;
					//	return IsOk;
				}
				if (pWtpStatus->Status != ACK) 
				{
					pWtpStatus->Status = NACK;
					//IsOk = FALSE;
					//	return IsOk;
				}
				if (ReadUSB (me,pWtpStatus,6 + MESSAGELENGTH) == FALSE)
				{
					IsOk = FALSE;
				}
				else
				{
					switch(me->m_DeviceType)
					{
					case kBootLoader:
						{
							UINT32 ReturnCode = 0;
							int i   ;
							for ( i = 0; i < 4; i++)
							{
								ReturnCode |= pWtpStatus->Data[i+2] << (8 * i);
							}
							if(pWtpStatus->Data[0]== WTPTPNOTIFICATION)
							{
								BOOL bFound = FALSE;
								for (i = 0; i < MAXNOTIFICATIONSCODES; i++)
								{
									if (WTPTPNotificationMsg[i].NotificationCode == ReturnCode)
									{
#ifndef COMPRESSDATA
                                        tfprintf (me->m_hLog,_T("\nWTPTP Notification: %s 0x%X\n"),WTPTPNotificationMsg[i].Description,ReturnCode);
#else
                                        tfprintf (me->m_hLog,_T("\nWTPTP Notification: 0x%X\n"),ReturnCode);
#endif
                                        bFound = TRUE;
										break;;
									}

								}
								if(!bFound)
								{
									tfprintf (me->m_hLog,_T("\nNotification Code: 0x%X\n"),ReturnCode);
								}
							}
							else if(pWtpStatus->Data[0]== WTPTPERRORREPORT && kBootLoader == me->m_DeviceType)
							{
								TCHAR szMessage[1024];
								BOOL bFound = FALSE;
								for (i = 0; i < MAXERRORCODES; i++)
								{
									if (WTPTPErrorCodes[i].ErrorCode == ReturnCode)
									{


										#ifndef COMPRESSDATA
										tfprintf (me->m_hLog,_T("\nWTPTP Error: %s : Errorcode is 0x%X\n"),WTPTPErrorCodes[i].Description,ReturnCode);
										#else
										tfprintf (me->m_hLog,_T("\nWTPTP Errorcode is 0x%X\n"),ReturnCode);
										#endif
										bFound = TRUE;
										break;
									}
								}

								if(!bFound)
								{


									tfprintf (me->m_hLog,_T("\nUser customized ErrorCode: 0x%X\n"),ReturnCode);



								}

								IsOk = FALSE;

							}
							else if (WTPTPNOTIFICATION_UPLOAD == pWtpStatus->Data[0])
							{
								tfprintf (me->m_hLog,_T("\nFlash_NandID: 0x%X\n"),ReturnCode);
							}
							else if (WTPTPNOTIFICATION_FLASHSIZE == pWtpStatus->Data[0])
							{

								tfprintf (me->m_hLog,_T("\nFlash_Size: 0x%X bytes\n"),ReturnCode);
							}
						}
						break;
					default:
						break;
					}
				}
			}
		}
	}
	return IsOk;
}

BOOL GetTargetMessage (struct CWtpComm *me,WTPSTATUS *pWtpStatus)
{

	BOOL IsOk = TRUE;
	unsigned long int Seconds = 0, DelayTime = 120;


	while ( (pWtpStatus->Status == ACK) && Seconds <DelayTime )
	{

		tfprintf (me->m_hLog,_T("\n GetWtpMessage...\n"));
		if (!GetWtpMessage (me,pWtpStatus))
		{

			IsOk = FALSE;
			break;
		}

		// This is to add a delay for WTPTP while DKB is busy on the target.
		if (pWtpStatus->Data[0] == PlatformBusy && kBootLoader == me->m_DeviceType  )
		{
			do
			{
				GetWtpMessage(me,pWtpStatus);

				if ( pWtpStatus->Data[0] == PlatformDisconnect )
					break;
				tfprintf (me->m_hLog,_T("\n usleep(2000000) in GetWtpMessage...\n"));
				usleep(2000000);
				Seconds += 2000;

			}
			while(pWtpStatus->Data[0] != PlatformReady);
		}
		tfprintf (me->m_hLog,_T(" Platform ready status: %X\n"), pWtpStatus->Data[0]);

		if ( pWtpStatus->Data[0] == PlatformDisconnect )
		{
			tfprintf (me->m_hLog,_T("Target requested disconnect!!!\n"));
			return FALSE;
		}


		if ( pWtpStatus->Data[0] == PlatformReady && (pWtpStatus->Flags & 0x1) != MESSAGEPENDING)
		{
			break;
		}

	}

	return IsOk;
}


int OpenUsbPort (struct CWtpComm *me)
{
	tfprintf(me->m_hLog,_T("\ntry to openUsbPort:%s....\n"),me->m_pLinuxUsb->DevName);
	me->m_bXDB_BREAKPOINT_RETRY = TRUE;
	_tcscpy(me->m_szDeviceName,me->m_pLinuxUsb->DevName);
	int retry = 0;
	system("echo ---begin open usb--- > /dev/kmsg");
Retry:
	retry++;
	int retValue = BulkDevNonDrv_OpenDev(me->m_pLinuxUsb);
	if(0 == retValue)
	{
#if PRINTLOG
		perror(_T("open"));
#endif
		usleep(5000*100);
		if(retry<OPEN_RETRY)  //2000*5000 = 2000*0.005s = 10s
			{
#if PRINTLOG
			printf("\nRetry openning\n");
#endif
			goto Retry;
			}
		else
			{
			tfprintf(me->m_hLog,_T("\nopenUsbPort  timeout\n"));
			}
	}
	tfprintf(me->m_hLog,_T("\nopenUsbPort  m_fdUsb = %s....\n"),me->m_pLinuxUsb->DevName);
	return retValue;
}


BOOL CloseUsbPort(struct CWtpComm *me)
{
	//tfprintf(m_hLog,_T("\nCloseUsbPort....\n"));
	if (me->m_pLinuxUsb->hDevHandle != 0)
		BulkDevNonDrv_CloseDev(me->m_pLinuxUsb);
#if PRINTLOG
	tprintf(_T("\nCloseUsbPort devName = %s....\n"),me->m_pLinuxUsb->DevName);
#endif
	return TRUE;
}


void HandlePendingMessages(struct CWtpComm *me, WTPSTATUS *pWtpStatus )
{
	// this is a bogus way to let the bootrom that uses a small packetsize
	// have a little more time to process the command

	HandleTraceLog(me,_T("HandlePendingMessages CMD\n"));

	pWtpStatus->Status = ACK;
	do
	{
		if ((pWtpStatus->Flags & 0x1 )== MESSAGEPENDING )
		{
			GetTargetMessage (me,pWtpStatus);
			HandleTraceLog(me,_T("HandlePendingMessages CMD\n"));
		}
		else
		{
			HandleTraceLog(me,_T("HandlePendingMessages break\n"));
			break;
		}
	}
	while( pWtpStatus->Status != ACK );

	HandleTraceLog(me,_T("HandlePendingMessages return\n"));

}


BOOL isFastDownload(struct CWtpComm *me,BOOL mode, BOOL value)          //added to set/get the fast download mode.
{

	if (mode)
		me->m_bfastDownload = value;
	else
		return me->m_bfastDownload;

	return FDMODE;
}
BOOL isLastData(struct CWtpComm *me,BOOL mode, BOOL value)   //added to set/get the last data condition.
{

	if (mode)
		me->m_blastData = value;
	else
		return me->m_blastData;

	return FDMODE;
}
BOOL WriteUSB(struct CWtpComm *me,WTPCOMMAND* pWtpCmd,size_t dwSize)
{
	HandleTraceLog(me,_T("WriteUSB\n"));
	BOOL bRes = TRUE;
	size_t dwBytes = -1;
	int iMsgCnt = 0;

	if(me->m_ThreadExit==STOPFLAG)
	{
		tfprintf(me->m_hLog,_T("Thread is to be exit"));
		return FALSE;
	}

	if (me->m_pLinuxUsb->hDevHandle == -1)
	{
#if PRINTLOG
		tprintf(_T("\nError: device is not exist\n"));
#endif
		return FALSE;
	}
Retry:
#ifdef MACDOWNLOAD
	int iVal = m_WtptpCommunicator.Write(pWtptpDev,pWtpCmd, dwSize);
	if(iVal!=0)
	{
		fprintf(me->m_hLog, "Write USB failed\n");
		bRes = FALSE;
	}
#else
	 dwBytes = BulkDevNonDrv_Write(me->m_pLinuxUsb,pWtpCmd,dwSize);
	if(dwBytes<=0)
		bRes = FALSE;
#endif
	if (!bRes)
	{
		tfprintf(me->m_hLog,_T("\nError: write failed and return -1\n"));
#if PRINTLOG
		printf(_T("\nError: write failed and return -1 iMsgCnt=%d\n"),iMsgCnt);
#endif
		iMsgCnt++;

		usleep(200);

		if ( iMsgCnt == 10 )
		{
#if PRINTLOG			
			tprintf(_T("Error: Write failed with error %s.\n"),strerror(errno));
#endif
			return FALSE;

		}

		usleep(1000);
		goto Retry;
	}
	else
	{
		HandleTraceLog(me,_T("WriteUSB dwBytes = %d\n"),dwBytes);
	}
	return bRes;
}

BOOL WriteUSBWithNoRsp (struct CWtpComm *me,BYTE *pData,size_t dwSize)
{
	TCHAR Message[256] = {0};
	BOOL bRes = TRUE;
	size_t dwBytes = -1;
	int iMsgCnt = 0;

	if(me->m_ThreadExit==STOPFLAG)
	{
		tfprintf(me->m_hLog,_T("Thread is to be exit"));
		return FALSE;
	}

	if (me->m_pLinuxUsb->hDevHandle == -1)
	{
		sprintf (Message,_T("  Error: device is not exist!"));
		tfprintf(me->m_hLog,_T("\n%s\n"),Message);
		return FALSE;
	}

	if(me->m_bDebugTrace)
	{
		sprintf (Message,_T("WriteUSBWithNoRsp  dwSize is %d"),dwSize);
		tfprintf(me->m_hLog,_T("\n%s\n"),Message);
		tprintf(_T("\n%s\n"),Message);
	}
Retry:

#ifdef MACDOWNLOAD
	int iVal = me->m_WtptpCommunicator.Write(pWtptpDev,pData, dwSize);
	if(iVal!=0)
	{
		fprintf(me->m_hLog, "SelectImage Write USB failed\n");
		bRes = FALSE;
	}
#else
	dwBytes = BulkDevNonDrv_Write (me->m_pLinuxUsb,pData,dwSize);
	if(dwBytes<=0)
		bRes = FALSE;
#endif

	if (!bRes)
	{
		iMsgCnt++;
		if(me->m_bDebugTrace)
		{
			tprintf(_T("Retry in WriteUSBWithNoRsp\n"));
		}
		if ( iMsgCnt == 20 )
		{
#ifdef PRINTLOG
			tprintf(_T("Error: Write failed with error: %s,ErrorCode:%d.\n"),strerror(errno),errno);
#endif
			fprintf(me->m_hLog,_T("Error: Write failed with error: %s,ErrorCode:%d.\n"),strerror(errno),errno);

			return FALSE;

		}

		usleep(1000);
		goto Retry;
	}
	return bRes;
}

BOOL ReadUSB (struct CWtpComm *me,WTPSTATUS *pWtpStatus,size_t dwSize)
{

	BOOL bRes = TRUE;
	size_t dwBytes = -1;
	int iMsgCnt = 0;

	if(me->m_ThreadExit==STOPFLAG)
	{
		tfprintf(me->m_hLog,_T("Thread is to be exit"));
		return FALSE;
	}
	if (me->m_pLinuxUsb->hDevHandle == -1)
	{
#if PRINTLOG
		tprintf (_T("  Error: device is not exist!\n"));
#endif
		tfprintf(me->m_hLog,_T("\n Error: device is not exist!\n"));
		return FALSE;
	}
	memset(pWtpStatus,0,sizeof(WTPSTATUS));
Retry:

#ifdef MACDOWNLOAD
	int ival = me->m_WtptpCommunicator.Read(pWtptpDev,pWtpStatus, dwSize);
	if(ival!=0)
	{
		fprintf(me->m_hLog, "Read USB failed\n");
		bRes = FALSE;
	}
#else
	dwBytes = BulkDevNonDrv_Read(me->m_pLinuxUsb,pWtpStatus,dwSize,0);
	if(dwBytes<=0)
		bRes = FALSE;
#endif
	if (!bRes)
	{
		iMsgCnt++;

		HandleTraceLog(me,_T("Retry in ReadUSB\n"));

		if(iMsgCnt == 10 )
		{        
			tfprintf(me->m_hLog,_T("Error: ReadUSB failed with error %s.errno = %d\n"),strerror(errno),errno);
#if PRINTLOG
			tprintf(_T("Error: ReadUSB failed with error %s.errno = %d\n"),strerror(errno),errno);
#endif
			return FALSE;
		}

		usleep(1000);
		goto Retry;
	}
	else
	{
		//tfprintf(m_hLog,_T("\nReadUSB dwBytes = %d\n"),dwBytes);
		TCHAR m_szMessage[256];
		sprintf (m_szMessage,_T("\nBytesRead : %d pWtpStatus:%x %x %x %x %x %x %x"),
			dwBytes,
			pWtpStatus->CMD,
			pWtpStatus->SEQ,
			pWtpStatus->CID,
			pWtpStatus->Status,
			pWtpStatus->Flags,
			pWtpStatus->DLEN,
			pWtpStatus->Data[0]);

		//  tfprintf (m_hLog,_T("\nReadUSB message%s\n"),m_szMessage);
		HandleTraceLog(me,_T("\nReadUSB message%s\n"),m_szMessage);
		if (dwBytes<1)
		{
			iMsgCnt++;

			HandleTraceLog(me,_T("Retry in ReadUSB for read bytes is 0\n"));

			if(iMsgCnt == 10 )
			{
#if PRINTLOG
				tprintf(_T("Error: ReadUSB failed for no data got.\n"),strerror(errno));
#endif
				return FALSE;

			}

			usleep(1000);
			goto Retry;
		}
	}

	return bRes;
}
// features added to support upload   2010-12-28
BOOL GetProtocolVersion (struct CWtpComm *me, PROTOCOL_VERSION* pTargetProtocolVersion )
{
	WTPSTATUS WtpStatus = {0};
	BOOL IsOk = TRUE, EnableMessages = TRUE, bFoundChar = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {PROTOCOLVERSION,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	DWORD BytesRead = 0, StatusLength = 0;


	//set to defaults
	memset( &WtpStatus, 0, sizeof(WTPSTATUS) );
	HandlePendingMessages(me, &WtpStatus );

	if(me->m_bDebugTrace)
	{
#if PRINTLOG		
		tprintf(_T("GetProtocolVersion....\n"));
#endif
	}
	IsOk = WriteUSB (me,&WtpCmd,8);

	if(IsOk)
	{
		IsOk = FALSE;
		IsOk = ReadUSB(me,&WtpStatus,6+sizeof(PROTOCOL_VERSION));

	}

	if (WtpStatus.Status == NACK)
	{
		IsOk = FALSE;
		tsprintf (me->m_szMessage,_T("  Error: GetProtocolVersion returned a NACK!"));

	}
	else if (WtpStatus.Status == ACK)
	{
		if ( pTargetProtocolVersion )
		{
			if ( WtpStatus.DLEN != sizeof(PROTOCOL_VERSION) )
				tfprintf(me->m_hLog,_T("nProtocolVersion returned LEN is not correct! LEN == %c\n"), WtpStatus.DLEN);

			memset( pTargetProtocolVersion, 0, sizeof(PROTOCOL_VERSION) );
			pTargetProtocolVersion->MajorVersion = WtpStatus.Data[0];
			pTargetProtocolVersion->MinorVersion = WtpStatus.Data[1];
			pTargetProtocolVersion->Build = Endian16ConvertLToB(&me->MyConvertLT2B,*((short*)&WtpStatus.Data[2])) ;

			tfprintf(me->m_hLog,_T("\nProtocolVersion: %d"), pTargetProtocolVersion->MajorVersion);
			tfprintf(me->m_hLog,_T(".%d"), pTargetProtocolVersion->MinorVersion);
			tfprintf(me->m_hLog,_T(".%d\n"), pTargetProtocolVersion->Build);
			fflush(me->m_hLog);
			if(me->m_bDebugTrace)
			{
				tprintf(_T("\nProtocolVersion: %d"), pTargetProtocolVersion->MajorVersion);
				tprintf(_T(".%d"), pTargetProtocolVersion->MinorVersion);
				tprintf(_T(".%d\n"), pTargetProtocolVersion->Build);
			}
		}
	}
	else
	{
		//Do nothing!
	}

	HandlePendingMessages(me, &WtpStatus );

	return IsOk;
}


BOOL GetParameters (struct CWtpComm *me, TARGET_PARAMS* pTargetParams )
{
	WTPSTATUS WtpStatus = {0};
	BOOL IsOk = TRUE, EnableMessages = TRUE, bFoundChar = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {GETPARAMETERS,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	DWORD BytesRead = 0, StatusLength = 0;


	HandlePendingMessages(me, &WtpStatus );
	if(me->m_bDebugTrace)
	{
		tprintf(_T("GetParameters....\n"));
	}
	if (!WriteUSB (me,&WtpCmd,8))
	{
		IsOk = FALSE;
	}
	if(IsOk)
	{
		IsOk = FALSE;
		IsOk = ReadUSB(me,&WtpStatus,6+sizeof(TARGET_PARAMS));

	}

	if (WtpStatus.Status == NACK)
	{
		IsOk = FALSE;
		tfprintf(me->m_hLog,_T("  Error: GetParameters returned a NACK!"));
		fflush( me->m_hLog);
	}
	else if (WtpStatus.Status == ACK)
	{
		if ( WtpStatus.DLEN != 16 )
		{
			tfprintf(me->m_hLog,_T("GetParameters returned LEN is not correct! LEN == %c\n"), WtpStatus.DLEN);
		}


		tfprintf(me->m_hLog, _T("\nBuffer Size: %d"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[0])));
		tfprintf(me->m_hLog, _T("\nRsvd1: %d"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[4])));
		tfprintf(me->m_hLog, _T("\nRsvd2: %d"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[8])));
		tfprintf(me->m_hLog, _T("\nRsvd3: %d\n"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[12])));
		fflush( me->m_hLog);
		pTargetParams->BufferSize = Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[0]));
		pTargetParams->Rsvd1 = Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[4]));
		pTargetParams->Rsvd2 = Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[8]));
		pTargetParams->Rsvd3 = Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[12]));

		if(me->m_bDebugTrace)
		{
			tprintf(_T("\nBuffer Size: %d"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[0])));
			tprintf(_T("\nRsvd1: %d"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[4])));
			tprintf(_T("\nRsvd2: %d"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[8])));
			tprintf(_T("\nRsvd3: %d\n"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)(&WtpStatus.Data[12])));
		}
	}
	else
	{
		//Do nothing!
	}

	HandlePendingMessages(me, &WtpStatus );

	return IsOk;

}


BOOL UploadDataHeader (struct CWtpComm *me, UPLOAD_DATA_PARAMS* pUploadDataParams )
{
	WTPSTATUS WtpStatus = {0};
	BOOL IsOk = TRUE, EnableMessages = TRUE, bFoundChar = TRUE;
	me->m_iSequence = 0x00;
	unsigned int i = 0;
	WTPCOMMAND WtpCmd = {UPLOADDATAHEADER,me->m_iSequence,0x00,0x00,htole32(sizeof(UPLOAD_DATA_PARAMS))};
	DWORD BytesRead = 0, StatusLength = 0;

	// put upload parameters in
	memcpy( WtpCmd.Data, pUploadDataParams, sizeof(UPLOAD_DATA_PARAMS) );

	HandlePendingMessages(me, &WtpStatus );

	if(me->m_bDebugTrace)
	{
		tprintf(_T("UploadDataHeader....\n"));
	}

	if (!WriteUSB (me,&WtpCmd,8+sizeof(UPLOAD_DATA_PARAMS)))
	{
		IsOk = FALSE;
	}
	if(IsOk)
	{
		IsOk = FALSE;
		IsOk = ReadUSB(me,&WtpStatus,6);

	}

	if (WtpStatus.Status == NACK)
	{
		IsOk = FALSE;
		//  tsprintf (m_szMessage,);
		tfprintf(me->m_hLog, _T("  Error: UploadDataHeader returned a NACK!"));
		if(WtpStatus.DLEN > 0)
		{
			tfprintf(me->m_hLog, _T("\nErrorCode in UploadData Header: %x\n"), Endian32ConvertLToB(&me->MyConvertLT2B,*(unsigned int*)&WtpStatus.Data[0]));
#if PRINTLOG
			for (i = 0; i < MAXERRORCODES; i++)
			{
				if (WTPTPErrorCodes[i].ErrorCode == WtpStatus.Data[0])
				{
#ifndef COMPRESSDATA
					tprintf(_T("Code: %s\n"), WTPTPErrorCodes[i].Description);
#endif
                    tprintf(_T("0x%x\n"), WtpStatus.Data[0]);
				}
			}
#endif
		}

	}
	fflush( me->m_hLog);
	HandlePendingMessages(me, &WtpStatus );

	return IsOk;
}

BOOL UploadData(struct CWtpComm *me, PBYTE pData, unsigned int Length , WTPSTATUS* pWtpStatus)
{

	BOOL IsOk = TRUE, EnableMessages = TRUE, bFoundChar = TRUE;
	me->m_iSequence = 0x00;
	WTPCOMMAND WtpCmd = {UPLOADDATA,me->m_iSequence,0x00,0x00,htole32(0x00000000)};
	DWORD StatusLength = Length;

	unsigned int i = 0;

	HandlePendingMessages(me, pWtpStatus );

	if (!WriteUSBWithNoRsp (me,(PBYTE)&WtpCmd,8))
	{
		IsOk = FALSE;
	}
	if(IsOk)
	{
		IsOk = FALSE;
		IsOk = ReadUSB(me,pWtpStatus, 6+StatusLength);

	}

	if (pWtpStatus->Status == NACK)
	{
		IsOk = FALSE;
		//tsprintf (m_szMessage,);
		tfprintf(me->m_hLog,_T("Error: Data returned a NACK!"));

	}
	else
	{
		// copy data back to data buffer
		// exclude the 6 bytes used for the wtpstatus at the head of the packet
		memcpy( pData, pWtpStatus->Data, StatusLength );
		HandlePendingMessages(me, pWtpStatus);
	}

	fflush( me->m_hLog);
	return IsOk;
}
void SetLogFile(struct CWtpComm *me,FILE *hLog)  {me->m_hLog = hLog;}
FILE * GetLogFile(struct CWtpComm *me) {return me->m_hLog;}
void SetExitHandle(struct CWtpComm *me,int ThreadExit)	{me->m_ThreadExit = ThreadExit;}
BOOL GetWTPTPFlag(struct CWtpComm *me){return me->m_bIsNonNewWTPTP;}
void SetWTPTPFlag(struct CWtpComm *me,BOOL IsNonNewWTPTP){me->m_bIsNonNewWTPTP = IsNonNewWTPTP;}
void SetLinuxDev(struct CWtpComm *me,USB_HANDLE* pLinuxDev) {  me->m_pLinuxUsb = pLinuxDev;}
USB_HANDLE* GetLinuxDev(struct CWtpComm *me) {  return me->m_pLinuxUsb ;}

