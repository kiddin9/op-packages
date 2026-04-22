#ifndef __TIM_H__
#define __TIM_H__

//#include "general.h"
#include "Macrodef.h"
#include "TimIncludedType.h"
/******************* TIM Layout ************************************/
/* Below Presents the Maxiumum Size TIM layout in memory

VERSION_I      	VersionBind;         			// 0
FLASH_I        	FlashInfo;           			// 0x10
UINT_T         	NumImages;           			// 0x20
UINT_T         	NumKeys;						// 0x24
UINT_T         	SizeOfReserved;					// 0x28
IMAGE_INFO 		IMG[MAX_IMAGES];                // 0x2C
KEY_MOD        	Key[MAX_KEYS];                  // 0x284
UINT_T         	Reserved[0x4E8];       			// 0x908  (0x4E8 bytes)
PLAT_DS        	TBTIM_DS;                       // 0xDF0
												// 0x1000 = 4 KB
Below Presents the Maxiumum Size NTIM layout in memory

VERSION_I   	VersionBind;         			// 0
FLASH_I     	FlashInfo;           			// 0x10
UINT_T      	NumImages;           			// 0x20
UINT_T         	NumKeys;						// 0x24
UINT_T      	SizeOfReserved;					// 0x28
IMAGE_INFO 		IMG[MAX_IMAGES];                // 0x2C
UINT_T      	Reserved[0xD80];       			// 0x284
NTIM, *pNTIM;									// 0x1000 = 4KB
/******************* TIM Layout ************************************/


// TIM Versions
#define TIM_3_1_01			0x30101			
#define TIM_3_2_00			0x30200			// Support for Partitioning
#define TIM_3_3_00			0x30300			// Support for ECDSA-256 and 64 bit addressing
#define TIM_3_4_00			0x30400			// Support for ECDSA-521
#define TIM_3_5_00			0x30500			// Support for Encrypted Boot

const int MAX_HASH = 256;
const int MAX_HASH_IN_BITS = 512;	// 512 bits

// B1 TIM
#include "Typedef.h"
#define MAX_IMAGES			100
#define MAX_KEYS	 		3
#define MAX_TIM_SIZE 		0x1000
#define TIMBUFFER 			4096    		//4k for a Tim structure size
#define MAXKEYSIZEWORDS		64				// 2048 bits
#define MAXRSAKEYSIZEWORDS	 64				// 2048 bits
#define MAXECCKEYSIZEWORDS 17				// 521 bits+

// Predefined Image Identifiers
#define TIMIDENTIFIER		0x54494D48		// "TIMH"
#define TIM1IDENTIFIER		0x54494D31		// "TIM1"
#define TIM4IDENTIFIER		0x54494D34		// "TIM4"
#define WTMIDENTIFIER		0x57544D49		// "WTMI"
#define OBMIDENTIFIER		0x4F424D49		// "OBMI"
#define MONITORIDENTIFIER	0x4D4F4E49		// "MONI"
#define TZSWIDENTIFIER		0x545A5349		// "TZSI"    This is also used as consumer ID	
#define TBRIDENTIFIER		0x54425249		// "TBRI"	 This is also used as consumer ID	
#define DKBIDENTIFIER		0x444B4249		// "DKBI"
#define JTAGIDENTIFIER		0x4A544147		// "JTAG"
#define AUTHIDENTIFIER		0x41555448		// "AUTH"
#define PATCHIDENTIFIER		0x50415443		// "PATC"
#define TCAIDENTIFIER		0x5443414B		// "TCAK"
#define OSLOADERID			0x4F534C4F		// "OSLO"
#define ROMC                0x524F4D43      // "ROMC"
#define DSIGIDENTIFIER      0x44534947      // "DSIG"
#define ENCKIDENTIFIER      0x454E434B      // "ENCK"

// WTP Format Recognized Reserved Area Indicator
#define WTPRESERVEDAREAID	0x4F505448      // "OPTH"

// Reserved Area Package Headers
#define AUTOBIND			0x42494E44		// "BIND"
#define TERMINATORID		0x5465726D		// "Term"
#define GPIOID				0x4750494F		// "GPIO"
#define UARTID				0x55415254		// "UART"
#define USBID				0x00555342		// "USB"
#define RESUMEID			0x5265736D		// "Resm"
#define USBVENDORREQ		0x56524551		// "VREQ"
#define TBR_XFER			0x54425258		// "TBRX"
#define RESUMEBLID          0x52736D32      // "Rsm2"
#define ESCAPESEQID			0x45534353		// "ESCS"
#define ESCSEQID_v2			0x45537632		// "ESv2"	Escape Sequence Version 2
#define OEMCUSTOMID			0x43555354		// "CUST"
#define NOMONITORID			0x4E4F4D43		// "NOMC"
#define COREID				0x434F5245		// "CORE"
#define BBMTID              0x42424D54      // "BBMT"
#define QNXBOOT             0x514E5850      // "QNXP"
#define GPP1ID				0x47505031		// "GPP1"  Processed in RESERVEDAREA_State
#define GPP2ID				0x47505032		// "GPP2"  Processed in XFER_State
#define ROMRESUMEID			0x52736D33		// "Rsm3"
#define PINID               0x50494E50      // "PINP"
#define IMAPID              0x494D4150      // "IMAP"


// DDR Related ID's
#define DDRID				0x44447248		// "DDrH"
#define DDRGID				0x44445247		// "DDRG"
#define DDRTID				0x44445254		// "DDRT"
#define DDRCID				0x44445243		// "DDRC"
#define CMCCID				0x434d4343		// "CMCC"

// trust zone package
#define CIDPID              0x43494450      // "CIDP"
#define TZRI	            0x545A5249	    // ”TZRI?#endif

