' Hardware test for the `softserial` module: an echo on RB1 (TX) and RB2 (RX), 9600 baud, 8N1, 64 MHz, PIC18F27Q10.
' Wire a USB-serial adapter (3.3 V or 5 V logic to match the part): adapter RX to RB1, adapter TX to RB2, grounds together.
' Open a terminal on the adapter at 9600 8N1 and check, in this order:
'   1. "softserial ready" appears at start-up.
'   2. Every key you type comes straight back (the echo), at 9600, then change SoftInit to 19200, 38400 and 115200 and the
'      terminal with it: 64 MHz should work at all four.
'   3. Paste or send a long file (a few KB) from the terminal: the echo must be the same text. A byte lost between two
'      calls is expected when the sender has no gap between characters (this module polls, it does not buffer): at
'      9600 add a one-character-time delay between characters in the terminal program, or send in lines of up to 20 bytes
'      with 5 ms between lines. Any "?" in the echo is a framing error (-2): a stop bit that was not high, so wrong baud
'      rate or noise, not a lost byte.
'   4. Set the terminal to a wrong baud rate (for example 9600 against 19200 in the program): the echo must be "?"s
'      and garbage, not a hang.
' Scope or logic analyser (optional): the bit time of an echoed "U" ($55) on RB1 should be 104.2 us at 9600 and
' the edges within 2 % at every rate above. To stress it, a sender 3 % fast and 3 % slow must still echo correctly.
Program SoftEcho
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "softserial"
Dim c As Integer
Dim ok As Boolean
ok = SoftInit(9, 10, 9600, False)
If Not ok Then
    Terminate()
End If
SoftWrite("softserial ready")
SoftNewLine()
While True
    c = SoftReadByte(1000)
    If c >= 0 Then
        SoftWriteByte(Byte(c))
    ElseIf c = -2 Then
        SoftWriteByte(63)
    End If
Wend
