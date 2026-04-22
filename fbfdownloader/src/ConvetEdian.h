#pragma once

#include "Typedef.h"
#include <stdlib.h>
#include <stdio.h>
struct CConvertLT2B
{
	BOOL    m_bIsLittleEndian;
};

UINT32 Endian32ConvertLToB(struct CConvertLT2B *me,UINT32 InputNum);
UINT16 Endian16ConvertLToB(struct CConvertLT2B *me,UINT16 InputNum);
void IsLittleEndian(struct CConvertLT2B *me);
void NewCConvertLT2B (struct CConvertLT2B *me);


