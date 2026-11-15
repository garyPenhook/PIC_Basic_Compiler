' Timer0 interrupt blink
'
' Blinks an LED from the Timer0 overflow interrupt while the main loop stays free for other work.
' Shows the third way of using the timer module (manual, section 3, timer): the program writes its own
' Interrupt handler, the handler clears the flag with Timer0Ack (the hardware does not), and the call
' is wrapped in Save because module routines are not reentrant.
'
' Device:  PIC18F27Q10, 16 MHz from the internal oscillator.
' Connect: an LED and a series resistor (about 330 ohm) from RB0 to ground.
' Expect:  the LED changes state on every Timer0 overflow, about every 2 s ((244 + 1) * 32768 instruction
'          cycles at 4 MIPS); the main loop counts in `loops` meanwhile.
' Status:  built and run in basil-sim (the interrupt keeps firing and the main loop keeps running);
'          not yet run on a real chip.

Program TimerInterruptBlink
Device = 18F27Q10
Clock = 16
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, CSWEN = ON, WDTE = OFF, LVP = ON
Include "intosc"
Include "timer"

Dim led As PORTB.0
Dim loops As Word

Interrupt Tick()
    Save(0, Timer0Ack)
        Timer0Ack()             ' clear the flag first, or the handler is entered again at once
    Restore
    Toggle(led)
End Interrupt

ANSELB = 0                      ' RB0 digital
Output(led)
Timer0Start(15, 244)            ' the period of the manual's Timer0Start example
Timer0EnableInterrupt()
Enable(Tick)                    ' global interrupts on, with Tick as the handler

While True
    Inc(loops)                  ' the main program keeps running between interrupts
Wend
