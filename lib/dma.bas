Module Dma
' DMA of the PIC18F0x/1xQ41 (DS40002214G chapter 16; DS40002242F has the same chapter): four channels that move bytes
' between SFR/GPR addresses while the CPU runs. DmaCopy is the software-started copy; DmaOnTrigger arms a channel
' so that a peripheral's interrupt request (SIRQ) starts each message.
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
' A hardware trigger is sampled while SIRQEN = 1; each request starts a message, which ends when the smaller of the
' two counters reloads [16.3.3, 16.3.4.1.2]. A fixed side has a size of 1, so a memory-to-register feed moves one
' byte per request and the source pointer carries on from message to message. With DmaOnce the stop bit of the side
' that runs through the buffer (SSTP or DSTP) clears SIRQEN when that counter reloads, i.e. after `count` bytes
' [16.4.2], and DmaDone then reports 1. Trigger numbers are the vector numbers of Table 16-6 (DMAnSIRQ); the same
' table also lists the abort sources (DMAnAIRQ), selected by DmaAbortOn. An abort request soft-stops the channel: DGO,
' SIRQEN and AIRQEN are cleared, DMAxAIF is set, and a message in progress is cut after the access under way
' [16.3.4.2.2, 16.8.6, 16.8.7]. DmaDone then reports 1; DmaAborted tells it from a normal end.
'
' The program keeps running during a copy: do not read the destination, or change the source, before DmaDone.
#if not _has(DMAnCON0)
#error "dma needs a part with DMA registers (PIC18-Q41)"
#endif
Dim IntEn As INTCON0.7
Dim PrLocked As PRLOCK.0
Dim AirqEn As DMAnCON0.2
Dim Aif1 As PIR2.7
Dim Aif2 As PIR6.7
Dim Aif3 As PIR9.7
Dim Aif4 As PIR10.7

' Number of DMA channels, 1..DmaChannels.
Public Const DmaChannels = 4

' Largest message, in bytes: the size registers are 12 bits [DMAnSSZ, DMAnDSZ].
Public Const DmaMaxBytes = 4095

' DmaOnTrigger options, added together.
Public Const DmaFixedSrc = 1
Public Const DmaFixedDst = 2
Public Const DmaOnce = 4

' Trigger numbers for DmaOnTrigger, from Table 16-6. The part must have the peripheral.
Public Const DmaTrigIoc = 7
Public Const DmaTrigAdc = 10
Public Const DmaTrigSpi1Rx = 24
Public Const DmaTrigSpi1Tx = 25
Public Const DmaTrigTmr2 = 27
Public Const DmaTrigTmr1 = 28
Public Const DmaTrigTmr0 = 31
Public Const DmaTrigU1Rx = 32
Public Const DmaTrigU1Tx = 33
Public Const DmaTrigI2c1Rx = 56
Public Const DmaTrigI2c1Tx = 57
Public Const DmaTrigU2Rx = 64
Public Const DmaTrigU2Tx = 65

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

' As DmaCopy, but the source is program flash: `src` is a flash byte address (@table of a Const array gives one) and
' the destination is a SFR/GPR address. SMR = 01 selects the flash [DMAnCON1, 16.13.3], set up as in the example of
' 16.11. Data EEPROM is not offered: the data sheet does not say which DMAnSSA value addresses it. Returns at once, with
' the results of DmaCopy. Nothing checks that `count` bytes fit the destination object.
Public Function DmaCopyFlash(ByVal channel As Byte, ByVal src As LongWord, ByVal dst As Word, ByVal count As Word) As Byte
    Result = 0
    If channel >= 1 Then
        If channel <= DmaChannels Then
            If count >= 1 Then
                If count <= DmaMaxBytes Then
                    PickChannel(channel)
                    If (DMAnCON0 And 96) = 0 Then
                        DMAnCON0 = 0
                        DMAnSSAU = Byte(src >> 16)
                        DMAnSSAH = Byte(src >> 8)
                        DMAnSSAL = Byte(src)
                        DMAnDSAH = Byte(dst >> 8)
                        DMAnDSAL = Byte(dst)
                        DMAnSSZH = Byte(count >> 8)
                        DMAnSSZL = Byte(count)
                        DMAnDSZH = Byte(count >> 8)
                        DMAnDSZL = Byte(count)
                        DMAnCON1 = 74
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

