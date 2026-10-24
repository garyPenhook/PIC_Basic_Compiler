Module Quiet
#ifdef DBG
#error DBG must not leak from the including file
#endif
Public Dim q As Byte
