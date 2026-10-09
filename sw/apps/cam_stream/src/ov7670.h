#ifndef OV7670_H
#define OV7670_H

#include "xiicps.h"
#include "xstatus.h"

#define OV7670_I2C_ADDR 0x21  /* 7-bit SCCB address (write=0x42, read=0x43) */

s32 OV7670_CheckId(XIicPs *IicInstancePtr);
s32 OV7670_Init(XIicPs *IicInstancePtr);

#endif
