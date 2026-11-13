Module Onewire
Include "pinio"
' 1-Wire master (standard speed) on any one pin (0..23 as in `Pinio`: RA0 = 0, RB0 = 8, RC0 = 16): a reset with presence
' detect, bit and byte transfer, the ROM search and the CRC8 of the family (DS18B20, DS2401, DS2413 ...). The line is open
' drain: the pin is pulled low as an output and let go as an input, never driven high, so it needs an external pull-up
' (4.7 k to 5 k) and several devices share it.
'
' Slots are timed in microseconds from `Clock` (a constant `DelayUs`); the pin switching and the call cost a few cycles
' that the delays make up for (the constants below, measured with `scripts/test_onewire.py`). A bit slot is 70 us, a reset
' about 1 ms, a byte about 0.6 ms. Each bit slot runs with the global interrupt enable cleared and puts it back as it
' was: an interrupt inside a slot would stretch a low time past what a device accepts. Between slots interrupts run.
' The slowest Clock is 16 MHz on a PIC18 (4 MIPS) and 32 MHz on a PIC16: below that the pin switch alone is too long
' a part of the 3 us read pulse.
'
' Timing (us, standard speed): reset low 490, presence sampled 70 after the release, the slot ends 480 after it. Write 1: low
' 3, then release. Write 0: low 62, then release. Read: low 3, line sampled 10 after the falling edge (a device holds its
' bit for 15 us). Each slot is 75 to 79 us measured, which the bus allows (60 to 120). The interrupt enable is also held
' low from the release of a reset to its presence sample. A failed OwInit leaves the module without a pin.

#if _core = "pic18"
#if _Clock < 16
#error "onewire needs a Clock of at least 16 MHz on a PIC18 (at 4 MIPS the pin switch and call are most of a 3 us read pulse)"
#endif
' Instruction cycles from the TRIS write that pulls the line low to the first delay, and from the end of a delay to the
' TRIS write that lets it go, with the call and return of the pin routines.
Private Const SwCyc = 16
#else
#if _Clock < 32
#error "onewire needs a Clock of at least 32 MHz on a PIC16"
#endif
Private Const SwCyc = 16
#endif

' Microseconds that `SwCyc` instruction cycles take, rounded, at the build's Clock (4 clocks to a cycle).
Private Const SwUs = Word((SwCyc * 4 + _Clock / 2) / _Clock)

' The global interrupt enable: bit 7 of INTCON (GIE, or GIE/GIEH with priorities), of INTCON0 on the PIC18-Q41
' [DS40002043F 15.13.1, DS40002343F 12.10.1, DS40002214G 11.13.1].
#if _has(INTCON0)
Private Dim Gie As INTCON0.7
#else
Private Dim Gie As INTCON.7
#endif

Private Dim owPin As Byte = 255

' ROM search state: the 64-bit ROM code of the device found (family code first, CRC last), the last position where the
' search took the 0 branch at a fork, and whether the last device has been found.
Public Dim OwRom(8) As Byte
Private Dim lastFork As Byte
Private Dim lastDone As Boolean

' Sets the pin (the line idles high through the pull-up); call it first. A pin above 23 or one the part lacks is
' refused: False.
Public Function OwInit(ByVal pin As Byte) As Boolean
    owPin = 255
    lastFork = 0
    lastDone = False
    Result = False
    If Pinio.PinOk(pin) Then
        owPin = pin
        Pinio.PinSet(pin, False)
        Pinio.BindOd(pin)
        Pinio.PinInput(pin)
        Result = True
    End If
End Function

' Reset pulse; True when a device answers with a presence pulse. A line that is low before the pulse (no pull-up, a short)
' is False.
Public Function OwReset() As Boolean
    Dim g As Boolean
    Result = False
    If Not Pinio.PinOk(owPin) Then
        Exit
    End If
    Pinio.BindOd(owPin)
    If Not Pinio.OdRead() Then
        Exit
    End If
    Pinio.OdLow()
    DelayUs(490 - SwUs)
    g = Gie = 1
    Gie = 0
    Pinio.OdRelease()
    DelayUs(70 - SwUs)
    Result = Not Pinio.OdRead()
    If g Then
        Gie = 1
    End If
    DelayUs(410 - SwUs)
End Function

