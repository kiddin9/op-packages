#ifndef PARADEFINE_H
#define PARADEFINE_H

#include "./Macrodef.h"
#include "./Typedef.h"
#include "ErrorCode.h"
#include "./UploadParaDef.h"
#include "kstring.h"
#define BADBLOCKRATE_BASE 10000

extern struct CWtptpDownLoad   gWtptpDownload;
extern struct CBinFileWtp gBinFileWtp;


#define __pstrl_free(x)
KLIST_INIT(pstrl,kstring_t*,__pstrl_free)


struct StringList
{
	const char* strL[64];
	int nSize;
};

typedef struct
{
	UINT32 ImageID;
	UINT32 BadCnt;
}ImageBBInfo;

typedef struct
{
	UINT32 ImageID;
	UINT32 CRC32;
}CRCInfo;

// Badblock data
typedef struct {
	UINT32  TotalBadBlocks;
	UINT32  TotalBlocks;
	ImageBBInfo BadCount[8]; //reserved for critical partitions support
} BadBlockData, *pBadBlockData;

// Image CRC data
typedef struct
{
	UINT32 	MCPID;
	UINT32	ImageNum;
	CRCInfo ImageCRC[32]; //Crc32 of all images, support 32 images at maximum
}ImageCRCInfo, *pImageCRCInfo;


typedef enum EProcessState
{
	kProcIdle				=  0,	// Not active
	kProcInit				=  1,	// Initialization
    kProcBootRom            =  2,   // Initialization for BootRom
	kProcPrepareData		=  3,	// Preparation images downloading
    kProcConnecting         =  4,   // Open connection and handshake
	kProcDownloading 		=  5,	// Downloading Data
	kProcAborting		    =  6,	// Aborting in process
	kProcFileCompleted      =  7,	// File downloading process is completed
	kProcCompleted          =  8,	// Downloading process is completed
	kProcUsbRemove          =  9,   // Usb device is removed
	kProcDebugLog			=  10,  // Debug message report
	kProcBurningFlash       =  11,  // Burning Data
	kProcUploadingData      =  12,  // Uploading Data
	kProcWaitingUploadData  =  13,  // Waiting UE to get upload data
	kProcEraseAllFlash      =  14,  // Erase all Flash
	kProcErrorCode          =  15,  // Error code in downloading
	kProcFuseInfo			=  16,  // fuse Info
	kProcFuseInfoError		=  17,  // fuse Info operate error report
    kProcUEInfo			    =  18,  // fuse Info
	kProcStateMax           =  0xfe
}eProcessState;


typedef enum
{
 	stOK,						// Finished OK
 	stInvalid,				// Couldn't create instance
 	stUsbError,				// Couldn't connect to the USB driver
 	stNoReply,				// Target is not responding
 	stBadReply,				// Protocol error
 	stDownloadMBError,		// Downloading error
 	stFailedToConnect,		// Handshake failure/TimeOut
 	stFailedFileCreate,       // Create file failed
 	stParseFile,		 	    // Parse file error
 	stEmptyFileList,			// Image file list is empty
 	stFileError,				// AXF file not found or file format error
 	stFilePathError,			// File path is not exist
 	stAborted,				// Aborted using abort Process()
 	stThreadError,			// Error creating the instance thread
 	stNack,					// Not acknowledge
 	stCalculationError,		// Check sum calculation error
 	stImgConversionFail,		// Error Image conversion
 	stImgCheckOverlapFail,    // Error image overlap
 	stImgBuildFail,           // Error image build
 	stFolderError,			// Work folder error
 	stMepBndError,			// Error binding Mep data
 	stBurningFlashError,      // Error in burning flash 
 	stUEErrorTrace	= 0xff	// Target error trace
} eProcessStatus;


//Providing  process evaluation information via Callback function
typedef struct _NotifyStatus
{
	int             nDevice,				// Active device number
					nDevType,				// Device type 	kUnknown = 0, kBootRom	= 1, kBootloader = 2
					nDownloadedPercent;		// Downloading percent
	TCHAR	        pszProcMsg[1024];		// Callback message
	TCHAR			pszUSBPortAddress[260];	// USB socket address
	BadBlockData	lpBadBlk;				// flash bad block data
	ImageCRCInfo	lpImageCrc;				// CRC value of Images read back from flash
	eProcessState   eProcState;				// Current process state
	eProcessStatus  eProcStatus;			// Current process status
	int             nErrorCode;             // Errorcode in download or burning



}NotifyStatus, *PProcInfo;


typedef void (/*__stdcall*/ * CALLBACKPROC)(PProcInfo  pNotifyInfo);


typedef klist_t(pstrl)*           t_stringList;
typedef kliter_t(pstrl)* t_stringListIter;

typedef struct _DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC
{
	t_stringList*    pImagelist;
	kstring_t        sVendorDDRId;
	kstring_t        sFlashInfo;
	int             TotalVendorDDRTypeNum;
    int             TotalFlashTypeNum;
} DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC,*pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC; 


#define __dfdi_free(x)
KLIST_INIT(dfdil,DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC*,__dfdi_free)


typedef klist_t(dfdil)*           t_DdrFlashDownloadImgInfoList;
typedef kliter_t(dfdil)* t_DdrFlashDownloadImgInfoIter;

#define CMDDATALENGTH 8196
typedef struct _WTPTPREAMBLECOMMAND
{
	BYTE CMD;
	BYTE SEQ;
	BYTE CID;
	BYTE Flags;
	UINT32 LEN;
	BYTE Data[CMDDATALENGTH];

}WTPTPREAMBLECOMMAND,*pWTPTPREAMBLECOMMAND;





