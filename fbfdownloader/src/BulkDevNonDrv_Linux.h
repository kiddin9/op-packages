#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <dirent.h>
#include <fcntl.h>
#include <errno.h>
#include <pthread.h>
#include <ctype.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/usbdevice_fs.h>
#include <linux/usbdevice_fs.h>
#include <linux/version.h>
#if LINUX_VERSION_CODE > KERNEL_VERSION(2, 6, 20)
#include <linux/usb/ch9.h>
#else
#include <linux/usb_ch9.h>
#endif
#include <asm/byteorder.h>

#ifdef __ANDROID__
#include <sys/stat.h>
#endif

#define MAX_DEVNUM 5
#define MAX_FILE_LENGTH 1024

static int HWIds_WTPTPTable[37][3] =
{
    {0x8086, 0xE001, -1},
    {0x8086, 0xC001, -1},
    {0x8086, 0xD001, -1},
    {0x1286, 0x8100, -1},
    {0x1286, 0x8101, -1},
    {0x1286, 0x8102, -1},
    {0x1286, 0x8103, -1},
    {0x1286, 0x8104, -1},
    {0x1286, 0x8105, -1},
    {0x1286, 0x8106, -1},
    {0x1286, 0x8111, -1},
    {0x1286, 0x8112, -1},
    {0x1286, 0x8113, -1},
    {0x1286, 0x8114, -1},
    {0x1286, 0x8115, -1},
    {0x1286, 0x8116, -1},
    {0x1286, 0x8117, -1},
    {0x1286, 0x8118, -1},
    {0x1286, 0x8128, -1},
    {0x1286, 0x8129, -1},
    {0x1286, 0x812a, -1},
    {0x1286, 0x8130, -1},
    {0x1286, 0x8164, -1},
    {0x1286, 0x8170, -1},
    {0x1286, 0x8165, -1},
    {0x1286, 0x8174, -1},
    {0x1286, 0x8175, -1},
    {0x1286, 0x8181, -1},
    {0x1286, 0x8182, -1},
    {0x1286, 0x8189, -1},
    {0x1286, 0x8167, -1},
    {0x2ECC, 0x3001, -1},
    {0x2ECC, 0x3002, -1},
    {0x2ECC, 0x3003, -1},
    {0x19D2, 0x1491, -1},
	{0x305A, 0x1413, -1},

    {0x0, 0x0, 0x0}
};

static int HWIds_USBDiagTable[11][3] =
{
    {0x1286, 0x4E3C, 0},
    {0x1286, 0x4E38, 4},
    {0x1286, 0x4E2C, 0},
    {0x1286, 0x4E28, 4},
    {0x1286, 0x4E30, 0},
    {0x1286, 0x4E31, 2},
    {0x0BB4, 0x4E49, 0},
    {0x0BB4, 0x4E4A, 4},
    {0x0BB4, 0x4E4D, 3},
    {0x0BB4, 0x4E4E, 0},
    {0x0, 0x0, 0x0}
};


static int (*HWIds_CurrentTable)[3] = HWIds_WTPTPTable;

typedef struct _USB_HANDLE
{
    char DevName[256];
    char iSerialNumber[256];
    int hDevHandle;
    int nPipeIn;
    int nPipeOut;


} USB_HANDLE, *PUSB_HANDLE;
static void NEW_USB_HANDLE(PUSB_HANDLE me)
{
    memset(me->DevName, 0, sizeof(me->DevName));
    memset(me->iSerialNumber, 0, sizeof(me->iSerialNumber));
    me->hDevHandle = -1;
    me->nPipeIn = -1;
    me->nPipeOut = -1;
}

static void COPY_USB_HANDLE(PUSB_HANDLE me, PUSB_HANDLE pusb)
{
	strcpy(me->DevName, pusb->DevName);
	strcpy(me->iSerialNumber, pusb->iSerialNumber);
    me->hDevHandle = pusb->hDevHandle;
    me->nPipeIn = pusb->nPipeIn;
    me->nPipeOut = pusb->nPipeOut;
}


typedef struct _USB_IFC_INFO
{
    unsigned short dev_vendor;
    unsigned short dev_product;

    unsigned char dev_class;
    unsigned char dev_subclass;
    unsigned char dev_protocol;

    unsigned char ifc_class;
    unsigned char ifc_subclass;
    unsigned char ifc_protocol;

    unsigned char has_bulk_in;
    unsigned char has_bulk_out;

    unsigned char writable;

    char serial_number[256];
} USB_IFC_INFO, *PUSB_IFC_INFO;

int BulkDevNonDrv_OpenDev(USB_HANDLE *usb);
int BulkDevNonDrv_CloseDev(USB_HANDLE *usb);
int BulkDevNonDrv_Write(USB_HANDLE *h, const void *_data, int nLen);
int BulkDevNonDrv_Read(USB_HANDLE *h, void *_data, int nLen, int timeout);
int BulkDevNonDrv_CheckDevForNetLink(USB_HANDLE *usb, const char *NetLinkBuff, int nBuffLen, int *bAdd);
int BulkDevNonDrv_WaitDev();
int BulkDevNonDrv_FindAllSupportedDevices(PUSB_HANDLE hUSBArray[]);
int BulkDevNonDrv_check(void *_desc, int nLen, unsigned int type, int size);
int BulkDevNonDrv_badname(const char *name);
int BulkDevNonDrv_ChecHWIds(long idVendor, long idProduct, long MI);
int BulkDevNonDrv_IsSupported(const char *NetLinkBuff, int nBuffLen, char *Dev_Name, int *nDevNameLen, int *bAdd);
int BulkDevNonDrv_GetPipeOfDev(/*int fd, */char *ptr, int nLen, int *ept_in_id, int *ept_out_id, int *ifc_id);
#define BulkDevNonDrv_ChecHWIds2(a,b) BulkDevNonDrv_ChecHWIds(a,b,-1)