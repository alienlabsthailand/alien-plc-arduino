/*
  AlienPLC - helpers for the Alien PLC 20MR board.
  Pin names (X0..X13, Y0..Y7, LED1, LED2, RUN_SW, PWM_OUT, AIN0, AIN1, VIN_SENSE) are built into the
  board variant, so plain digitalRead(X0) / digitalWrite(Y0, HIGH) work without this library.
  This library adds PLC-style helpers.
*/
#pragma once
#include <Arduino.h>

#if !defined(ALIEN_PLC_20MR)
#error "AlienPLC: select Tools > Board > Alien Labs Boards > Alien PLC 20MR"
#endif

namespace AlienPLC {
  // Inputs in terminal order: X0..X7, X10..X13 (index 0..11)
  static const uint32_t INPUTS[12]  = { X0, X1, X2, X3, X4, X5, X6, X7, X10, X11, X12, X13 };
  // Relays Y0..Y7 (index 0..7)
  static const uint32_t OUTPUTS[8]  = { Y0, Y1, Y2, Y3, Y4, Y5, Y6, Y7 };

  // Configure all inputs, relays (off), LEDs and the RUN switch. Call in setup().
  inline void begin() {
    for (uint8_t i = 0; i < 12; i++) pinMode(INPUTS[i], INPUT);
    for (uint8_t i = 0; i < 8; i++)  { pinMode(OUTPUTS[i], OUTPUT); digitalWrite(OUTPUTS[i], LOW); }
    pinMode(LED1, OUTPUT); pinMode(LED2, OUTPUT);
    pinMode(RUN_SW, INPUT);
    analogReadResolution(12);
  }
  // true when the input terminal is active (shorted to the input 0V)
  inline bool input(uint8_t n)              { return n < 12 && digitalRead(INPUTS[n]) == LOW; }
  inline void output(uint8_t n, bool on)    { if (n < 8) digitalWrite(OUTPUTS[n], on ? HIGH : LOW); }
  inline bool outputState(uint8_t n)        { return n < 8 && digitalRead(OUTPUTS[n]) == HIGH; }
  inline void allOff()                      { for (uint8_t i = 0; i < 8; i++) digitalWrite(OUTPUTS[i], LOW); }
  // RUN/STOP switch
  inline bool isRun()                       { return digitalRead(RUN_SW) == HIGH; }
  // Analog: voltage at the A0/A1 terminal (estimated, ~1/3 divider), and supply voltage
  inline float analogVolts(uint8_t ch)      { return analogRead(ch ? AIN1 : AIN0) * 3.3f / 4095.0f * AIN_SCALE; }
  inline float supplyVolts()                { return analogRead(VIN_SENSE) * 3.3f / 4095.0f * VIN_SCALE; }
  // PWM on the expansion header (0..255)
  inline void pwm(uint8_t duty)             { analogWrite(PWM_OUT, duty); }

  // Rising-edge helper (like LDP in ladder): true once when the input becomes active
  class Edge {
  public:
    bool rising(bool now)  { bool r = now && !_last; _last = now; return r; }
  private:
    bool _last = false;
  };

  // Non-blocking timer (like a TON timer)
  class Timer {
  public:
    // returns true once 'ms' has elapsed while 'enable' stays true; resets when enable is false
    bool on(bool enable, uint32_t ms) {
      if (!enable) { _running = false; return false; }
      if (!_running) { _running = true; _start = millis(); }
      return millis() - _start >= ms;
    }
  private:
    bool _running = false;
    uint32_t _start = 0;
  };
}
