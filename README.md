# Alien PLC – Arduino board package

Arduino support for the **Alien PLC 20MR**: 12 opto-isolated inputs, 8 relay outputs, RUN/STOP
switch, 2 analog inputs (0–10 V), PWM, RS232 (DB9). MCU: Geehy APM32F030C8T6
(STM32F030C8 compatible).

* Pin names built in: `X0`–`X7`, `X10`–`X13`, `Y0`–`Y7`, `RUN_SW`, `LED1`, `LED2`, `AIN0`, `AIN1`, `PWM_OUT`, `VIN_SENSE`
* `Serial` goes to the DB9 port (USART1) – Serial Monitor works out of the box
* **Upload without the BOOT0 jumper** – the Upload button sends `!BOOT`, the board resets into its
  ROM bootloader and is flashed over the same serial cable
* Examples: File → Examples → AlienPLC

## ติดตั้ง (Installation)

1. Arduino IDE 2.x → **File → Preferences → Additional boards manager URLs** ใส่ 2 บรรทัดนี้:
   ```
   https://github.com/stm32duino/BoardManagerFiles/raw/main/package_stmicroelectronics_index.json
   https://raw.githubusercontent.com/alienlabsthailand/alien-plc-arduino/main/package_alienlabs_index.json
   ```
2. **Tools → Board → Boards Manager**
   * ติดตั้ง **STM32 MCU based boards** (STMicroelectronics) เวอร์ชัน **3.1.0** ก่อน
   * แล้วติดตั้ง **Alien Labs Boards**
3. **Tools → Board → Alien Labs Boards → Alien PLC 20MR**
4. เลือกพอร์ต COM ของสาย USB-RS232 แล้วกด **Upload**

> Package นี้ใช้คอมไพเลอร์และ core จาก STM32 package (ทดสอบกับ 3.1.0) จึงต้องติดตั้ง STM32 ก่อน
> ตัว upload ตอนนี้รองรับ **Windows** เท่านั้น

## เขียนโปรแกรม (Example)

```cpp
#include <AlienPLC.h>
using namespace AlienPLC;

void setup() { begin(); Serial.begin(9600); }

void loop() {
  if (!isRun()) { allOff(); return; }      // RUN/STOP switch
  output(0, input(0));                      // X0 -> Y0
}
```

| ฟังก์ชัน | ความหมาย |
|---|---|
| `begin()` | ตั้งค่า X, Y (ปิด), LED, สวิตช์ |
| `input(n)` | อินพุต n (0–11 = X0..X7, X10..X13) ทำงานอยู่ไหม (ต่อกับ 0V) |
| `output(n, on)` / `allOff()` | สั่งรีเลย์ Y0..Y7 |
| `isRun()` | สวิตช์อยู่ RUN |
| `analogVolts(0/1)` | แรงดันที่ขั้ว A0/A1 (ประมาณ) |
| `supplyVolts()` | แรงดันไฟเลี้ยง |
| `pwm(0..255)` | PWM ที่หัวพินขยาย |
| `Edge`, `Timer` | ขอบขาขึ้น (เหมือน LDP) และ timer หน่วงเวลา (เหมือน TON) |

## Pin map

| Terminal | MCU | Terminal | MCU |
|---|---|---|---|
| X0 | PA0 | Y0 (C0) | PA4 |
| X1 | PB3 | Y1 (C0) | PA7 |
| X2 | PB4 | Y2 (C1) | PB14 |
| X3 | PA1 | Y3 (C1) | PB15 |
| X4 | PF1 | Y4 (C2) | PA12 |
| X5 | PC14 | Y5 (C2) | PA11 |
| X6 | PC15 | Y6 (C2) | PF6 |
| X7 | PB9 | Y7 (C2) | PF7 |
| X10 | PB7 | LED1 / LED2 | PB10 / PB11 |
| X11 | PB6 | RUN/STOP (HIGH = RUN) | PB8 |
| X12 | PB5 | PWM / A0 / A1 | PA6 / PA5 / PB0 |
| X13 | PA15 | Supply monitor | PB1 |
| Serial (DB9, J3) | PA9 TX / PA10 RX | | |

Inputs are active **LOW** (terminal shorted to the input 0V). Relays are ON when the pin is HIGH.

## Upload ไม่ได้? (Recovery)

ถ้าโปรแกรมค้างจนรับคำสั่งไม่ได้:
1. จั๊มป์แพด **BOOT0** (2 แพดข้างตัวต้านทาน 103) แล้วปิดเปิดไฟ
2. กด Upload ตามปกติ
3. ถอดจั๊มป์ แล้วปิดเปิดไฟ

## Serial Monitor เปิดไม่ได้? (สาย CH340)

สาย USB-Serial ชิป CH340 บางรุ่น **ไม่ยอมตั้ง baud เดิมซ้ำ** ทำให้เปิดพอร์ตไม่ได้
(ตั้งแต่ v1.0.1 ตัว upload แก้ให้อัตโนมัติหลังโหลดโปรแกรม) ถ้ายังเจอ:
* เปลี่ยน baud ใน Serial Monitor ไปค่าอื่นแล้วเปลี่ยนกลับ หรือ
* ถอดสาย USB แล้วเสียบใหม่
* แนะนำใช้สาย **CP2102 / FT232** จะไม่มีปัญหานี้

## How "upload without jumper" works

The board variant starts `Serial` at 9600 before `setup()`, and a 1 ms SysTick hook watches the
receive buffer (without consuming it) for `!BOOT`. When seen, it stores a magic word in RAM and
resets; very early after reset the core jumps into the MCU's ROM bootloader (USART1). After upload
the program restarts once to boot cleanly from flash (Cortex-M0 has no VTOR). The upload tool tries
9600, 115200, 57600, 38400 and 19200 baud, so sketches may use any of these.

## Web control page

`extras/AlienPLC_IOControl.html` + example `05_IOControl`: open the page in Edge/Chrome, connect the
COM port, and click relays / watch inputs live (Web Serial).

## License

Board variant files derived from STMicroelectronics STM32duino (BSD-3-Clause, headers kept).
Alien Labs code: MIT.
