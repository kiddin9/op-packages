#pragma once
#pragma warning ( disable : 4100 ) // Disable warning messages: unreferenced formal parameter
#pragma warning ( disable : 4189 ) // Disable warning messages: local variable is initialized but not referenced
#include <stdio.h>
#include <wchar.h>
#include <stdlib.h>
#include "klist.h"
#include "kstring.h"
#ifdef LINUX
#include <endian.h>
#if defined(__BYTE_ORDER__)&&(__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#define htobe16(x)  (x)
#define htobe32(x)  (x)
#define htobe64(x)  (x)
#define htole16(x)  __builtin_bswap16(x)
#define htole32(x)  __builtin_bswap32(x)
#define htole64(x)  __builtin_bswap64(x)
#else
#define htobe16(x)  __builtin_bswap16(x)
#define htobe32(x)  __builtin_bswap32(x)
#define htobe64(x)  __builtin_bswap64(x)
#define htole16(x)  (x)
#define htole32(x)  (x)
#define htole64(x)  (x)
#endif /* __BYTE_ORDER__ */
#define be16toh(x)  htobe16(x)
#define le16toh(x)  htole16(x)
#define be32toh(x)  htobe32(x)
#define le32toh(x)  htole32(x)
#define be64toh(x)  htobe64(x)
#define le64toh(x)  htole64(x)

#include <memory.h>
#include <unistd.h> 
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

#define _tmain main
#define _TCHAR TCHAR
#define _fseeki64 fseeko
#ifndef VOID
#define VOID void
typedef char CHAR;
typedef short SHORT;
typedef long LONG;
#endif

#undef FALSE
#undef TRUE
#undef NULL
#define FALSE   0
#define TRUE    1
#define NULL    0

#ifdef UNICODE     
#define _T L##     
#define TCHAR  wchar_t
#define _tprintf wprintf  
#define _tcslen  wcslen
#define tsnprintf  snwprintf 
#define _tcslen		wcslen
#define _tcscmp  wcscmp
#define _tfopen  _wfopen
#define _tcsstr  wcsstr
#define _tcscat  wcscat
#define _taccess    access
#define _tcstoul    wcstoul
#define _tcsrchr        wcsrchr
#define _tcscpy         wcscpy
#define _tcsncpy   wcsncpy
#define _ttoi    _wtoi
#define _ttot    _itow
#define _vstprintf vswprintf
#define _trename _wrename
#define _tremove  _wremove
#define _stscanf swscanf
#else     
#define _T    
#define TCHAR   char
#define _tprintf printf   
#define _tcslen  strlen
#define tsnprintf  snprintf
#define _tcslen		strlen
#define _tcscmp  strcmp
#define _tfopen  fopen
#define _tcsstr   strstr
#define _tcscat   strcat
#define _taccess   access
#define _tcstoul    strtoul
#define _tcsrchr        strrchr
#define _tcscpy         strcpy
#define _tcsncpy   strncpy
#define _ttoi    atoi
#define _ttot    itoa
#define _vstprintf vsprintf
#define _trename  rename
#define _tremove  remove
#define _stscanf sscanf
#endif  

#else
#ifdef UNICODE
#define tsnprintf  _snwprintf 
#else
#define tsnprintf  _snprintf 
#endif
#endif


#ifdef UNICODE
#define tsprintf  swprintf
#define taccess   _waccess
#define tatoi     _wtoi
#define titoa     _itow
#define tsscanf     swscanf
#define ttolower     towlower
#define ttoupper     towupper
#define tfprintf     fwprintf
#define tprintf      wprintf

#define t_splitpath_s  _wsplitpath_s

#else
#define tsprintf  sprintf
#define taccess   access
#define tatoi     atoi
#define titoa     itoa
#define tsscanf     sscanf
#define ttolower     tolower
#define ttoupper     toupper
#define tfprintf     fprintf
#define tprintf      printf
#define t_splitpath_s  _splitpath_s
#endif


#define ACCESS_FILE_EXIST 0
#define COMPARE_EQUAL	  0