' Arms `channel` so that each request from `trigger` (DmaTrig..., 1..93, a reserved number of Table 16-6 is not
' checked) starts a message, and returns at once. Returns 1 when armed, 0 for the refusals of DmaCopy or a trigger
' outside 1..93. `options` is DmaFixedSrc (the source is one register such as a receive buffer: its size is 1 and the
' pointer stays), DmaFixedDst (the destination is one register such as a transmit buffer), DmaOnce (stop after
' `count` bytes); the other side is a buffer of `count` bytes whose pointer increments. With both sides fixed `count`
' is ignored and DmaOnce stops after the first byte. Without DmaOnce the channel carries on round the buffer for as
' long as requests come. With a level trigger (UART, SPI, I2C) the request stays up while the peripheral wants data:
' use DmaOnce, or the channel keeps running past the end of the buffer.
Public Function DmaOnTrigger(ByVal channel As Byte, ByVal trigger As Byte, ByVal src As Word, ByVal dst As Word, ByVal count As Word, ByVal options As Byte) As Byte
    Dim con1 As Byte
    Dim ssz As Word
    Dim dsz As Word
    Result = 0
    If channel >= 1 Then
        If channel <= DmaChannels Then
            If trigger >= 1 Then
                If trigger <= 93 Then
                    If count >= 1 Then
                        If count <= DmaMaxBytes Then
                            PickChannel(channel)
                            If (DMAnCON0 And 96) = 0 Then
                                con1 = 0
                                ssz = 1
                                dsz = 1
                                If (options And 1) = 0 Then
                                    con1 = 2
                                    ssz = count
                                End If
                                If (options And 2) = 0 Then
                                    con1 = con1 + 64
                                    dsz = count
                                End If
                                If (options And 4) <> 0 Then
                                    If (options And 1) = 0 Or (options And 2) <> 0 Then
                                        con1 = con1 + 1
                                    Else
                                        con1 = con1 + 32
                                    End If
                                End If
                                DMAnCON0 = 0
                                DMAnSSAU = 0
                                DMAnSSAH = Byte(src >> 8)
                                DMAnSSAL = Byte(src)
                                DMAnDSAH = Byte(dst >> 8)
                                DMAnDSAL = Byte(dst)
                                DMAnSSZH = Byte(ssz >> 8)
                                DMAnSSZL = Byte(ssz)
                                DMAnDSZH = Byte(dsz >> 8)
                                DMAnDSZL = Byte(dsz)
                                DMAnCON1 = con1
                                DMAnSIRQ = trigger
                                LockPriority()
                                If PrLocked = 1 Then
                                    DMAnCON0 = 192
                                    Result = 1
                                End If
                            End If
                        End If
                    End If
                End If
            End If
        End If
    End If
End Function

' Makes requests from `trigger` (the numbers of DmaOnTrigger, 1..93) abort `channel`. Call it after DmaOnTrigger or
' DmaCopy has armed the channel: clearing EN returns DMAnAIRQ to its reset value, so a stopped channel refuses.
' Returns 1 when set, 0 for a channel outside 1..4, a trigger outside 1..93 or a channel that is not enabled (EN clear).
' The abort is one-shot: the hardware clears AIRQEN when it fires, so call DmaAbortOn again after DmaAborted.
Public Function DmaAbortOn(ByVal channel As Byte, ByVal trigger As Byte) As Byte
    Result = 0
    If channel >= 1 Then
        If channel <= DmaChannels Then
            If trigger >= 1 Then
                If trigger <= 93 Then
                    PickChannel(channel)
                    If (DMAnCON0 And 128) <> 0 Then
                        DMAnAIRQ = trigger
                        AirqEn = 1
                        Result = 1
                    End If
                End If
            End If
        End If
    End If
End Function

' 1 when `channel` has been aborted since the last call (its DMAxAIF flag was set), and clears the flag; else 0.
' A channel outside 1..4 reports 0. After an abort the channel is stopped but keeps its set-up: DmaStop, then arm it again.
Public Function DmaAborted(ByVal channel As Byte) As Byte
    Result = 0
    If channel = 1 Then
        Result = Aif1
        Aif1 = 0
    ElseIf channel = 2 Then
        Result = Aif2
        Aif2 = 0
    ElseIf channel = 3 Then
        Result = Aif3
        Aif3 = 0
    ElseIf channel = 4 Then
        Result = Aif4
        Aif4 = 0
    End If
End Function

' 1 when `channel` is not moving data and not armed for a trigger (a finished copy, a DmaOnce feed that has run its
' course, or a channel never started), 0 while a copy is in progress or triggers are still being accepted.
' A channel outside 1..4 reports 1.
Public Function DmaDone(ByVal channel As Byte) As Byte
    Result = 1
    If channel >= 1 Then
        If channel <= DmaChannels Then
            PickChannel(channel)
            If (DMAnCON0 And 96) <> 0 Then
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