#define CFG_VERSION		        _T("V1.3")
#define CFG_SECTION_NAME		_T("DownloadPackageCfg")
#define CFG_VERSION_NUMBER		_T("CfgVersion")
#define CFG_IMAGE_NUM			_T("ImageNum")	
#define CFG_FBF_SET_NUM         _T("FbfSetNum")	
#define CFG_DDRTYPE_NUM         _T("DDRVendorTypeNum")	
#define CFG_FLASHTYPE_NUM       _T("FlashTypeNum")
#define CFG_IMAGE_IDX			_T("Image_")
#define CFG_DDREMMC_TYPE		_T("DDRVendorID_EMMC")	
#define CFG_DDRTYPE_NAME		_T("DDRVendorName")	
#define CFG_DDRTYPE_ID		    _T("DDRVendorID")
#define CFG_FLASH_INFO			_T("FlashInfo")
#define CFG_DKB_BIN				_T("DKBbin")
#define CFG_DKB_TIM				_T("DKBTim")
#define CFG_OBM_FILE			_T("OBMFile")
#define CFG_TZII_FILE		    _T("TZIIFile")
#define CFG_WTM_FILE			_T("WTMFile")
#define CFG_IMEI_FILE			_T("IMEIFile")
#define CFG_MEP_FILE			_T("MEPFile")
#define CFG_PLATFORM_TYPE		_T("PlatFormType")
#define CFG_FLASH_TYPE			_T("FlashFamilyType")
#define CFG_COMMAND 			_T("Command")
#define CFG_FLASH_PAGE_SIZE		_T("FlashPageSize")
#define CFG_PRODUCTIONMODE		_T("ProductionMode")

#define MAX_RESERVED_DATA  4

typedef struct _InstanceParams
{
    t_DdrFlashDownloadImgInfoList * pDownloadImagesList;
	const TCHAR*  	pszDKBbin;		// Download file  for Bootrom
	const TCHAR* 	pszDKBTim;		// Primary flasher file path(*.bin, *.axf, *.elf) (can be either Comm. or App flasher)
	const TCHAR* 	pszOBMFile;			// OBM file path
	const TCHAR* 	pszWTMFile;			// WTM file path
	const TCHAR*    pszTZIIFile;        //TZII file path
	const TCHAR* 	pszJTAGKeyFile;		// OEM Key file path to do re-eanble JTAG in case JTAG is disable
	CALLBACKPROC	CallbackProc;		// Callback function that will back relevant process information
	pWTPTPREAMBLECOMMAND pWtptpPreaCmd; // Customize Preamble Command
	unsigned int    PlaformType;        /* 2-MMP2   */
										/* 3-WUKONG */
										/* 4-PXA978   */
										/* 5-MMP3   */
	                                    /* 6-PXA1802  */
	                                    /* 8-PXA988/986 */
	                                    /* 9-PXA1088 */
	                                    /* 10-PXA1928 */
	                                    /* 11-PXA1920 */
										/* 15-PXA1826 */
	unsigned int    FlashType;          // 0-NAND, 1-eMMC,3-SPINOR,4-ONENAND,others-Unknown
	unsigned int    Commands;           // flags description /* bit switches */, user only need to set bit3 if user want to use customized preamble
	                                      /*bit 0:Erase all flash flag*/  
	                                      /*bit 1: Upload flag */
	                                      /*bit 2: Reset BBT flag */
	                                      /*bit 3: Customized preamble flag*/
	                                      /*bit 4: erase all flash only flag */
	                                      /*bit 5: JTAG Re enable flag */
	                                      /*bit 6 ~ bit31 reserved */
    unsigned int    FlashPageSize;      // Nand Flash Data page size
	unsigned int    DownloadMode;       // Single_Download 1,multi_download 0;
	unsigned int    ProductionMode;     // ;
	unsigned int    GetBadBlk;			//get flash bad block enabled 1; otherwise: 0
	unsigned int    ImageCrcEn;       // Image CRC enabled: 1,Image CRC disabled: 0;
	unsigned int    ReservedVal[MAX_RESERVED_DATA];                                           
	t_UpLoadDataSpecList* pUploadSpecs; // Upload spec Info   
	
}InstanceParams, *PInstanceParams;

