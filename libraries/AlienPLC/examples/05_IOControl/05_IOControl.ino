/*
  IOControl - serial command firmware for the Alien PLC 20MR (use with extras/AlienPLC_IOControl.html)
  Used by IOControl.html (browser UI over Web Serial).
  Serial on DB9: USART1 PA9/PA10, 9600 8N1.

  Board -> PC (every 200 ms and on any change):
    S X=<12 x 0/1 raw X0..X13> R=<8 relays> L=<2 LEDs> RUN=<0/1> P=<pwm 0..255>
      A=<5 analog readings 0..4095, comma separated, order of A_PINS> U=<8 x 0/1 raw unknown pins>
  PC -> board (one command per line):
    R<n><0|1>   relay n (0..7 = Y0..Y7) off/on          e.g. R31
    L<n><0|1>   status LED n (0..1)                     e.g. L01
    P<0..255>   PWM duty on the header PWM pin (PA6)    e.g. P128
    A           all relays + LEDs + PWM off
    ?           send status now
    !BOOT       handled by the Alien PLC core: resets into the bootloader for upload
*/
#include <Arduino.h>

// Inputs X0..X13 (measured 2026-11-22)
const uint32_t X_PINS[12] = { PA0, PB3, PB4, PA1, PF1, PC14, PC15, PB9, PB7, PB6, PB5, PA15 };
// Relays Y0..Y7 (measured 2026-11-22), HIGH = ON
const uint32_t RELAY_PINS[8] = { PA4, PA7, PB14, PB15, PA12, PA11, PF6, PF7 };
// Status LEDs
const uint32_t LED_PINS[2] = { PB10, PB11 };
// RUN/STOP switch: HIGH = RUN
const uint32_t RUN_PIN = PB8;
// Expansion header PWM pin
const uint32_t PWM_PIN = PA6;
// ADC-capable pins not mapped yet: A0/A1 of the expansion header should be two of these
const uint32_t A_PINS[5] = { PA2, PA3, PA5, PB0, PB1 };
// Other pins not mapped yet
const uint32_t U_PINS[8] = { PA8, PA13, PA14, PB2, PB12, PB13, PC13, PF0 };

bool relay[8];
bool led[2];
int pwm = 0;
String lastStatus;
uint32_t lastSend = 0;
String rx;

void applyOutputs() {
  for (int i = 0; i < 8; i++) digitalWrite(RELAY_PINS[i], relay[i] ? HIGH : LOW);
  for (int i = 0; i < 2; i++) digitalWrite(LED_PINS[i], led[i] ? HIGH : LOW);
  analogWrite(PWM_PIN, pwm);
}

String buildStatus(bool withAnalog) {
  String s = "S X=";
  for (int i = 0; i < 12; i++) s += digitalRead(X_PINS[i]) ? '1' : '0';
  s += " R=";
  for (int i = 0; i < 8; i++) s += relay[i] ? '1' : '0';
  s += " L=";
  for (int i = 0; i < 2; i++) s += led[i] ? '1' : '0';
  s += " RUN="; s += digitalRead(RUN_PIN) ? '1' : '0';
  s += " P="; s += pwm;
  if (withAnalog) {
    s += " A=";
    for (int i = 0; i < 5; i++) { if (i) s += ','; s += analogRead(A_PINS[i]); }
  }
  s += " U=";
  for (int i = 0; i < 8; i++) s += digitalRead(U_PINS[i]) ? '1' : '0';
  return s;
}

void handle(const String &cmd) {
  if (cmd.length() == 0) return;
  char c = cmd[0];
  if ((c == 'R' || c == 'L') && cmd.length() >= 3) {
    int n = cmd[1] - '0';
    bool v = cmd[2] == '1';
    if (c == 'R' && n >= 0 && n < 8) relay[n] = v;
    if (c == 'L' && n >= 0 && n < 2) led[n] = v;
  } else if (c == 'P') {
    pwm = constrain(cmd.substring(1).toInt(), 0, 255);
  } else if (c == 'A') {
    for (int i = 0; i < 8; i++) relay[i] = false;
    for (int i = 0; i < 2; i++) led[i] = false;
    pwm = 0;
  }
  applyOutputs();
  lastStatus = "";   // force a status line after every command
}

void setup() {
  for (int i = 0; i < 12; i++) pinMode(X_PINS[i], INPUT);
  for (int i = 0; i < 8; i++) { pinMode(U_PINS[i], INPUT); }
  pinMode(RUN_PIN, INPUT);
  for (int i = 0; i < 8; i++) { pinMode(RELAY_PINS[i], OUTPUT); relay[i] = false; }
  for (int i = 0; i < 2; i++) { pinMode(LED_PINS[i], OUTPUT); led[i] = false; }
  analogReadResolution(12);
  applyOutputs();
  Serial.begin(9600);
  Serial.println("IOControl ready");
}

void loop() {
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n' || ch == '\r') { handle(rx); rx = ""; }
    else if (rx.length() < 16) rx += ch;
  }
  // Digital part decides "changed"; analog values ride along every 200 ms (they jitter a little).
  String key = buildStatus(false);
  if (key != lastStatus || millis() - lastSend >= 200) {
    Serial.println(buildStatus(true));
    lastStatus = key;
    lastSend = millis();
  }
  delay(10);
}