// Operating mode related ID's
#define FREQID				0x46524551		// "FREQ"
#define VOLTID				0x564f4c54		// "VOLT"
#define OPMODEID			0x4d4f4445		// "MODE"
#define OPDIVID 			0x4f504456		// "OPDV"
#define CLKEID				0x434c4b45		// "CLKE"

// trust zone package
#define TZID				0x545A4944      // "TZID"
#define TZON                0x545A4f4E      // "TZON" Register based

#define FUNC	            0x46554E43      // "FUNC"
#define PROI	            0x50524F49      // "PROI"

#define ERASID              0x45524153      //ERAS
#define SKIPID              0x534B4950      //SKIP
// USB
#define DESCRIPTOR_RES_ID	0x55534200      // "USB"
#define NUM_USB_DESCRIPTORS			10
#define MAX_USB_STRINGS 			7

#define NOFREQUENCYID		0x4E4F4643		// "NOFC"
#define NOKEYDETECTID		0x4E4F4B44		// "NOKD"

#define TRFU				0x54524655      //TR069 control info.
#define DTYP				0x44545950      //DDR type
#define LTWS				0x4C545753      //LTG LWG SELECT PACKAGE
#define OTAI				0x4F544149      //FOTA Info
#define DDR_FLASH_MCP_MAP_PACKAGE_ID  0X44464D50 // "DFMP"
#define CITA_CUMIZED_INFO_TRANSFER_TOAP_ID  0X43495441 // "CITA"
#define BBMTYPEID			0x42424D54		// "BBMT"
#define FLASH_GEO_PKG_ID       0x46475049      // "FGPI"  Flash Geometry Package ID
#define BBCS				0x42424353		//Bad block report switch
#define CRCS				0x43524353		//CRC switch


/***************************************************************************
*
*             New package for DDR auto adjust -- start
*
****************************************************************************/

#define		  DDRBYTESELECT         0x44444253         // "DDBS", ddr byte select
#define       DDR_SAMSUNG_ID        0x49443031         // "ID01"
#define       DDR_QIMONDA_ID        0x49443032         // "ID02"
#define       DDR_ELPIDA_ID         0x49443033         // "ID03"
#define       DDR_ETRON_ID          0x49443034         // "ID04"
#define       DDR_NANYA_ID          0x49443035         // "ID05"
#define       DDR_HYNIX_ID          0x49443036         // "ID06"
#define       DDR_MOSEL_ID          0x49443037         // "ID07"
#define       DDR_WINBOND_ID        0x49443038         // "ID08"
#define       DDR_ESMT_ID           0x49443039         // "ID09"
#define       DDR_RESERVED_ID       0x49443041         // "ID0A"
#define       DDR_SPANSION_ID       0x49443042         // "ID0B"
#define       DDR_SST_ID            0x49443043         // "ID0C"
#define       DDR_ZMOS_ID           0x49443044         // "ID0D"
#define       DDR_INTEL_ID          0x49443045         // "ID0E"
#define       DDR_NUMONYX_ID        0x49443046         // "ID0F"
#define       DDR_MICRON_ID         0x49443130         // "ID10"
#define       DDR_TOSHIBA_ID        0x49443131         // "ID11"


typedef enum
{
 eUSB_DEVICE_DESCRIPTOR   				= (DESCRIPTOR_RES_ID | 0),
 eUSB_CONFIG_DESCRIPTOR   				= (DESCRIPTOR_RES_ID | 1),
 eUSB_INTERFACE_DESCRIPTOR 				= (DESCRIPTOR_RES_ID | 2),
 eUSB_LANGUAGE_STRING_DESCRIPTOR   		= (DESCRIPTOR_RES_ID | 3),
 eUSB_MANUFACTURER_STRING_DESCRIPTOR   	= (DESCRIPTOR_RES_ID | 4),
 eUSB_PRODUCT_STRING_DESCRIPTOR   	  	= (DESCRIPTOR_RES_ID | 5),
 eUSB_SERIAL_STRING_DESCRIPTOR   	  	= (DESCRIPTOR_RES_ID | 6),
 eUSB_INTERFACE_STRING_DESCRIPTOR   		= (DESCRIPTOR_RES_ID | 7),
 eUSB_DEFAULT_STRING_DESCRIPTOR			= (DESCRIPTOR_RES_ID | 8),
 eUSB_ENDPOINT_DESCRIPTOR 				= (DESCRIPTOR_RES_ID | 9)
} USB_DESCRIPTORS;

typedef enum
{
      COREID_MP1 = 0,
      COREID_MP2 = 1, 
      COREID_MM  = 2
}
COREID_T;

typedef enum
{
      BBMT_TYPE_NO_BBM = 0,
      BBMT_TYPE_LEGACY = 1, 
      BBMT_TYPE_MARVELL_FM_V1 = 2,
      BBMT_TYPE_MARVELL_FM_V2 = 3
}
BBMT_TYPE_T;
// Global Identifiers
#define FFIDENTIFIER		0x00004646		// "FF"
#define ALTIDENTIFIER		0x00414C54		// "ALT"
#define DIFFIDENTIFIER		0x44696666		// "Diff"
#define SEIDENTIFIER		0x00005345		// "SE"
#define U2DIDENTIFIER		0x55534232		// "USB2"
#define PINSIDENTIFIER		0x50696E73		// "Pins"
#define MDOCFORMATID        0x6d444f43      // "mDOC"
#define MDOCBINID           0x6d42944E      // "mBIN"
#define MDOCBDTLID          0x6d424454	    // "mBDT"
#define CI2IDENTIFIER       0x00434932     // "CI2"
#define OTGIDENTIFIER		0x554F5447		// "UOTG"
#define INVALIDID           0x21212121      // "!!!!" Should never appear in actual TIM file
#define PARTIONIDENTIFIER	0x50415254      // "PART"
// identifier for common tools Marvell Format image file
#define FBFIDENTIFIER       0x46424649      // "FBFI" Should never appear in actual TIM file


