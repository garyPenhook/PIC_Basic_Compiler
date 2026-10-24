Module Gpio
' Port-level helpers for the PIC18F27/47Q10 (DS40002043F, chapter 16 "I/O Ports").
' Single pins need no library: `Input(p)`, `Output(p)`, `High(p)`, `Low(p)`, `Toggle(p)` are
' compiler intrinsics and `Dim led As PORTB.0` names a pin. Ports A, B and C exist on the
' 28-pin parts.

' Makes every pin of ports A, B and C a digital pin. ANSELx resets to 1 (analog, input buffer
' off), so a pin read as digital stays 0 until this runs [p.247].
Public Sub GpioAllDigital()
    ANSELA = 0
    ANSELB = 0
    ANSELC = 0
End Sub

' Weak pull-ups: a 1 bit enables the pull-up of that pin [p.251].
Public Sub GpioPullUps(ByVal maskA As Byte, ByVal maskB As Byte, ByVal maskC As Byte)
    WPUA = maskA
    WPUB = maskB
    WPUC = maskC
End Sub

' Open-drain outputs: a 1 bit makes the pin drive low only [p.256].
Public Sub GpioOpenDrain(ByVal maskA As Byte, ByVal maskB As Byte, ByVal maskC As Byte)
    ODCONA = maskA
    ODCONB = maskB
    ODCONC = maskC
End Sub
