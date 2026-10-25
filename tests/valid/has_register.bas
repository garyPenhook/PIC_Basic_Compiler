Program HasRegister
Device = 18F27Q10
Clock = 16

' _has(NAME) is true for a register the device description defines, in any letter case.
#if not(_has(ANSELB))
#error "the 18F27Q10 has ANSELB"
#endif
#if not(_has(portb) and _has(WPUC))
#error "register names are not case sensitive"
#endif
#if _has(NOSUCHREG)
#error "NOSUCHREG is not a register"
#endif

Include "gpio"

GpioAllDigital()
GpioPullUps(1, 2, 3)
GpioOpenDrain(0, 0, 4)