// Miscellanous
#define BINDKEYSIZE			128				// (MAXKEYSIZEWORDS * 2)
#define FLASHSIGMASK		0x0000000F		// mask off the 4 bits of platform state




typedef enum INSTRUCTION_OP_CODE_SPEC_E
{ 
    // Enums specify the following:
    INSTR_NOP = 0, 
    INSTR_WRITE = 1,          
    INSTR_READ  = 2 ,       	
    INSTR_DELAY = 3,
    INSTR_WAIT_FOR_BIT_SET = 4,
    INSTR_WAIT_FOR_BIT_CLEAR = 5,
    INSTR_AND_VAL = 6,
    INSTR_OR_VAL = 7,
    // new DDR Script instructions
    INSTR_SET_BITFIELD = 8,
    INSTR_WAIT_FOR_BIT_PATTERN = 9,
    INSTR_TEST_IF_ZERO_AND_SET = 10,
    INSTR_TEST_IF_NOT_ZERO_AND_SET = 11,
    INSTR_LOAD_SM_ADDR = 12,
    INSTR_LOAD_SM_VAL = 13,
    INSTR_STORE_SM_ADDR = 14,
    INSTR_MOV_SM_SM = 15,
    INSTR_RSHIFT_SM_VAL = 16,
    INSTR_LSHIFT_SM_VAL = 17,
    INSTR_AND_SM_VAL = 18,
    INSTR_OR_SM_VAL = 19,
    INSTR_OR_SM_SM = 20,
    INSTR_AND_SM_SM = 21,
    INSTR_TEST_SM_IF_ZERO_AND_SET = 22,
    INSTR_TEST_SM_IF_NOT_ZERO_AND_SET = 23,
	// conditional execution branch and subroutine call instructions
	INSTR_LABEL = 24,
	INSTR_TEST_ADDR_AND_BRANCH = 25,
	INSTR_TEST_SM_AND_BRANCH = 26,
	INSTR_BRANCH = 27,
	// Interpreter Directives
	INSTR_END = 28,
	//Add/Subtract
	INSTR_ADD_SM_VAL = 29,
	INSTR_ADD_SM_SM = 30,
	INSTR_SUB_SM_VAL = 31,
	INSTR_SUB_SM_SM = 32,
	INSTR_LOAD_SM_FROM_ADDR_IN_SM = 33,
	INSTR_STORE_SM_TO_ADDR_IN_SM = 34,
	// New values go above here
	INSTRUCTION_OP_CODE_E_MAX,

	// These enums identify pseudo op code that
	// are used by tools for syntax shortcuts.  The
	// bootrom does not recognize the pseudo op
	// code.  When TBB is writing the TIM.bin, the pseudo
	// op codes are converted to one or more instructions
	// using the above INSTRUCTION_OP_CODE_SPEC_T enums.

	// pseudo instruction op codes used only by tools
	// Enums specify the following:
	INSTRUCTION_PSEUDO_OP_CODE_E_MIN = 10000,

	INSTR_PP_WRITE = 10001,
	INSTR_PP_TABLEHEADER = 10002,
	// New values go above here
	INSTRUCTION_PSEUDO_OP_CODE_E_MAX,
  
} INSTRUCTION_OP_CODE_SPEC_T;

 typedef struct 
{
    unsigned int	InstructionId;  // InstructionID determines # of params for defined instructions
    unsigned int	Parameter;		// first of the variable sized list of Parameters[ MAX_NUMBER_PARAMS = 3 ]
} INSTRUCTION_S, *pINSTRUCTION_S;



typedef struct 
{
    unsigned int 	OpId;
    unsigned int	OpValue;
} TZ_OPERATION, *pTZ_OPERATION;

typedef enum TZ_OPERATION_SPEC_E
{ 
    TZ_NOP = 0,              	        // Enums specify the following:
    TZ_CONFIG_ENABLE,                   // TZ config enable flag (1 = configure)
    // New values go above here  
    TZ_OPERATION_SPEC_E_MAX
} TZ_OPERATION_SPEC_T; 


 typedef enum DDR_OPERATION_SPEC_E
{ 
    DDR_NOP = 0,              // Enums specify the following:
    DDR_INIT_ENABLE,          // DDR init flag (1 = init)
    DDR_MEMTEST_ENABLE,       // DDR Memtest flag (1 = test)
    DDR_MEMTEST_START_ADDR,   // Memtest start addr (Current default is 0) 
    DDR_MEMTEST_SIZE,         // NumBytes to test (Current default is 2K)
    DDR_INIT_LOOP_COUNT,      // Loop Count for initialization attempts
    DDR_IGNORE_INST_TO,		  // Treat a time out waiting for a bit to set/clear
                              //   	as informational only, operation continues
    // New values go above here  
    DDR_OPERATION_SPEC_E_MAX
} DDR_OPERATION_SPEC_T;

/********** WTP Recognized Reserved Area Layout ********************************
*
*	WTPTP_Defined_Reserved_Format_ID    \	  This clues BR, OBM and DKB that the reserved area is in a known format
*	Number of Reserved Area Packages    /	  For each package there is a header, payload size and payload
*
*	Header	 	 		\	  Indicates what type of a Reserved Area Package
*	Size		  		 \	  Size Comprises a single Reserved Area Package
*	Payload		  		 /	  There may be any number of Packages so long as TIM/NTIM < 4KB
*			 			/
*
*	Header		 		\	  The Last one should be a Package with a Terminator Header
*	Size		 		/	  The size should be 8 bytes (the size of this package)
*
**********************************************************************************/
typedef struct
{
 UINT_T WTPTP_Reserved_Area_ID;	  	// This clues BR, OBM and DKB that the reserved area is in a known format
 UINT_T	NumReservedHeaders;	  		// For each package there is a header, payload size and payload
}WTP_RESERVED_AREA, *pWTP_RESERVED_AREA;

