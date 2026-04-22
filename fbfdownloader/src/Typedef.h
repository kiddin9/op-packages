/******************************************************************************
 *
 *  (C)Copyright 2001-2009 Marvell. All Rights Reserved.
 *  
 *  THIS IS UNPUBLISHED PROPRIETARY SOURCE CODE OF MARVELL.
 *  The copyright notice above does not evidence any actual or intended 
 *  publication of such source code.
 *  This Module contains Proprietary Information of Marvell and should be
 *  treated as Confidential.
 *  The information in this file is provided for the exclusive use of the 
 *  licensees of Marvell.
 *  Such users have the right to use, modify, and incorporate this code into 
 *  products for purposes authorized by the license agreement provided they 
 *  include this notice and the associated copyright notice with any such
 *  product. 
 *  The information in this file is provided "AS IS" without warranty.
 *
 ******************************************************************************/
 
#ifndef _TYPEDEF_H_
#define _TYPEDEF_H_


#include "Macrodef.h"

typedef volatile unsigned long 	VUINT32_T;
typedef unsigned long 		   	UINT32_T;
typedef volatile unsigned int  	VUINT_T;
typedef unsigned int 		   	UINT_T;
typedef int			 		   	INT_T;
typedef unsigned short 		   	UINT16_T, USHORT;
typedef volatile unsigned short VUINT16_T;
typedef unsigned char 			UINT8_T;
typedef char		 		INT8_T;
typedef int                 BOOL;



#ifdef LINUX
typedef unsigned long		*PDWORD;
typedef unsigned char       *PBYTE;
typedef unsigned int        	UINT,     *PUINT;    // The size is not important
typedef unsigned long long  	UINT64,   *PUINT64;
typedef unsigned int        	UINT32,   *PUINT32;
typedef unsigned short      	UINT16,   *PUINT16;
typedef unsigned char       	UINT8,    *PUINT8;
typedef unsigned char       	UCHAR,BYTE,*PUCHAR;
typedef unsigned long		    DWORD;
typedef BYTE*                    LPBYTE;

typedef int                 	INT,      *PINT;    // The size is not important
typedef long long           	INT64,    *PINT64;
typedef int                 	INT32,    *PINT32;
typedef short               	INT16,    *PINT16;
typedef signed char             INT8,     *PINT8;
#define VOID void
#define PVOID void*
#else
#include "stdafx.h"
#endif


#define LOCKED     				1
#define UNLOCKED   				0



typedef void(*FnPVOID)(void);





typedef volatile  UINT      	VUINT,    *PVUINT;    // The size is not important
typedef volatile  UINT64    	VUINT64,  *PVUINT64;
typedef volatile  UINT32    	VUINT32,  *PVUINT32;
typedef volatile  UINT16    	VUINT16,  *PVUINT16;
typedef volatile  UINT8     	VUINT8,   *PVUINT8;
typedef volatile  UCHAR     	VUCHAR,   *PVUCHAR;

typedef volatile  INT       	VINT,     *PVINT;    // The size is not important
typedef volatile  INT64     	VINT64,   *PVINT64;
typedef volatile  INT32     	VINT32,   *PVINT32;
typedef volatile  INT16     	VINT16,   *PVINT16;
typedef volatile  INT8      	VINT8,    *PVINT8;
typedef volatile  CHAR      	VCHAR,    *PVCHAR;

typedef struct{
	UINT_T	ErrorCode;
	UINT_T	StatusCode;
	UINT_T 	PCRCode;
}FUNC_STATUS, *pFUNC_STATUS;

#ifdef LINUX
#ifdef _UNICODE
#define My_strcpy(a,b,c)    wcscpy(a,c)
#else
#define My_strcpy(a,b,c)    strcpy(a,c)
#endif
#else
#ifdef _UNICODE
#define My_strcpy(a,b,c)    _tcscpy_s(a,b,c)
#else
#define My_strcpy(a,b,c)    strcpy(a,c)
#endif
#endif// LINUX



#endif //_TYPEDEF_H_
