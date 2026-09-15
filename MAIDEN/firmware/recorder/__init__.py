"""MAIDEN station Ch. 10 recorder (SBC side).

Desk-built core (maiden40): rings, min-RTC merge writer, UART record
demux per firmware/recorder/PROTOCOL.md, CLI. Real bench I/O (camera,
serial port) lands in maiden41-42; every source here can be driven by a
fake in tests, and nothing pretends hardware ran when it didn't.

Runs on the station SBC with the `maiden` package installed (the
recorder imports maiden.ch10 / maiden.tmats / maiden.timebase — one
definition of every interface, per D4).
"""