typedef struct
{
 UINT_T Identifier;					// Identification of this reserved area entry
 UINT_T Size;						// Size  = Payload Size + 2 words (8 bytes).
}WTP_RESERVED_AREA_HEADER, *pWTP_RESERVED_AREA_HEADER;

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T 	bmRequestType;
 UINT_T 	bRequest;
 UINT_T		wValue;
 UINT_T		wIndex;
 UINT_T		wLength;
 UINT_T		wData; 							// First word of the proceeding Data. Note, there may be more traialing data
} USB_VENDOR_REQ, *pUSB_VENDOR_REQ;			// There is no restriction that data need be 32 bit aligned.

typedef struct
{
 volatile int *Addr;
 UINT_T Value;
}GPIO_DEF, *pGPIO_DEF;
// General Purpose Patch (GPPx) related structures
typedef struct
{
	unsigned int 	OpId;
	unsigned int	OpValue;
} GPP_OPERATION, *pGPP_OPERATION;

typedef enum GPP_OPERATION_SPEC_E
{
	GPP_NOP = 0,              	// Enums specify the following:
	GPP_IGNORE_INST_TO = 6,		// Treat a time out waiting for a bit to set/clear
	// as informational only, operation continues
	// New values go above here
	GPP_OPERATION_SPEC_E_MAX
} GPP_OPERATION_SPEC_T;

typedef struct
{
	WTP_RESERVED_AREA_HEADER WRAH;
	unsigned int		NumberOperations;
	unsigned int 		NumberInstructions;
	GPP_OPERATION		GPP_Operations;     // GPP_Op[NumberOperations];
	INSTRUCTION_S	 	GPP_Instructions;	// GPP_Instruction[NumberInstructions];
} GPP_PACKAGE, *pGPP_PACKAGE;
// End General Purpose Patch related structures


#if 0 // requires general.h
typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T XferLoc;						//location to put the XFER table
 UINT_T NumPairs;
 XFER_DATA_PAIR_T pXferPairs[0];
}}OPT_XFER_SET, *pOPT_XFER_SET;
#endif 

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T Port;
 UINT_T Enabled; 					// 1 - Enabled
}OPT_PROTOCOL_SET, *pOPT_PROTCOL_SET;

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T EscSeqTimeOutMS;  				// Value is interpreted in milli secs.
}OPT_ESCAPE_SEQUENCE, *P_OPT_ESCAPE_SEQUENCE;


typedef struct
{
	WTP_RESERVED_AREA_HEADER WRAH;
	UINT_T Enable;                         // enable TR069 firmware upgrade or not
	UINT_T FlashAddr;          // flash address to store FBF header
	UINT_T Magic;                           // Magic number of FBF header
}TR069_INFO, *pTR069_INFO;

typedef struct
{
	WTP_RESERVED_AREA_HEADER WRAH;
	UINT_T Type;
}DDR_Type, *pDDR_Type;


typedef struct
{
	UINT MFPR_address;
	UINT MFPR_value;
} MFPR_PAIR_T, *pMFPR_PAIR_T;

typedef struct
{
	WTP_RESERVED_AREA_HEADER WRAH;
	UINT_T GPIO_number;			//GPIO to check
	UINT_T GPIO_trigger_val;	//value of GPIO to trigger the escape sequence
	UINT_T num_MFPR_pairs;		//number of MFPR pairs contained in this package
	MFPR_PAIR_T mfpr_pairs[1];	//MFPR address/value pairs: array will be of size 'num_MFPR_pairs"
} OPT_ESC_SEQ_v2, *P_OPT_ESC_SEQ_v2;

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T NumGpios;
 pGPIO_DEF	GPIO;
}OPT_GPIO_SET, *pOPT_GPIO_SET;

typedef struct
{
 UINT_T ResumeAddr;
 UINT_T ResumeParam;
 UINT_T ResumeFlag;
}OPT_RESUME_DDR_INFO, *pOPT_RESUME_DDR_INFO;

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 OPT_RESUME_DDR_INFO ResumeDDRInfo;
// pOPT_RESUME_DDR_INFO pResumeDDRInfo;
}OPT_RESUME_SET, *pOPT_RESUME_SET;

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T ACCR_VALUE;
 UINT_T MDCNFG_VALUE;
 UINT_T DDR_HCAL_VALUE;
 UINT_T MDREFR_VALUE;
}OPT_DDR_SET, *pOPT_DDR_SET;

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T	ImageAddr;
// UINT_T	ImageSize;
// UINT_T	ImageCRC;
}OPT_RESM_LOC, *pOPT_RESM_LOC;

typedef struct
{
 WTP_RESERVED_AREA_HEADER WRAH;
 UINT_T AutoBind;
}OPT_AUTOBIND, *pOPT_AUTOBIND;

/****  Used only for backwards compatability!!! ***/
typedef struct
{
 UINT_T Identifier;
 UINT_T PortType;
 UINT_T Port;
 UINT_T GPIOPresent;
 UINT_T NumGpios;
 pGPIO_DEF	GPIO;
}OPT_SET, *pOPT_SET;

