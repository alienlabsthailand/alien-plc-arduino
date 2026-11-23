// Alien PLC 20MR - Analog inputs, supply voltage and PWM
// Prints A0, A1 (estimated terminal volts) and the supply voltage every 0.5 s.
// PWM on the expansion header follows A0 (0-10 V -> 0-100 %).
#include <AlienPLC.h>
using namespace AlienPLC;

void setup() {
  begin();
  Serial.begin(9600);
}

void loop() {
  float a0 = analogVolts(0), a1 = analogVolts(1), vin = supplyVolts();
  pwm((uint8_t)constrain(a0 / 10.0f * 255.0f, 0, 255));
  Serial.print("A0="); Serial.print(a0, 2);
  Serial.print(" V  A1="); Serial.print(a1, 2);
  Serial.print(" V  Supply="); Serial.print(vin, 1); Serial.println(" V");
  delay(500);
}
