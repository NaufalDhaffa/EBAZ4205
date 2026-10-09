#ifndef LITESCOPE_BRIDGE_H
#define LITESCOPE_BRIDGE_H

#include "xgpiops.h"

/* Blocks forever, relaying litex's UART wire protocol (see
 * litex.tools.remote.comm_uart.CommUART) onto litescope_top_0's CSR bus
 * via csr_gpio_bridge_0's GPIO_O/GPIO_I handshake. Entered from the
 * console on request (see main.c); reset the board to leave. */
void LitescopeBridge_Run(XGpioPs *Gpio);

#endif