//mDOC general formatting parameters
// look in flstruct.h and flcommon.h
// for parameter definitions
// not spelled out here
//----------------------------------
typedef struct
{								/* byte totals */
 WTP_RESERVED_AREA_HEADER WRAH;	/*0x08 bytes */
 UINT_T percentUse;				/*0x0C */        /* NAND flash inherently contains some bad blocks. TrueFFS handles
                                                  * those blocks by managing a pool of spare blocks also called transfer
                                                  * units. This format parameter specifies the percentage of the media
                                                  * to use.  Starting from TrueFFS 6.3.0 alpha 4 this field is no longer a
                                                  * configurable formatting argument. You must set this field to
                                                  * TL_DEFAULT_PERCENTAGE = 0, letting TrueFFS to choose this value for you. */
 UINT_T noOfBDTLPartitions;	    /*0x10 */  /* Indicates the number of Disk partition (1 to 4). */
 UINT_T noOfBinaryPartitions;   /*0x14 */  /* Indicates the number of binary partitions (up to 3). 0 will
                                            * cause formatting with no binary partition. This value is ignored
                                            * if TL_LEAVE_BINARY_AREA flag is set in the irFlags field the ioreq */
 UINT_T cascadedDeviceNo;       /*0x18*/  /* Not used */
 UINT_T noOfCascadedDevices;    /*0x1C*/  /* Not used */
 UINT_T progressCallback;  	    /*0x20*/  /* Progress callback routine, will be called if not NULL.
                                             The callback routine is called after erasing each unit,
                                             and its parameters are the total number of erase units
                                             to format and the number erased so far.
                                             The callback routine returns a Status value. A value of
                                             OK (0) allows formatting to continue. Any other value
                                             will abort the formatting with the returned status code. */
                                          /* In case the FL_REPORT_MOUNT_PROGRESS compilation flag is set the
                                             routine will also report the mount progress of the mount routine
                                             for each of the Disk partitions. A 0,0 return values will report
                                             the end of a format status and of a mount operation */
 UINT_T FP_0_RFU_0;             /*0x24*/  /* Reserved 0 */
 UINT_T FP_1_RFU_0;             /*0x28*/  /* Reserved 0 */

  /* Note the following section is not used by for DiskOnChips */
  /*************************************************************/
 UINT_T   bootImageLen;         /*0x2C*/  /* Reserved 0     */
 UINT_T   vmAddressingLimit;    /*0x30*/  /* Reserved 0     */
 UINT_T   embeddedCISlength;    /*0x34*/  /* Reserved 0     */
 UINT_T   *embeddedCIS;         /*0x38*/  /* Reserved NULL  */
}MDOC_FORMAT_INFO, *pMDOCFORMAT_INFO;

//mDOC BDTL partition type
//------------------------
typedef	struct
{
  WTP_RESERVED_AREA_HEADER WRAH;	/*0x08 bytes */
  UINT_T  length;                   /*0x0c */      /* The size in bytes of the usable storage space. The size
                                                    rounded upwards to a multiplication of a block size.
                                                    The size of the last partition will calculated automatically,
                                                    but if the requested size is greater then the remaining space
                                                    an error code will be returned,. Requesting zero size for any
                                                    partition but the last will generate an flBadParameters status. */

  UINT_T  fastAreaLength;			/*0x10*/
  UINT_T  lengthType;				/*0x14*/
  UINT_T  fastAreaLengthType;		/*0x18*/
  UINT_T  fastAreaVirtualFactor;    /*0x1C*/ /* Should be set to FL_NORMAL_SPACING = 1 */
  UINT_T  noOfSpareUnits;           /*0x20*/ /* BDTL needs at least one spare erase unit in order to function
                                               as a read/write media. It is possible to specify more than one
                                               spare unit, which takes more media space. The advantage of
                                               specifying more than one spare unit is that if one of the flash
                                               erase units becomes bad and un-erasable in the future, then one
                                               of the spare units can replace it. In that case, a second spare
                                               unit enables TrueFFS to continue its read/write functionality,
                                               whereas if no second spare unit is available the media goes into
                                               read-only mode. The standard value used is 3 */

  UINT_T  BDTLFP_0_RFU_0;           /*0x24*/  /* Reserved 0  */
  UINT_T  BDTLFP_1_RFU_0;           /*0x28*/  /* Reserved 0  */
  UINT_T  BDTLFP_2_RFU_0;           /*0x2C*/  /* Reserved 0  */
  UINT_T  BDTLFP_3_RFU_0;           /*0x30*/  /* Reserved 0  */
  UINT_T  protectionKey[8];         /*0x50*/  /* The key for the protection*/
  UINT_T  protectionType;           /*0x54*/  /* PROTECTABLE          - Can receive protection           */
                                              /* READ_PROTECTED       - Protect against read operations  */
                                              /* WRITE_PROTECTED      - Protect against write operations */
                                              /* LOCK_ENABLED         - Enables the hardware lock signal */
                                              /* PROTECTABLE          - This partition can be protected  */
                                              /* CHANGEABLE_PROTECTION - protection type can be changed  */
                                              /* The ratio between the real media size and the virtual size
                                                reported to the file system when compression is active. */

}MDOC_BDTL_PARTITION, *pMDOC_BDTL_PARTITION;

//mDOC binary partition type
//------------------------
typedef	struct
{
  WTP_RESERVED_AREA_HEADER WRAH;  /*0x08 bytes */
  UINT_T  length;                 /*0x0c*/            /* Required number of usable bytes (rounded to units) */
                                                      /* in the  partition.                                 */

  UINT_T   lengthType;            /*0x10*/       /* Must be FL_LENGTH_IN_BYTES = 0                     */
  UINT_T   sign[4];               /*0x20*/       /* signature of the binary  partition to format. Typically "BIPO"
                                                    The signature 0xFFFF FFFF is not a valid signature  */

  UINT_T  flags;                  /*0x24*/       /* TL_NORMAL_FORMAT=0  / TL_SPL_FORMAT=0xF0            */
  UINT_T  spareBlocks;            /*0x28*/   /* Spare blocks for DBB support, should be at least 1              */
  UINT_T  BDKFP_0_RFU_0;          /*0x2C*/           /* Reserved 0  */
  UINT_T  BDKFP_1_RFU_0;          /*0x30*/           /* Reserved 0  */
  UINT_T  BDKFP_2_RFU_0;          /*0x34*/           /* Reserved 0  */
  UINT_T  BDKFP_3_RFU_0;          /*0x38*/           /* Reserved 0  */
  UINT_T  protectionKey[8];       /*0x58*/     /* The key for the protection*/
  UINT_T  protectionType;         /*0x5C*/             /* PROTECTABLE          - Can receive protection           */
                                               /* READ_PROTECTED       - Protect against read operations  */
                                               /* WRITE_PROTECTED      - Protect against write operations */
                                               /* LOCK_ENABLED         - Enables the hardware lock signal */
                                               /* PROTECTABLE          - This partition can be protected  */
                                               /* CHANGEABLE_PROTECTION - protection type can be changed  */
}MDOC_BINARY_PARTITION, *pMDOC_BINARY_PARTITION;

