// Alien PLC 20MR - Hello
// Prints to the DB9 serial port (9600) and blinks LED1 and relay Y0 every 0.5 s.
// Open Serial Monitor at 9600 to see the text.
#include <AlienPLC.h>

void setup() {
  AlienPLC::begin();
  Serial.begin(9600);
  Serial.println("Hello from Alien PLC!");
}

void loop() {
  static bool on = false;
  on = !on;
  digitalWrite(LED1, on);
  digitalWrite(Y0, on);
  Serial.println(on ? "Y0 ON" : "Y0 OFF");
  delay(500);
}
