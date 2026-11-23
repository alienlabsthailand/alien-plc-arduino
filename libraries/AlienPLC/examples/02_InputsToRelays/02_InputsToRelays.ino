// Alien PLC 20MR - Inputs to relays
// X0..X7 drive Y0..Y7 directly while the switch is on RUN. On STOP all relays are off.
#include <AlienPLC.h>
using namespace AlienPLC;

void setup() {
  begin();
}

void loop() {
  if (!isRun()) { allOff(); digitalWrite(LED1, LOW); return; }
  digitalWrite(LED1, HIGH);                 // LED1 = RUN indicator
  for (uint8_t i = 0; i < 8; i++) output(i, input(i));
}