/*********************************************************************************/

typedef enum
{
	PlatformVerificationKey,
	NetworkOperatorCAKey,
	SoftwareUpdateCAKey,
	DRMDeviceCAKey,
	OEMReservedKey1,
	OEMReservedKey2,
	NUMKEYMODULES
}
KEYMODULES_T;

typedef enum
{
    Marvell_DS = 0,
    PKCS1_v1_5_Caddo = 1,
    PKCS1_v2_1_Caddo = 2,
    PKCS1_v1_5_Ippcp = 3,
    PKCS1_v2_1_Ippcp = 4,
    ECDSA_256 = 5,
    ECDSA_521 = 6
}
ENCRYPTALGORITHMID_T;

#define Intel_DS Marvell_DS

typedef enum
{
	MRVL_SHA160 = 20,
	MRVL_SHA256 = 32, 
	MRVL_SHA512 = 64
}
HASHALGORITHMID_T;

typedef struct
{
 UINT_T Version;
 UINT_T	Identifier;					// "TIMH"
 UINT_T Trusted;					// 1- Trusted, 0 Non
 UINT_T IssueDate;
 UINT_T OEMUniqueID;
} VERSION_I, *pVERSION_I;			// 0x10 bytes

typedef struct
{
 UINT_T WTMFlashSign;
 UINT_T WTMEntryAddr;
 UINT_T WTMEntryAddrBack;
 UINT_T WTMPatchSign;
 UINT_T WTMPatchAddr;
 UINT_T BootFlashSign;
} FLASH_I, *pFLASH_I;				// 0x10 bytes

typedef struct
{
 UINT_T	KeyID;						// Associate an ID with this key
 UINT_T HashAlgorithmID;            // See HASHALGORITHMID_T
 UINT_T ModulusSize;				// 1024 bit or 2048 bit keys
 UINT_T PublicKeySize;
 UINT_T RSAPublicExponent[MAXKEYSIZEWORDS];		// Contents depend on PublicKeySize
 UINT_T RSAModulus[MAXKEYSIZEWORDS];// Up to 2K bits
 UINT_T KeyHash[8]; 				// Reserve 256 bits for the hash
} KEY_MOD, *pKEY_MOD;				// 0x22C bytes

typedef struct
{
 UINT_T ImageID;					// Indicate which Image
 UINT_T NextImageID;				// Indicate next image in the chain
 UINT_T FlashEntryAddr;			 	// Block numbers for NAND
 UINT_T LoadAddr;
 UINT_T ImageSize;
 UINT_T ImageSizeToHash;
 UINT_T HashAlgorithmID;            // See HASHALGORITHMID_T
 UINT_T Hash[8];					// Reserve 256 bits for the hash
 UINT_T PartitionNumber;			// This is new for V3.2.0
} IMAGE_INFO_3_2_0, *pIMAGE_INFO_3_2_0;			// 0x40 bytes

typedef struct
{
 UINT_T ImageID;					// Indicate which Image
 UINT_T NextImageID;				// Indicate next image in the chain
 UINT_T FlashEntryAddr;			 	// Block numbers for NAND
 UINT_T LoadAddr;
 UINT_T ImageSize;
 UINT_T ImageSizeToHash;
 UINT_T HashAlgorithmID;            // See HASHALGORITHMID_T
 UINT_T Hash[8];					// Reserve 256 bits for the hash
} IMAGE_INFO_3_1_0, *pIMAGE_INFO_3_1_0; 	// 0x3C bytes

typedef struct
{
 UINT_T ImageID;					// Indicate which Image
 UINT_T NextImageID;				// Indicate next image in the chain
 UINT_T FlashEntryAddr;			 	// Block numbers for NAND
 UINT_T LoadAddr;
 UINT_T ImageSize;
 UINT_T ImageSizeToHash;
 UINT_T HashAlgorithmID;            // See HASHALGORITHMID_T
 UINT_T Hash[16];					// Reserve 512 bits for the hash, this is new for V3.4.0
 UINT_T PartitionNumber;
} IMAGE_INFO_3_4_0, *pIMAGE_INFO_3_4_0;			// 0x60 bytes

typedef struct
{
	UINT_T ImageID;						// Indicate which Image
	UINT_T NextImageID;					// Indicate next image in the chain
	UINT_T FlashEntryAddr;					// Block numbers for NAND
	UINT_T LoadAddr;
	UINT_T ImageSize;
	UINT_T ImageSizeToHash;
	HASHALGORITHMID_T HashAlgorithmID;		// See HASHALGORITHMID_T
	UINT_T Hash[16];						// Reserve 512 bits for the hash
	UINT_T PartitionNumber;
	ENCRYPTALGORITHMID_T EncAlgorithmID;	// See ENCRYPTALGORITHMID_T
	UINT_T EncryptStartOffset;
	UINT_T EncryptSize;
} IMAGE_INFO_3_5_0, *pIMAGE_INFO_3_5_0;			// 0x60 bytes

