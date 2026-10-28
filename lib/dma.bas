Module Dma
' DMA of the PIC18F0x/1xQ41 (DS40002214G chapter 16; DS40002242F has the same chapter): four channels that move bytes
' between SFR/GPR addresses while the CPU runs. This step is the software-started copy; a transfer started by a
' peripheral's interrupt flag (SIRQ) is not in the module yet.
'
' All four channels share one set of registers, selected by DMASELECT = channel - 1 [16.12]. The module therefore
' must not run from a handler and from the main program at once, and it leaves DMASELECT on the channel it used last.
'
' A software start is EN = 1, then DGO = 1 [16.3.4.1.1]. With the source and destination sizes equal, the message ends
' when both counters reach zero and the hardware clears DGO [16.3.3], so DGO = 0 means the copy is finished. Both
' pointers increment by one after each byte (SMODE = DMODE = 01, SMR = 00: SFR/GPR space) [DMAnCON1, 16.13.3].
' Clearing EN stops a transfer for good and returns the channel's registers to their reset values [16.3.4.2.5, 16.9],
' so the module clears it before it sets a channel up.
'
' The system arbiter gives the DMA memory access only while PRLOCKED is set [7.1.1]; the module sets it with the
' sequence of Example 7-1 (interrupts off for the three writes) if it is clear. The priorities stay at their reset
' value of 7 for the main program, handlers and all DMA channels [Table 7-1], so the DMA uses cycles the CPU leaves free
' [7.2.1] and the CPU is not slowed. A program that changes DMAxPR itself should do so before the first DmaCopy.
' The data sheet shows no DMA erratum other than the vector numbers of Table 11-2 (DS80000901H 2.1), which this
' module does not use.
'
' The program keeps running during a copy: do not read the destination, or change the source, before DmaDone.
#if not _has(DMAnCON0)
#error "dma needs a part with DMA registers (PIC18-Q41)"
#endif
Dim IntEn As INTCON0.7
Dim PrLocked As PRLOCK.0
Dim DmaGo As DMAnCON0.5

' Number of DMA channels, 1..DmaChannels.
Public Const DmaChannels = 4

' Largest message, in bytes: the size registers are 12 bits [DMAnSSZ, DMAnDSZ].
Public Const DmaMaxBytes = 4095

Sub PickChannel(ByVal channel As Byte)
    DMASELECT = channel - 1
End Sub

Sub LockPriority()
    Dim ie As Byte
    If PrLocked = 0 Then
        ie = IntEn
        IntEn = 0
        PRLOCK = 85
        PRLOCK = 170
        PrLocked = 1
        If ie = 1 Then
            IntEn = 1
        End If
    End If
End Sub

' Copies `count` bytes from address `src` to address `dst` (use @x for a variable's address) on `channel`, 1..4, and
' returns at once. Returns 1 when the copy was started, 0 for a channel outside 1..4, a count of 0 or above
' DmaMaxBytes, a channel still copying or armed for a hardware trigger (DGO or SIRQEN set), or a priority lock that did not
' take. Source and destination are SFR/GPR addresses; they should not overlap. Nothing checks that `count` bytes fit the
' destination object: a count larger than the array overwrites whatever follows it.
Public Function DmaCopy(ByVal channel As Byte, ByVal src As Word, ByVal dst As Word, ByVal count As Word) As Byte
    Result = 0
    If channel >= 1 Then
        If channel <= DmaChannels Then
            If count >= 1 Then
                If count <= DmaMaxBytes Then
                    PickChannel(channel)
                    If (DMAnCON0 And 96) = 0 Then
                        DMAnCON0 = 0
                        DMAnSSAU = 0
                        DMAnSSAH = Byte(src >> 8)
                        DMAnSSAL = Byte(src)
                        DMAnDSAH = Byte(dst >> 8)
                        DMAnDSAL = Byte(dst)
                        DMAnSSZH = Byte(count >> 8)
                        DMAnSSZL = Byte(count)
                        DMAnDSZH = Byte(count >> 8)
                        DMAnDSZL = Byte(count)
                        DMAnCON1 = 66
                        LockPriority()
                        If PrLocked = 1 Then
                            DMAnCON0 = 128
                            DMAnCON0 = 160
                            Result = 1
                        End If
                    End If
                End If
            End If
        End If
    End If
End Function

' 1 when `channel` is not moving data (a finished copy, or a channel never started), 0 while a copy is in progress.
' A channel outside 1..4 reports 1.
Public Function DmaDone(ByVal channel As Byte) As Byte
    Result = 1
    If channel >= 1 Then
        If channel <= DmaChannels Then
            PickChannel(channel)
            If DmaGo = 1 Then
                Result = 0
            End If
        End If
    End If
End Function

' Stops `channel` and returns its registers to their reset values; a copy in progress is cut short.
Public Sub DmaStop(ByVal channel As Byte)
    If channel >= 1 Then
        If channel <= DmaChannels Then
            PickChannel(channel)
            DMAnCON0 = 0
        End If
    End If
End Sub
