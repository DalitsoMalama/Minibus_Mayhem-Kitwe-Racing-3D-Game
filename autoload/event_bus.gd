extends Node
## Global signal hub. Systems emit here instead of calling each other directly,
## so the HUD, audio, economy and call boy can react without tight coupling.

signal passenger_boarded(bus: Node, stop: Node, fare: int)
signal passenger_alighted(bus: Node, stop: Node)
signal bark(text: String)
signal fined(bus: Node, amount: int, reason: String)
signal refuelled(bus: Node, litres: float, cost: int)
signal race_finished(player_earnings: int)