typedef struct
{
 UINT_T	KeyID;						// Associate an ID with this key
 UINT_T HashAlgorithmID;            // 160 - SHA1, 256 - SHA2
 UINT_T KeySize;					// Specified in bits
 UINT_T PublicKeySize;				// Specified in bits
 UINT_T RSAPublicExponent[MAXRSAKEYSIZEWORDS]; // Contents depend on PublicKeySize
 UINT_T RSAModulus[MAXRSAKEYSIZEWORDS]; // Up to 2K bits
 UINT_T KeyHash[8]; 				// Reserve 256 bits for the hash
} KEY_MOD_3_1_0, *pKEY_MOD_3_1_0;				// 0x22C bytes
typedef struct
{
	UINT_T	KeyID;						// Associate an ID with this key
	HASHALGORITHMID_T HashAlgorithmID;    // See HASHALGORITHMID_T
	UINT_T KeySize;					// Specified in bits
	UINT_T PublicKeySize;				// Specified in bits
	UINT_T RSAPublicExponent[MAXRSAKEYSIZEWORDS]; // Contents depend on PublicKeySize
	UINT_T RSAModulus[MAXRSAKEYSIZEWORDS]; // Up to 2K bits
	UINT_T KeyHash[8]; 				// Reserve 256 bits for the hash
} KEY_MOD_3_2_0, *pKEY_MOD_3_2_0;				// 0x22C bytes

#if RVCT
#pragma anon_unions
#endif
typedef struct
{
	UINT_T KeyID;				// Associate an ID with this key
	HASHALGORITHMID_T HashAlgorithmID;     // See HASHALGORITHMID_T
	UINT_T KeySize;			    // Specified in bits
	UINT_T PublicKeySize;		// Specified in bits
	ENCRYPTALGORITHMID_T EncryptAlgorithmID;	// See ENCRYPTALGORITHMID_T;
	union
	{
		struct
		{
			UINT_T RSAPublicExponent[MAXRSAKEYSIZEWORDS];	// Contents depend on PublicKeySize
			UINT_T RSAModulus[MAXRSAKEYSIZEWORDS];			// Up to 2K bits
		}Rsa;

		struct
		{
			UINT_T PublicKeyCompX[MAXECCKEYSIZEWORDS]; // Contents depend on PublicKeySize
			UINT_T PublicKeyCompY[MAXECCKEYSIZEWORDS]; // Up to 521 bits
			// Pad this struct so it remains consistent with RSA struct
			UINT_T Reserved[(2*MAXRSAKEYSIZEWORDS)-(2*MAXECCKEYSIZEWORDS)]; 
		}Ecdsa;
	};

	UINT_T KeyHash[8]; 				// Reserve 256 bits for the hash
} KEY_MOD_3_3_0, *pKEY_MOD_3_3_0;		// 


// use EncryptedBitMask to access bit 31 of EncryptedAlgorithmID
// if bit 31 == 0 the access KEY_MOD_3_4_0 using the Rsa or Ecdsa structs
// if bit 31 == 1 the access KEY_MOD_3_4_0 using the EncryptedRsa or Encrypted Ecdsa structs
#define EncryptedBitMask 0x80000000
typedef struct
{
	UINT_T KeyID;                      // Associate an ID with this key
	HASHALGORITHMID_T HashAlgorithmID;    // See HASHALGORITHMID_T
	UINT_T KeySize;            // Specified in bits
	UINT_T PublicKeySize;      // Specified in bits
	ENCRYPTALGORITHMID_T EncryptAlgorithmID; // See ENCRYPTALGORITHMID_T;
	union
	{
		struct
		{
			UINT_T RSAPublicExponent[MAXRSAKEYSIZEWORDS];   // Contents depend on PublicKeySize
			UINT_T RSAModulus[MAXRSAKEYSIZEWORDS];          // Up to 2K bits
		}Rsa;

		struct
		{
			UINT_T PublicKeyCompX[MAXECCKEYSIZEWORDS]; // Contents depend on PublicKeySize
			UINT_T PublicKeyCompY[MAXECCKEYSIZEWORDS]; // Up to 521 bits
			// Pad this struct so it remains consistent with RSA struct
			UINT_T Reserved[(2*MAXRSAKEYSIZEWORDS)-(2*MAXECCKEYSIZEWORDS)];
		}Ecdsa;

		struct
		{
			UINT_T EncryptedHashRSAPublicExponent[MAXRSAKEYSIZEWORDS];  // Contents depend on PublicKeySize
			UINT_T EncryptedHashRSAModulus[MAXRSAKEYSIZEWORDS];         // Up to 2K bits
		}EncryptedRsa;

		struct
		{
			UINT_T EncryptedHashPublicKeyCompX_R[MAXECCKEYSIZEWORDS]; // Contents depend on PublicKeySize
			UINT_T EncryptedHashPublicKeyCompX_S[MAXECCKEYSIZEWORDS]; // Contents depend on PublicKeySize

			UINT_T EncryptedHashPublicKeyCompY_R[MAXECCKEYSIZEWORDS]; // Up to 521 bits
			UINT_T EncryptedHashPublicKeyCompY_S[MAXECCKEYSIZEWORDS]; // Up to 521 bits

			// Pad this struct so it remains consistent with encrypted RSA struct
			UINT_T Reserved[(2 * MAXRSAKEYSIZEWORDS)-(4 * MAXECCKEYSIZEWORDS)];
		}EncryptedEcdsa;
	};

	UINT_T KeyHash[16];                  // Reserve 512 bits for the hash
} KEY_MOD_3_4_0, *pKEY_MOD_3_4_0;        //



