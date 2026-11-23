/*
  Alien PLC 20MR - built-in upload support (no user code needed)

  1. Serial is started at 9600 before setup() (initVariant), so the board always listens on the
     DB9/J3 port. A sketch may call Serial.begin(<other baud>); the upload tool tries common bauds.
  2. Every 1 ms (SysTick hook) the Serial RX buffer is scanned (without consuming it) for "!BOOT".
     When found: a magic word is written to RAM and the MCU resets.
  3. Very early after reset (constructor, before clocks/main), the magic word sends the CPU into
     the ROM bootloader (USART1) - from thread mode with a clean peripheral state.
  4. After the bootloader's GO command, system memory is still mapped at address 0 (Cortex-M0 has
     no VTOR), so the program restarts itself once to boot cleanly from flash.

  Same idea as Arduino Leonardo's "1200-baud touch", using a text command because a real UART
  cannot see baud changes and the board has no DTR/RTS line to the MCU.
*/
#include "Arduino.h"

#if defined(ARDUINO_ALIEN_PLC_20MR)

#define ALIEN_SYSMEM_BASE   0x1FFFEC00UL          // ROM bootloader (verified on APM32F030C8)
#define ALIEN_MAGIC_ADDR    ((volatile uint32_t *)0x20001E00UL)  // 512 B below top of 8 KB SRAM
#define ALIEN_MAGIC         0x424F4F54UL          // "BOOT"

static void alien_jump_to_rom_bootloader(void)
{
  // Called right after reset: peripherals are in reset state, clock is HSI 8 MHz.
  RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;
  (void)RCC->APB2ENR;
  SYSCFG->CFGR1 = (SYSCFG->CFGR1 & ~SYSCFG_CFGR1_MEM_MODE) | SYSCFG_CFGR1_MEM_MODE_0;  // system flash @0
  __DSB(); __ISB();
  uint32_t sp = *(volatile uint32_t *)ALIEN_SYSMEM_BASE;
  uint32_t rv = *(volatile uint32_t *)(ALIEN_SYSMEM_BASE + 4);
  __set_MSP(sp);
  ((void (*)(void))rv)();
  while (1) {}
}

__attribute__((constructor(101))) static void alien_early_boot(void)
{
  // (a) "!BOOT" requested before the reset?
  if (ALIEN_MAGIC_ADDR[0] == ALIEN_MAGIC && ALIEN_MAGIC_ADDR[1] == ~ALIEN_MAGIC) {
    ALIEN_MAGIC_ADDR[0] = 0; ALIEN_MAGIC_ADDR[1] = 0;
    alien_jump_to_rom_bootloader();
  }
  // (b) started by the bootloader's GO command? -> restart cleanly from flash
  RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;
  (void)RCC->APB2ENR;
  if ((SYSCFG->CFGR1 & SYSCFG_CFGR1_MEM_MODE) != 0) {
    NVIC_SystemReset();
  }
}

// Read access to the protected serial_t inside the Uart object (no consumption of user data).
struct AlienUartPeek : public Uart {
  static serial_t &of(Uart &u) { return u.*(&AlienUartPeek::_serial); }
};

extern "C" void osSystickHandler(void)
{
  static uint16_t idx = 0;
  static uint8_t  match = 0;
  static const char key[] = "!BOOT";
  serial_t &s = AlienUartPeek::of(Serial);
  if (s.rx_buff == NULL) return;
  uint16_t head = s.rx_head;
  if (idx >= SERIAL_RX_BUFFER_SIZE) idx = 0;
  while (idx != head) {
    char c = (char)s.rx_buff[idx];
    idx = (uint16_t)((idx + 1) % SERIAL_RX_BUFFER_SIZE);
    if (c == key[match]) {
      if (key[++match] == 0) {
        ALIEN_MAGIC_ADDR[0] = ALIEN_MAGIC;
        ALIEN_MAGIC_ADDR[1] = ~ALIEN_MAGIC;
        NVIC_SystemReset();      // pins go to reset state -> relays off
      }
    } else {
      match = (c == key[0]) ? 1 : 0;
    }
  }
}

// Start Serial before setup() so the board always listens for "!BOOT".
void initVariant(void)
{
  Serial.begin(9600);
}

#endif /* ARDUINO_ALIEN_PLC_20MR */
