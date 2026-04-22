
#include "ConvetEdian.h"




UINT32 Endian32ConvertLToB(struct CConvertLT2B *me,UINT32 InputNum)
{
    if(!me->m_bIsLittleEndian)  ////big endian ,please convert
    {
        UINT32 ConvertNum =((((UINT32)(InputNum) & 0xff000000) >> 24) 
						+ (((UINT32)(InputNum) & 0x00ff0000) >> 8) 
						+ (((UINT32)(InputNum) & 0x0000ff00) << 8)
						+ (((UINT32)(InputNum) & 0x000000ff) << 24));
        return ConvertNum;

    }
    else
    {
        return InputNum;
    }

}


UINT16 Endian16ConvertLToB(struct CConvertLT2B *me,UINT16 InputNum)
{
    if(!me->m_bIsLittleEndian) //big endian ,please convert
    {
        return ((((UINT16)(InputNum) & 0xff00) >> 8) |(((UINT16)(InputNum) & 0x00ff) << 8));
    }
    else
    {
        return InputNum;
    }

}

void IsLittleEndian(struct CConvertLT2B *me)
{
    int a=1;
    char *b;
    b = (char *)&a;
    if((*b)==1)
    {
        me->m_bIsLittleEndian = TRUE;
        //tprintf (_T("Little Endian\n"));
    }
    else
    {
        me->m_bIsLittleEndian = FALSE;         
        //tprintf (_T("Big Endian\n"));      
    }
}
void NewCConvertLT2B (struct CConvertLT2B *me)
{
    me->m_bIsLittleEndian = TRUE;
    IsLittleEndian(me);
}