#ifndef COMPRESSDATA
static ERRORCODETABLE WTPTPErrorCodes[MAXERRORCODES]=
{
	{NoError,_T("NoError")},            		  			
	{NotFoundError,_T("NotFoundError")},      					
	{GeneralError,_T("GeneralError")},       					
	{WriteError,_T("WriteError")},         					
	{ReadError,_T("ReadError")}	,	   				
	{NotSupportedError,_T("NotSupportedError")} , 					
	{InvalidPlatformConfigError,_T("InvalidPlatformConfigError")},		
	{InvalidPlatformState,_T("InvalidPlatformState")},				
	{InvalidSizeError,_T("InvalidSizeError")},				
	{ProbeListExhaustError,_T("ProbeListExhaustError")},				
	{DDR_NotInitializedError,_T("DDR_NotInitializedError")},				
	{UnknownReservedPackage,_T("UnknownReservedPackage")},				
	{NULLPointer,_T("NULLPointer")},
	{NANDIDDISMATCH	,_T("NANDIDDISMATCH")},             
	{FBF_VersionNotMatch,_T("FBF_VersionNotMatch")},    
	{FBF_DeviceMoreThanOne,_T("FBF_DeviceMoreThanOne")},
	{PlatformConfigBuckError,_T("PlatformConfigBuckError")},
	{ChipIdMismatch,_T("ChipIdMismatch")},
	{EraseError,_T("EraseError	")},	 			
	{ProgramError,_T("ProgramError")},					
	{InvalidBootTypeError,_T("InvalidBootTypeError")},				
	{ProtectionRegProgramError,_T("ProtectionRegProgramError")},			
	{NoOTPFound,_T("NoOTPFound")},					
	{BBTReadError,_T("BBTReadError")},						
	{MDOCInitFailed,_T("MDOCInitFailed	")},					
	{OneNandInitFailed,_T("OneNandInitFailed")},               
	{MDOCFormatFailed,_T("MDOCFormatFailed ")},                   
	{BBTExhaustedError,_T("BBTExhaustedError ")},                  
	{NANDNotFound,_T("NANDNotFound ")},                       
	{SDMMCNotFound,_T("SDMMCNotFound  ")},                     
	{FlexOneNANDNotFound,_T("FlexOneNANDNotFound ")},                
	{SDMMCReadError,_T("SDMMCReadError  ")},                    
	{XIPReadError,_T("XIPReadError   ")},                     
	{FlexOneNANDError,_T("FlexOneNANDError ")},                   
	{FlashDriverInitError,_T("FlashDriverInitError")},                
	{FlashFuncNotDefined,_T("FlashFuncNotDefined")},			
	{OTPError,_T("OTPError")},				
	{InvalidAddressRangeError,_T("InvalidAddressRangeError")},		
	{FlashLockError,_T("FlashLockError	")},			
	{ReadDisturbError,_T("ReadDisturbError")},			
	{FlashReadError,_T("FlashReadError")},                      
	{SPIFlashNotResponding,_T("SPIFlashNotResponding")},			
	{ImageOverlayError,_T("ImageOverlayError ")},  
	{FlashAddrNotChunkAlign ,_T("FlashAddrNotChunkAlign")},
	{FlashAddrNotWordAlign  ,_T("FlashAddrNotWordAlign")},
	{BBTOUTOFRANGE	        ,_T("BBTOUTOFRANGE")},        
	{FlashWriteVerifyError  ,_T("FlashWriteVerifyError")},
	{FlashAddrOutOfRange  ,_T("FlashAddrOutOfRange")},
	{DFCDoubleBitError,_T("DFCDoubleBitError ")},   			
	{DFCSingleBitError,_T("DFCSingleBitError  ")},  			
	{DFCCS0BadBlockDetected,_T("DFCCS0BadBlockDetected  ")},		
	{DFCCS1BadBlockDetected,_T("DFCCS1BadBlockDetected ")}, 		
	{DFCInitFailed,_T("DFCInitFailed")},				
	{DFCONFIConfigError,_T("DFCONFIConfigError")},                  
	{DFC_WRREQ_TO,_T("DFC_WRREQ_TO")},				
	{DFC_WRCMD_TO,_T("DFC_WRCMD_TO")},				
	{DFC_RDDREQ_TO,_T("DFC_RDDREQ_TO")}	,			
	{DFC_RDY_TO,_T("DFC_RDY_TO	")},			
	{DFCCS0CommandDoneError,_T("DFCCS0CommandDoneError")},			
	{DFCCS1CommandDoneError,_T("DFCCS1CommandDoneError	")},		
	{DFC_PGDN_TO,_T("DFC_PGDN_TO")},
	{SPINORPROGRAMFAIL,_T("SPINORPROGRAMFAIL")},
	{SPINORERASEFAIL,_T("SPINORERASEFAIL")},
	{InvalidOEMVerifyKeyError,_T("InvalidOEMVerifyKeyError")},		
	{InvalidOBMImageError,_T("InvalidOBMImageError")},			
	{SecureBootFailureError,_T("SecureBootFailureError	")},		
	{InvalidSecureBootMethodError,_T("InvalidSecureBootMethodError")},		
	{UnsupportedFlashError,_T("UnsupportedFlashError")},			
	{InvalidCaddoFIFOEntryError,_T("InvalidCaddoFIFOEntryError ")},     	
	{InvalidCaddoKeyNumberError,_T("InvalidCaddoKeyNumberError	")},	
	{InvalidCaddoKeyTypeError,_T("InvalidCaddoKeyTypeError")},		
	{RSADigitalSignatureDecryptError,_T("RSADigitalSignatureDecryptError")}, 	
	{InvalidHashValueLengthError,_T("InvalidHashValueLengthError ")},    	
	{InvalidTIMImageError,_T("InvalidTIMImageError")},			
	{HashSizeMismatch,_T("HashSizeMismatch")},			
	{InvalidKeyHashError,_T("InvalidKeyHashError")},			
	{TIMNotFound,_T("TIMNotFound")},				
	{WTMStateError,_T("WTMStateError")},			
	{FuseRWError,_T("FuseRWError")},				
	{InvalidOTPHashError,_T("InvalidOTPHashError, keypair in current blf configuration is not the key of fuse")},			
	{CRCFailedError,_T("CRCFailedError	")},			
	{SaveStateNotFound,_T("SaveStateNotFound")},		
	{WTMInitializationError,_T("WTMInitializationError")},			
	{ImageNotFound,_T("ImageNotFound")},				
	{InvalidImageHash,_T("InvalidImageHash")},			
	{MicroCodePatchingError,_T("MicroCodePatchingError")},			
	{SetJtagKeyError,_T("SetJtagKeyError")},				
	{WTMDisabled,_T("WTMDisabled")},				
	{PlatformVerifyFailure,_T("PlatformVerifyFailure")},			
	{ImageLoadError,_T("ImageLoadError ")},                     
	{IPPCPHASHERROR,_T("IPPCPHASHERROR	")},						
	{DownloadPortError,_T("DownloadPortError")},			
	{DownloadError,_T("DownloadError")},				
	{FlashNotErasedError,_T("FlashNotErasedError")},			
	{InvalidKeyLengthError,_T("InvalidKeyLengthError")},			
	{DownloadImageTooBigError,_T("DownloadImageTooBigError")},		
	{UsbPreambleError,_T("UsbPreambleError")},			
	{TimeOutError,_T("TimeOutError")},				
	{UartReadWriteTimeOutError,_T("UartReadWriteTimeOutError")},		
	{UnknownImageError,_T("UnknownImageError")},			
	{MessageBufferFullError,_T("MessageBufferFullError")},			
	{NoEnumerationResponseTimeOutError,_T("NoEnumerationResponseTimeOutError")}, 	
	{UnknownProtocolCmd,_T("UnknownProtocolCmd")},		
	{UsbRxError,_T("UsbRxError")},                          
	{ForceDownloadPseudoError,_T("ForceDownloadPseudoError")},		
	{UsbTxError,_T("UsbTxError")},                          
	{JtagReEnableError,_T("JtagReEnableError")}	,		
	{JtagReEnableOEMPubKeyError,_T("JtagReEnableOEMPubKeyError")},		
	{JtagReEnableOEMSignedPassWdError,_T("JtagReEnableOEMSignedPassWdError")},	
	{JtagReEnableTimeOutError,_T("JtagReEnableTimeOutError")},		
	{JtagReEnableOEMKeyLengthError,_T("JtagReEnableOEMKeyLengthError  ")} ,			
	{SDMMC_SWITCH_ERROR,_T("SDMMC_SWITCH_ERROR")},	 		
	{SDMMC_ERASE_RESET_ERROR,_T("SDMMC_ERASE_RESET_ERROR")},	 		
	{SDMMC_CIDCSD_OVERWRITE_ERROR,_T("SDMMC_CIDCSD_OVERWRITE_ERROR")},		
	{SDMMC_OVERRUN_ERROR,_T("SDMMC_OVERRUN_ERROR ")},			
	{SDMMC_UNDERUN_ERROR,_T("SDMMC_UNDERUN_ERROR ")},			
	{SDMMC_GENERAL_ERROR,_T("SDMMC_GENERAL_ERROR ")},			
	{SDMMC_CC_ERROR,_T("SDMMC_CC_ERROR")}, 				
	{SDMMC_ECC_ERROR,_T("SDMMC_ECC_ERROR")}, 			
	{SDMMC_ILL_CMD_ERROR,_T("SDMMC_ILL_CMD_ERROR")},      			
	{SDMMC_COM_CRC_ERROR,_T("SDMMC_COM_CRC_ERROR")},			
	{SDMMC_LOCK_ULOCK_ERRROR,_T("SDMMC_LOCK_ULOCK_ERRROR")},			
	{SDMMC_LOCK_ERROR,_T("SDMMC_LOCK_ERROR ")},			
	{SDMMC_WP_ERROR,_T("SDMMC_WP_ERROR")}, 				
	{SDMMC_ERASE_PARAM_ERROR,_T("SDMMC_ERASE_PARAM_ERROR")},			
	{SDMMC_ERASE_SEQ_ERROR,_T("SDMMC_ERASE_SEQ_ERROR")},			
	{SDMMC_BLK_LEN_ERROR,_T("SDMMC_BLK_LEN_ERROR")}, 			
	{SDMMC_ADDR_MISALIGN_ERROR,_T("SDMMC_ADDR_MISALIGN_ERROR")}, 		
	{SDMMC_ADDR_RANGE_ERROR,_T("SDMMC_ADDR_RANGE_ERROR")}, 			
	{SDMMCDeviceNotReadyError,_T("SDMMCDeviceNotReadyError")},		
	{SDMMCInitializationError,_T("SDMMCInitializationError")},		
	{SDMMCDeviceVoltageNotSupported,_T("SDMMCDeviceVoltageNotSupported")},		
	{SDMMCWriteError,_T("SDMMCWriteError")},
	{SDMMCAltBootDataAlignmentError,_T("SDMMCAltBootDataAlignmentError")},
	{SDMMC_SGPT_ILLEGAL_LENGTH,_T("SDMMC_SGPT_ILLEGAL_LENGTH")},
	{SDIOReadError,_T("SDIOReadError")},		
	{SDIOWriteError,_T("SDIOWriteError")},             
	{SDIOOutOfSyncError,_T("SDIOOutOfSyncError")},             
	{SDIONullBuffer,_T("SDIONullBuffer")},             
	{SDIOBufferMisalignError,_T("SDIOBufferMisalignError")},             
	{SDIOImageSizeError,_T("SDIOImageSizeError")},   
	{FUSE_FuseBlockNotActive,_T("FUSE_FuseBlockNotActive")},              
	{FUSE_BufferTooSmall,_T("FUSE_BufferTooSmall")},                  
	{FUSE_FuseBlockLocked,_T("FUSE_FuseBlockLocked ")},                
	{FUSE_UnsupportedFuseBlock,_T("FUSE_UnsupportedFuseBlock")},            
	{FUSE_IncompleteBurnRequest,_T("FUSE_IncompleteBurnRequest")},           
	{FUSE_NoBurnRequest,_T("FUSE_NoBurnRequest")},                   
	{FUSE_FuseBlockFieldNotActive,_T("FUSE_FuseBlockFieldNotActive")},         
	{FUSE_BurnError,_T("FUSE_BurnError")},                       
	{FUSE_FuseBlockFieldOverflow,_T("FUSE_FuseBlockFieldOverflow")},          
	{FUSE_InvalidFuseBlockField,_T("FUSE_InvalidFuseBlockField")},           
	{FUSE_FuseBlockCompareFailed,_T("FUSE_FuseBlockCompareFailed")},          
	{FUSE_InvalidState,_T("FUSE_InvalidState")},                    
	{FUSE_InvalidBufferSize,_T("FUSE_InvalidBufferSize")},               
	{FUSE_BitSetError,_T("FUSE_BitSetError")},                     
	{FUSE_FuseBlockLockedAndNotReadable,_T("FUSE_FuseBlockLockedAndNotReadable")},   
	{FUSE_FuseBlockFieldFull,_T("FUSE_FuseBlockFieldFull")},              
	{FUSE_FuseSoftwareResetTimeout,_T("FUSE_FuseSoftwareResetTimeout")},        
	{FUSE_FuseBurnTimeout,_T("FUSE_FuseBurnTimeout")},                 
	{FUSE_FuseBlockStickyBitSet,_T("FUSE_FuseBlockStickyBitSet")},           
	{FUSE_UsbPhyBandgapNotEnabled,_T("FUSE_UsbPhyBandgapNotEnabled")},         
	{FUSE_UncorrectableEccError,_T("FUSE_UncorrectableEccError")},		
	{FUSE_FieldWriteProtectedByEcc,_T("FUSE_FieldWriteProtectedByEcc")},		
	{FUSE_LastLogicalBitBurned,_T("FUSE_LastLogicalBitBurned")},            
	{FUSE_TamperError,_T("FUSE_TamperError")},		     
	{FUSE_FuseReprogrammingError,_T("FUSE_FuseReprogrammingError")},          
	{FUSE_IncompleteFuseFieldsSetup,_T("FUSE_IncompleteFuseFieldsSetup")},       
	{GEU_FuseBlockNotActive,_T("GEU_FuseBlockNotActive")},               
	{GEU_BufferTooSmall,_T("GEU_BufferTooSmall")},                   
	{GEU_FuseBlockLocked,_T("GEU_FuseBlockLocked")},                  
	{GEU_UnsupportedFuseBlock,_T("GEU_UnsupportedFuseBlock ")},            
	{GEU_IncompleteBurnRequest,_T("GEU_IncompleteBurnRequest ")},           
	{GEU_NoBurnRequest,_T("GEU_NoBurnRequest")},                    
	{GEU_FuseBlockFieldNotActive,_T("GEU_FuseBlockFieldNotActive")},          
	{GEU_BurnError,_T("GEU_BurnError")},                        
	{GEU_FuseBlockFieldOverflow,_T("GEU_FuseBlockFieldOverflow")},           
	{GEU_InvalidFuseBlockField,_T("GEU_InvalidFuseBlockField")},            
	{GEU_FuseBlockCompareFailed,_T("GEU_FuseBlockCompareFailed")},           
	{GEU_InvalidState,_T("GEU_InvalidState")},                     
	{GEU_InvalidBufferSize,_T("GEU_InvalidBufferSize")},                
	{GEU_BitSetError,_T("GEU_BitSetError")},                      
	{GEU_FuseBlockLockedAndNotReadable,_T("GEU_FuseBlockLockedAndNotReadable")},    
	{GEU_FuseBlockFieldFull,_T("GEU_FuseBlockFieldFull")},               
	{GEU_FuseSoftwareResetTimeout,_T("GEU_FuseSoftwareResetTimeout")},         
	{GEU_FuseBurnTimeout,_T("GEU_FuseBurnTimeout")},                  
	{GEU_FuseBlockStickyBitSet,_T("GEU_FuseBlockStickyBitSet")},            
	{GEU_UsbPhyBandgapNotEnabled,_T("GEU_UsbPhyBandgapNotEnabled")},          
	{GEU_UncorrectableEccError,_T("GEU_UncorrectableEccError")},		
	{GEU_FieldWriteProtectedByEcc,_T("GEU_FieldWriteProtectedByEcc")},	     
	{GEU_LastLogicalBitBurned,_T("GEU_LastLogicalBitBurned")},             
	{GEU_TamperError,_T("GEU_TamperError")},		             
	{GEU_FuseReprogrammingError,_T("GEU_FuseReprogrammingError")},           
	{GEU_IncompleteFuseFieldsSetup,_T("GEU_IncompleteFuseFieldsSetup")},        
	{TZ_Region0NotProtected,_T("TZ_Region0NotProtected")},	
	{TZ_FusesNotConfiguredForTrustzone,_T("TZ_FusesNotConfiguredForTrustzone")},
	{TZ_PackageNotFound		  ,_T("TZ_PackageNotFound")},               
	{TZ_InitDisabled		  ,_T("TZ_InitDisabled")},                  
	{TZ_UnknownOperation		  ,_T("TZ_UnknownOperation")},              
	{DDR_Package_Obsolete,_T("DDR_Package_Obsolete")},			
	{DDR_Unknown_Operation,_T("DDR_Unknown_Operation")},                
	{DDR_MemoryTest_Failed,_T("DDR_MemoryTest_Failed")},                
	{DDR_InitDisabled,_T("DDR_InitDisabled")},                     
	{DDR_CMCC_Package_Obsolete,_T("DDR_CMCC_Package_Obsolete")},		
	{DDR_Trustzone_Package_Obsolete,_T("DDR_Trustzone_Package_Obsolete")},	   	
	{DDR_PackageNotFound,_T("DDR_PackageNotFound")},			
	{DDR_FusesNotConfiguredForTrustzone,_T("DDR_FusesNotConfiguredForTrustzone")},   
	{UnknownInstruction,_T("UnknownInstruction	")},		
	{InstructionTimeout,_T("InstructionTimeout")}, 
	{INSTR_InvalidAddress,_T("INSTR_InvalidAddress")},	                               
	{INSTR_InvalidScratchMemoryId,_T("INSTR_InvalidScratchMemoryId")},	               
	{INSTR_InvalidMaskOrValue,_T("INSTR_InvalidMaskOrValue")},	                       
	{Sparse_ImageLengthLimitExceeded,_T("Sparse_ImageLengthLimitExceeded")},		
	{Sparse_BadMagic,_T("Sparse_BadMagic")},				
	{Sparse_IncompatibleFormat,_T("Sparse_IncompatibleFormat")},		
	{Sparse_BadChunkSize,_T("Sparse_BadChunkSize")},			
	{Sparse_BogusDontCareChunk,_T("Sparse_BogusDontCareChunk")},		
	{Sparse_UnknownChunkId,_T("Sparse_UnknownChunkId")},			
	{Sparse_WriteError,_T("Sparse_WriteError")},
	{SDH_CMD_TIMEOUT_ERR,_T("SDH_CMD_TIMEOUT_ERR")},
	{SDH_CMD_CRC_ERR,_T("SDH_CMD_CRC_ERR")},	
	{SDH_CMD_END_BIT_ERR,_T("SDH_CMD_END_BIT_ERR")},
	{SDH_CMD_INDEX_ERR,_T("SDH_CMD_INDEX_ERR")},
	{SDH_DATA_TIMEOUT_ERR,_T("SDH_DATA_TIMEOUT_ERR")},
	{SDH_RD_DATA_CRC_ERR,_T("SDH_RD_DATA_CRC_ERR")},
	{SDH_RD_DATA_END_BIT_ERR,_T("SDH_RD_DATA_END_BIT_ERR")},	
	{SDH_AUTO_CMD12_ERR	,_T("SDH_AUTO_CMD12_ERR")},
	{SDH_ADMA_ERR,_T("SDH_ADMA_ERR")},
	{SDH_TUNE_ERR,_T("SDH_TUNE_ERR")},
	{SDH_SPI_ERR,_T("SDH_SPI_ERR")},
	{SDH_AXI_RESP_ERR,_T("SDH_AXI_RESP_ERR")},
	{SDH_CPL_TIMEOUT_ERR,_T("SDH_CPL_TIMEOUT_ERR")},
	{SDH_CRC_STATUS_ERR,_T("SDH_CRC_STATUS_ERR")},  
	{IMAP_PackageNotFound,_T("IMAP_PackageNotFound")},
	{IMAP_ErrorFormat,_T("IMAP_ErrorFormat")},
	{IMAP_DTIMNotFound,_T("IMAP_DTIMNotFound")},
	{IMAP_DTIMLoadError,_T("IMAP_DTIMLoadError")},
	{IMAP_DTIMValidationFailed,_T("IMAP_DTIMValidationFailed")},
	{IMAP_BootFailed,_T("IMAP_BootFailed")},
	{IMAP_KeyNotFound,_T("IMAP_KeyNotFound")},
	{IMAP_ImageLoadError,_T("IMAP_ImageLoadError")},
	{IMAP_ImageValidateError,_T("IMAP_ImageValidateError")},
	{MRD_BadMagic,_T("MRD_BadMagic")},
	{MRD_CheckSumNotMatch,_T("MRD_CheckSumNotMatch")},
	{MRD_IMEINotMatch,_T("MRD_IMEINotMatch")},

};