' One bit slot: writes `b`, and returns the line as read in the slot (a device's answer to a read slot, the
' written bit itself when nobody holds the line low). A read slot is a write of 1 sampled early.
Private Function Slot(ByVal b As Boolean) As Boolean
    Dim g As Boolean
    g = Gie = 1
    Gie = 0
    Pinio.BindOd(owPin)
    Pinio.OdLow()
    If b Then
        DelayUs(3 - SwUs)
        Pinio.OdRelease()
        DelayUs(7 - SwUs)
        Result = Pinio.OdRead()
        DelayUs(60 - SwUs)
    Else
        DelayUs(62 - SwUs)
        Pinio.OdRelease()
        DelayUs(10 - SwUs)
        Result = False
    End If
    If g Then
        Gie = 1
    End If
End Function

' Writes one bit.
Public Sub OwWriteBit(ByVal b As Boolean)
    Dim x As Boolean
    If Pinio.PinOk(owPin) Then
        x = Slot(b)
    End If
End Sub

' Reads one bit.
Public Function OwReadBit() As Boolean
    Result = False
    If Pinio.PinOk(owPin) Then
        Result = Slot(True)
    End If
End Function

' Writes a byte, least significant bit first.
Public Sub OwWriteByte(ByVal b As Byte)
    Dim i As Byte
    For i = 0 To 7
        OwWriteBit((b And 1) <> 0)
        b = b >> 1
    Next
End Sub

' Reads a byte, least significant bit first.
Public Function OwReadByte() As Byte
    Dim i As Byte
    Result = 0
    For i = 0 To 7
        Result = Result >> 1
        If OwReadBit() Then
            Result = Result Or $80
        End If
    Next
End Function

' CRC8 of the 1-Wire family (x^8 + x^5 + x^4 + 1, shifted right, start value 0), one byte added to `crc`. Feeding the 8
' bytes of a ROM code, or the 9 bytes of a scratchpad, ends at 0 when they are intact.
Public Function OwCrc8(ByVal crc As Byte, ByVal b As Byte) As Byte
    Dim i As Byte
    crc = crc Xor b
    For i = 0 To 7
        If (crc And 1) <> 0 Then
            crc = (crc >> 1) Xor $8C
        Else
            crc = crc >> 1
        End If
    Next
    Result = crc
End Function

' The next device's ROM code in `OwRom`; False when there is none (the search is over: the next call starts again) or the
' code read is damaged. The devices are visited in order of their codes. A device added or taken off the line during a
' search can make it miss or repeat one.
Public Function OwSearchNext() As Boolean
    Dim pos As Byte
    Dim idx As Byte
    Dim mask As Byte
    Dim idBit As Boolean
    Dim cmpBit As Boolean
    Dim dir As Boolean
    Dim zero As Byte
    Dim crc As Byte
    Result = False
    If lastDone Then
        lastDone = False
        lastFork = 0
        Exit
    End If
    If Not OwReset() Then
        lastFork = 0
        Exit
    End If
    OwWriteByte($F0)
    zero = 0
    idx = 0
    mask = 1
    For pos = 1 To 64
        idBit = OwReadBit()
        cmpBit = OwReadBit()
        If idBit And cmpBit Then
            lastFork = 0
            Exit
        End If
        If idBit <> cmpBit Then
            dir = idBit
        Else
            If pos < lastFork Then
                dir = (OwRom(idx) And mask) <> 0
            Else
                dir = pos = lastFork
            End If
            If Not dir Then
                zero = pos
            End If
        End If
        If dir Then
            OwRom(idx) = OwRom(idx) Or mask
        Else
            OwRom(idx) = OwRom(idx) And (mask Xor 255)
        End If
        OwWriteBit(dir)
        mask = mask << 1
        If mask = 0 Then
            mask = 1
            Inc(idx)
        End If
    Next
    crc = 0
    For idx = 0 To 7
        crc = OwCrc8(crc, OwRom(idx))
    Next
    lastFork = zero
    lastDone = zero = 0
    Result = crc = 0
End Function

' Starts a ROM search: the first device's code in `OwRom`. False when no device answers or the code read is damaged
' (its CRC does not come out 0). Call `OwSearchNext` for the others.
Public Function OwSearchFirst() As Boolean
    lastFork = 0
    lastDone = False
    Result = OwSearchNext()
End Function

' Addresses one device: Match ROM and its code from `OwRom`. Reset the line first (`OwReset`).
Public Sub OwSelect()
    Dim i As Byte
    OwWriteByte($55)
    For i = 0 To 7
        OwWriteByte(OwRom(i))
    Next
End Sub

' Addresses every device at once: Skip ROM. Reset the line first. Only for a command with one device on the line, or a
' command none of them answers (Convert T to all DS18B20 at once).
Public Sub OwSkip()
    OwWriteByte($CC)
End Sub
