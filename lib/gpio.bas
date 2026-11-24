Module Gpio
' Port-level helpers for parts with the ANSELx / WPUx / ODCONx port registers (PIC18F27/47Q10,
' DS40002043F chapter 16; PIC16F17126/46, DS40002343F section 16.14; PIC16F18056/76, DS40002325C chapter 16; PIC16F153xx, DS40001866E chapter 12). Each register is written only
' when the device description defines it (`#if _has(REG)`), so a part with fewer ports, or no
' open-drain register, compiles; the mask of a port the part lacks is ignored. GpioAllDigital also clears ANSELD and
' ANSELE on the 40-pin PIC16F18076 and ANSELF on the PIC16F15385/86 (the only parts with port F); the mask routines below cover ports A, B and C only.
' Single pins need no library: `Input(p)`, `Output(p)`, `High(p)`, `Low(p)`, `Toggle(p)` are
' compiler intrinsics and `Dim led As PORTB.0` names a pin.
'
' PIC18(L)F2x/4xK22 (DS40001412H chapter 10; chosen with `_has(INTCON2.nRBPU)`): ANSELA..ANSELE as above (ANSELD and ANSELE on the
' 40/44-pin parts only, p.149-151), but weak pull-ups exist on port B only: WPUB (reset FFh, p.152) selects the pins and they work only
' while INTCON2.RBPU is 0 (p.110). GpioPullUps writes WPUB and clears RBPU when maskB has a pin, sets it when maskB is 0; maskA and
' maskC are ignored (the RE3 pull-up is WPUE3, TRISE bit 7, p.151). The part has no open-drain register: GpioOpenDrain does nothing there
' (Pinio.PinDriveLow and PinRelease emulate it).

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
#if _has(ANSELD)
    ANSELD = 0
#endif
#if _has(ANSELE)
    ANSELE = 0
#endif
#if _has(ANSELF)
    ANSELF = 0
#endif
End Sub

' dsPIC33CK64MC105 (DS70005399D section 8.3; chosen with `_has(CNPUA)`): the ports are 16 bits wide, so the masks of GpioPullUps and GpioOpenDrain are Words (a Byte argument widens) and port D, which has four pins (RD1, RD8, RD10, RD13),
' has its own pair GpioPullUpsD and GpioOpenDriveD. The pull-up is CNPUx [Register 8-6 p.105] and the open-drain output ODCx [Register 8-5 p.104]; a mask bit of a pin the port lacks is not implemented and is ignored. Pull-ups only work
' on a pin that is a digital input (GpioAllDigital); the pull-down CNPDx is not offered.
#if _has(CNPUA)
Public Sub GpioPullUps(ByVal maskA As Word, ByVal maskB As Word, ByVal maskC As Word)
    CNPUA = maskA
    CNPUB = maskB
    CNPUC = maskC
End Sub

Public Sub GpioPullUpsD(ByVal maskD As Word)
    CNPUD = maskD
End Sub

Public Sub GpioOpenDrain(ByVal maskA As Word, ByVal maskB As Word, ByVal maskC As Word)
    ODCA = maskA
    ODCB = maskB
    ODCC = maskC
End Sub

Public Sub GpioOpenDriveD(ByVal maskD As Word)
    ODCD = maskD
End Sub
#else
' Weak pull-ups: a 1 bit enables the pull-up of that pin [Q10 p.251, 16F171xx 16.14.5].
Public Sub GpioPullUps(ByVal maskA As Byte, ByVal maskB As Byte, ByVal maskC As Byte)
#if _has(WPUA)
    WPUA = maskA
#endif
#if _has(WPUB)
    WPUB = maskB
#endif
#if _has(INTCON2.nRBPU)
    INTCON2.nRBPU = Bit(maskB = 0)
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
#endif
