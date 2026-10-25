Module Gpio
' Port-level helpers for parts with the ANSELx / WPUx / ODCONx port registers (PIC18F27/47Q10,
' DS40002043F chapter 16; PIC16F17126/46, DS40002343F section 16.14). Each register is written only
' when the device description defines it (`#if _has(REG)`), so a part with fewer ports, or no
' open-drain register, compiles; the mask of a port the part lacks is ignored.
' Single pins need no library: `Input(p)`, `Output(p)`, `High(p)`, `Low(p)`, `Toggle(p)` are
' compiler intrinsics and `Dim led As PORTB.0` names a pin.

' Makes every pin of every port a digital pin. ANSELx resets to 1 (analog, input buffer
' off), so a pin read as digital stays 0 until this runs [Q10 p.247, 16F171xx 16.14.4].
Public Sub GpioAllDigital()
#if _has(ANSELA)
    ANSELA = 0
#endif
#if _has(ANSELB)
    ANSELB = 0
#endif
#if _has(ANSELC)
    ANSELC = 0
#endif
End Sub

' Weak pull-ups: a 1 bit enables the pull-up of that pin [Q10 p.251, 16F171xx 16.14.5].
Public Sub GpioPullUps(ByVal maskA As Byte, ByVal maskB As Byte, ByVal maskC As Byte)
#if _has(WPUA)
    WPUA = maskA
#endif
#if _has(WPUB)
    WPUB = maskB
#endif
#if _has(WPUC)
    WPUC = maskC
#endif
End Sub

' Open-drain outputs: a 1 bit makes the pin drive low only [Q10 p.256, 16F171xx 16.14.8].
Public Sub GpioOpenDrain(ByVal maskA As Byte, ByVal maskB As Byte, ByVal maskC As Byte)
#if _has(ODCONA)
    ODCONA = maskA
#endif
#if _has(ODCONB)
    ODCONB = maskB
#endif
#if _has(ODCONC)
    ODCONC = maskC
#endif
End Sub
