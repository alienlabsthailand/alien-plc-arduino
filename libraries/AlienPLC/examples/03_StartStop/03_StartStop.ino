// Alien PLC 20MR - Start / Stop motor (latching), like this ladder:
//
//   |--[ X0 ]--+--[/X1 ]--( Y0 )--|      X0 = Start button (NO)
//   |--[ Y0 ]--+                  |      X1 = Stop button  (NO here; use an NC button in real machines)
//
// Y1 turns on 3 s after the motor starts (TON timer). STOP switch position turns everything off.
#include <AlienPLC.h>
using namespace AlienPLC;

Timer delayY1;

void setup() {
  begin();
  Serial.begin(9600);
}

void loop() {
  bool start = input(0);   // X0
  bool stop  = input(1);   // X1
  bool motor = outputState(0);

  if (!isRun()) motor = false;
  else          motor = (start || motor) && !stop;

  output(0, motor);                           // Y0 = motor
  output(1, delayY1.on(motor, 3000));         // Y1 = 3 s after start
  digitalWrite(LED1, isRun());
}