static NOTIFICATIONTABLE WTPTPNotificationMsg[MAXNOTIFICATIONSCODES] =
{
	{PlatformBusy,_T("Platform is busy")},
	{PlatformReady,_T("Platform is Ready")},
	{PlatformResetBBT,_T("Reset BBT")},
	{PlatformEraseAllFlash,_T("Erase All flash begin")},
	{PlatformDisconnect,_T("platform is disconnect")},
	{PlatformEraseAllFlashDone,_T("Erase All flash done")},
	{PlatformEraseAllFlashWithoutBurn,_T("Erase All flash without burning begin")},
	{PlatformEraseAllFlashWithoutBurnDone,_T("Erase All flash without burning Done")},
	{PlatformFuseOperationStart,_T("Platform Fuse Operation Start")},
	{PlatformFuseOperationDone,_T("Platform Fuse Operation Done")},
	{PlatformUEInfoStart,_T("Platform UE Info Operation Start")},
	{PlatformUEInfoDone,_T("Platform UE Info Operation Done")}
};
#else
static ERRORCODETABLE WTPTPErrorCodes[MAXERRORCODES]=
{
	{NoError},            		  			
	{NotFoundError},      					
	{GeneralError},       					
	{WriteError},         					
	{ReadError}	,	   				
	{NotSupportedError} , 					
	{InvalidPlatformConfigError},		
	{InvalidPlatformState},				
	{InvalidSizeError},				
	{ProbeListExhaustError},				
	{DDR_NotInitializedError},				
	{UnknownReservedPackage},				
	{NULLPointer},
	{NANDIDDISMATCH	},             
	{FBF_VersionNotMatch},    
	{FBF_DeviceMoreThanOne},
	{PlatformConfigBuckError},
	{ChipIdMismatch},
	{EraseError},	 			
	{ProgramError},					
	{InvalidBootTypeError},				
	{ProtectionRegProgramError},			
	{NoOTPFound},					
	{BBTReadError},						
	{MDOCInitFailed},					
	{OneNandInitFailed},               
	{MDOCFormatFailed},                   
	{BBTExhaustedError},                  
	{NANDNotFound},                       
	{SDMMCNotFound},                     
	{FlexOneNANDNotFound},                
	{SDMMCReadError},                    
	{XIPReadError},                     
	{FlexOneNANDError},                   
	{FlashDriverInitError},                
	{FlashFuncNotDefined},			
	{OTPError},				
	{InvalidAddressRangeError},		
	{FlashLockError},			
	{ReadDisturbError},			
	{FlashReadError},                      
	{SPIFlashNotResponding},			
	{ImageOverlayError},  
	{FlashAddrNotChunkAlign },
	{FlashAddrNotWordAlign  },
	{BBTOUTOFRANGE	        },        
	{FlashWriteVerifyError  },
	{FlashAddrOutOfRange  },
	{DFCDoubleBitError},   			
	{DFCSingleBitError},  			
	{DFCCS0BadBlockDetected},		
	{DFCCS1BadBlockDetected}, 		
	{DFCInitFailed},				
	{DFCONFIConfigError},                  
	{DFC_WRREQ_TO},				
	{DFC_WRCMD_TO},				
	{DFC_RDDREQ_TO}	,			
	{DFC_RDY_TO},			
	{DFCCS0CommandDoneError},			
	{DFCCS1CommandDoneError},		
	{DFC_PGDN_TO},
	{SPINORPROGRAMFAIL},
	{SPINORERASEFAIL},
	{InvalidOEMVerifyKeyError},		
	{InvalidOBMImageError},			
	{SecureBootFailureError},		
	{InvalidSecureBootMethodError},		
	{UnsupportedFlashError},			
	{InvalidCaddoFIFOEntryError},     	
	{InvalidCaddoKeyNumberError},	
	{InvalidCaddoKeyTypeError},		
	{RSADigitalSignatureDecryptError}, 	
	{InvalidHashValueLengthError},    	
	{InvalidTIMImageError},			
	{HashSizeMismatch},			
	{InvalidKeyHashError},			
	{TIMNotFound},				
	{WTMStateError},			
	{FuseRWError},				
	{InvalidOTPHashError},			
	{CRCFailedError},			
	{SaveStateNotFound},		
	{WTMInitializationError},			
	{ImageNotFound},				
	{InvalidImageHash},			
	{MicroCodePatchingError},			
	{SetJtagKeyError},				
	{WTMDisabled},				
	{PlatformVerifyFailure},			
	{ImageLoadError},                     
	{IPPCPHASHERROR},						
	{DownloadPortError},			
	{DownloadError},				
	{FlashNotErasedError},			
	{InvalidKeyLengthError},			
	{DownloadImageTooBigError},		
	{UsbPreambleError},			
	{TimeOutError},				
	{UartReadWriteTimeOutError},		
	{UnknownImageError},			
	{MessageBufferFullError},			
	{NoEnumerationResponseTimeOutError}, 	
	{UnknownProtocolCmd},		
	{UsbRxError},                          
	{ForceDownloadPseudoError},		
	{UsbTxError},                          
	{JtagReEnableError}	,		
	{JtagReEnableOEMPubKeyError},		
	{JtagReEnableOEMSignedPassWdError},	
	{JtagReEnableTimeOutError},		
	{JtagReEnableOEMKeyLengthError} ,			
	{SDMMC_SWITCH_ERROR},	 		
	{SDMMC_ERASE_RESET_ERROR},	 		
	{SDMMC_CIDCSD_OVERWRITE_ERROR},		
	{SDMMC_OVERRUN_ERROR},			
	{SDMMC_UNDERUN_ERROR},			
	{SDMMC_GENERAL_ERROR},			
	{SDMMC_CC_ERROR}, 				
	{SDMMC_ECC_ERROR}, 			
	{SDMMC_ILL_CMD_ERROR},      			
	{SDMMC_COM_CRC_ERROR},			
	{SDMMC_LOCK_ULOCK_ERRROR},			
	{SDMMC_LOCK_ERROR},			
	{SDMMC_WP_ERROR}, 				
	{SDMMC_ERASE_PARAM_ERROR},			
	{SDMMC_ERASE_SEQ_ERROR},			
	{SDMMC_BLK_LEN_ERROR}, 			
	{SDMMC_ADDR_MISALIGN_ERROR}, 		
	{SDMMC_ADDR_RANGE_ERROR}, 			
	{SDMMCDeviceNotReadyError},		
	{SDMMCInitializationError},		
	{SDMMCDeviceVoltageNotSupported},		
	{SDMMCWriteError},
	{SDMMCAltBootDataAlignmentError},
	{SDMMC_SGPT_ILLEGAL_LENGTH},
	{SDIOReadError},		
	{SDIOWriteError},             
	{SDIOOutOfSyncError},             
	{SDIONullBuffer},             
	{SDIOBufferMisalignError},             
	{SDIOImageSizeError},   
	{FUSE_FuseBlockNotActive},              
	{FUSE_BufferTooSmall},                  
	{FUSE_FuseBlockLocked},                
	{FUSE_UnsupportedFuseBlock},            
	{FUSE_IncompleteBurnRequest},           
	{FUSE_NoBurnRequest},                   
	{FUSE_FuseBlockFieldNotActive},         
	{FUSE_BurnError},                       
	{FUSE_FuseBlockFieldOverflow},          
	{FUSE_InvalidFuseBlockField},           
	{FUSE_FuseBlockCompareFailed},          
	{FUSE_InvalidState},                    
	{FUSE_InvalidBufferSize},               
	{FUSE_BitSetError},                     
	{FUSE_FuseBlockLockedAndNotReadable},   
	{FUSE_FuseBlockFieldFull},              
	{FUSE_FuseSoftwareResetTimeout},        
	{FUSE_FuseBurnTimeout},                 
	{FUSE_FuseBlockStickyBitSet},           
	{FUSE_UsbPhyBandgapNotEnabled},         
	{FUSE_UncorrectableEccError},		
	{FUSE_FieldWriteProtectedByEcc},		
	{FUSE_LastLogicalBitBurned},            
	{FUSE_TamperError},		     
	{FUSE_FuseReprogrammingError},          
	{FUSE_IncompleteFuseFieldsSetup},       
	{GEU_FuseBlockNotActive},               
	{GEU_BufferTooSmall},                   
	{GEU_FuseBlockLocked},                  
	{GEU_UnsupportedFuseBlock},            
	{GEU_IncompleteBurnRequest},           
	{GEU_NoBurnRequest},                    
	{GEU_FuseBlockFieldNotActive},          
	{GEU_BurnError},                        
	{GEU_FuseBlockFieldOverflow},           
	{GEU_InvalidFuseBlockField},            
	{GEU_FuseBlockCompareFailed},           
	{GEU_InvalidState},                     
	{GEU_InvalidBufferSize},                
	{GEU_BitSetError},                      
	{GEU_FuseBlockLockedAndNotReadable},    
	{GEU_FuseBlockFieldFull},               
	{GEU_FuseSoftwareResetTimeout},         
	{GEU_FuseBurnTimeout},                  
	{GEU_FuseBlockStickyBitSet},            
	{GEU_UsbPhyBandgapNotEnabled},          
	{GEU_UncorrectableEccError},		
	{GEU_FieldWriteProtectedByEcc},	     
	{GEU_LastLogicalBitBurned},             
	{GEU_TamperError},		             
	{GEU_FuseReprogrammingError},           
	{GEU_IncompleteFuseFieldsSetup},        
	{TZ_Region0NotProtected},	
	{TZ_FusesNotConfiguredForTrustzone},
	{TZ_PackageNotFound		  },               
	{TZ_InitDisabled		  },                  
	{TZ_UnknownOperation		  },              
	{DDR_Package_Obsolete},			
	{DDR_Unknown_Operation},                
	{DDR_MemoryTest_Failed},                
	{DDR_InitDisabled},                     
	{DDR_CMCC_Package_Obsolete},		
	{DDR_Trustzone_Package_Obsolete},	   	
	{DDR_PackageNotFound},			
	{DDR_FusesNotConfiguredForTrustzone},   
	{UnknownInstruction},		
	{InstructionTimeout}, 
	{INSTR_InvalidAddress},	                               
	{INSTR_InvalidScratchMemoryId},	               
	{INSTR_InvalidMaskOrValue},	                       
	{Sparse_ImageLengthLimitExceeded},		
	{Sparse_BadMagic},				
	{Sparse_IncompatibleFormat},		
	{Sparse_BadChunkSize},			
	{Sparse_BogusDontCareChunk},		
	{Sparse_UnknownChunkId},			
	{Sparse_WriteError},
	{SDH_CMD_TIMEOUT_ERR},
	{SDH_CMD_CRC_ERR},	
	{SDH_CMD_END_BIT_ERR},
	{SDH_CMD_INDEX_ERR},
	{SDH_DATA_TIMEOUT_ERR},
	{SDH_RD_DATA_CRC_ERR},
	{SDH_RD_DATA_END_BIT_ERR},	
	{SDH_AUTO_CMD12_ERR	},
	{SDH_ADMA_ERR},
	{SDH_TUNE_ERR},
	{SDH_SPI_ERR},
	{SDH_AXI_RESP_ERR},
	{SDH_CPL_TIMEOUT_ERR},
	{SDH_CRC_STATUS_ERR},  
	{IMAP_PackageNotFound},
	{IMAP_ErrorFormat},
	{IMAP_DTIMNotFound},
	{IMAP_DTIMLoadError},
	{IMAP_DTIMValidationFailed},
	{IMAP_BootFailed},
	{IMAP_KeyNotFound},
	{IMAP_ImageLoadError},
	{IMAP_ImageValidateError},
	{MRD_BadMagic},
	{MRD_CheckSumNotMatch},
	{MRD_IMEINotMatch}

};


static NOTIFICATIONTABLE WTPTPNotificationMsg[MAXNOTIFICATIONSCODES] =
{
	{PlatformBusy},
	{PlatformReady},
	{PlatformResetBBT},
	{PlatformEraseAllFlash},
	{PlatformDisconnect},
	{PlatformEraseAllFlashDone},
	{PlatformEraseAllFlashWithoutBurn},
	{PlatformEraseAllFlashWithoutBurnDone},
	{PlatformFuseOperationStart},
	{PlatformFuseOperationDone},
	{PlatformUEInfoStart},
	{PlatformUEInfoDone}
};

#endif

void Copy_NotifyStatus(PProcInfo me,struct _NotifyStatus* rhs);
void New_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC me);
void Del_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC me);
void Copy_DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC(pDDR_FLASH_DOWNLOADIMAGE_INFO_SPEC me,struct _DDR_FLASH_DOWNLOADIMAGE_INFO_SPEC* DDRFlashDownloadImageInfo);
void Copy_WTPTPREAMBLECOMMAND(pWTPTPREAMBLECOMMAND me,struct _WTPTPREAMBLECOMMAND* WTPCMD);
void DelInstanceParams(PInstanceParams me);
void NewInstanceParams(PInstanceParams me);

#endif