typedef struct
{
 ENCRYPTALGORITHMID_T DSAlgorithmID; // See ENCRYPTALGORITHMID_T
 HASHALGORITHMID_T HashAlgorithmID;      // See HASHALGORITHMID_T
 UINT_T KeySize;	          // Specified in bits
 UINT_T Hash[8];					// Reserve 256 bits for the hash
 union 	// Note that this union should not be included as part of the hash for TIM in the Digital Signature
 {
    struct
    {
        UINT_T RSAPublicExponent[MAXRSAKEYSIZEWORDS];
        UINT_T RSAModulus[MAXRSAKEYSIZEWORDS];           	// Up to 2K bits
        UINT_T RSADigS[MAXRSAKEYSIZEWORDS];				// Contains TIM Hash
    }Rsa;
    struct
    {
        UINT_T ECDSAPublicKeyCompX[MAXECCKEYSIZEWORDS]; // Allow for 544 bits (17 words, 68 bytes for use with EC-521) 
        UINT_T ECDSAPublicKeyCompY[MAXECCKEYSIZEWORDS];
        UINT_T ECDSADigS_R[MAXECCKEYSIZEWORDS];
        UINT_T ECDSADigS_S[MAXECCKEYSIZEWORDS];
        UINT_T Reserved[(MAXRSAKEYSIZEWORDS*3)-(MAXECCKEYSIZEWORDS*4)];	
    } Ecdsa;
 };
} PLAT_DS, *pPLAT_DS;				// 0x780 bytes

// Constant part of the TIMs
typedef struct
{
 VERSION_I      VersionBind;         			// 0
 FLASH_I        FlashInfo;           			// 0x10
 UINT_T         NumImages;           			// 0x20
 UINT_T         NumKeys;						// 0x24
 UINT_T         SizeOfReserved;					// 0x28
} CTIM, *pCTIM;									// 0x2C

// TIM structure for use by DKB/OBM/BootROM
/*typedef struct
{
 pCTIM 			pConsTIM;			// Constant part
 pIMAGE_INFO	pImg;				// Pointer to Images
 pKEY_MOD		pKey;				// Pointer to Keys
 PUINT			pReserved;			// Pointer to Reserved Area
 pPLAT_DS       pTBTIM_DS;			// Pointer to Digital Signature
} 
TIM, *pTIM;*/

// NTIM structure for use by DKB/OBM/BootROM
typedef struct
{
 pCTIM 			pConsTIM;			// Constant part
 pIMAGE_INFO_3_1_0	pImg;				// Pointer to Images
 PUINT			pReserved;			// Pointer to Reserved Area
} NTIM_3_1_0, *pNTIM_3_1_0;
typedef struct
{
 pCTIM 			pConsTIM;			// Constant part
 pIMAGE_INFO_3_2_0	pImg;				// Pointer to Images
 PUINT			pReserved;			// Pointer to Reserved Area
} NTIM_3_2_0, *pNTIM_3_2_0;
typedef struct
{
 pCTIM 			pConsTIM;			// Constant part
 pIMAGE_INFO_3_4_0	pImg;				// Pointer to Images
 PUINT			pReserved;			// Pointer to Reserved Area
} NTIM_3_4_0, *pNTIM_3_4_0;


// Defined for DTIM support 2012-3



typedef enum
{
	PRIMARYIMAGE = 0,                // Primary image
	RECOVERYIMAGE = 1,               // Recovery image 
	CPIMAGE = 2  ,                    // CP image    
	PPSETINGIMAG = 3,                 //PP Setting image
    MARVELL_RESERVED_MAX = 9  ,   
	CUSTMOZIEDIMAGE_TYPE1 = 10,
	CUSTMOZIEDIMAGE_TYPE2 = 11,
	CUSTMOZIEDIMAGE_TYPE3 = 12,
	CUSTMOZIEDIMAGE_TYPE4 = 13,
	CUSTMOZIEDIMAGE_TYPE5 = 14,
	CUSTMOZIEDIMAGE_TYPE6 = 15,
	CUSTMOZIEDIMAGE_TYPE7 = 16,
	CUSTMOZIEDIMAGE_TYPE8 = 17,
	CUSTMOZIEDIMAGE_TYPE9 = 18,
	CUSTMOZIEDIMAGE_TYPE10 = 19,
	CUSTMOZIEDIMAGE_TYPE11 = 20,
	CUSTMOZIEDIMAGE_TYPE12 = 21,
	CUSTMOZIEDIMAGE_TYPE13 = 22,
	CUSTMOZIEDIMAGE_TYPE14 = 23,
	CUSTMOZIEDIMAGE_TYPE15 = 24,
	CUSTMOZIEDIMAGE_TYPE16 = 25,
	CUSTMOZIEDIMAGE_TYPE17 = 26,
	CUSTMOZIEDIMAGE_TYPE18 = 27,
	CUSTMOZIEDIMAGE_TYPE19 = 28,
	CUSTMOZIEDIMAGE_TYPE20 = 29,
	CUSTMOZIEDIMAGE_TYPE_MAX = 50,
} OTA_IMAGE_TYPE;

typedef struct
{
	UINT_T ImageID;                    // 0x54494Dxx   - secondary tim ID (TIMx)
	OTA_IMAGE_TYPE ImageType;          // OTA_IMAGE_TYPE (Primary VS Recovery)
	UINT_T FlashEntryAddr[2];          // Reserve 2 words for future compatibility
	UINT_T PartitionNumber;            // Partition # in the flash
} IMG_MAP_INFO, *pIMG_MAP_INFO; 

typedef struct
{
	WTP_RESERVED_AREA_HEADER WRAH;     // Let it contain IMAP as package ID 
	UINT_T NumberOfMappedImages;       // Number of images with mapping information
	IMG_MAP_INFO pImgMapInfo[1];       // First image map information struct
} IMAGE_MAP, *pIMAGE_MAP;           



#endif



