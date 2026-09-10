class_name BigNum
extends RefCounted

var mantissa: float = 0.0
var exponent: int = 0

func _init(m: float = 0.0, e: int = 0) -> void:
	mantissa = m
	exponent = e
	_normalize()

static func from_float(value: float) -> BigNum:
	if value == 0.0:
		return BigNum.new()
	var e := int(floor(log(abs(value)) / log(10.0)))
	return BigNum.new(value / pow(10.0, e), e)

static func from_log10(log_value: float) -> BigNum:
	if is_inf(log_value) and log_value < 0.0:
		return BigNum.new()
	var e := int(floor(log_value))
	var m := pow(10.0, log_value - float(e))
	return BigNum.new(m, e)

static func from_dict(data: Dictionary) -> BigNum:
	return BigNum.new(float(data.get("m", 0.0)), int(data.get("e", 0)))

func to_dict() -> Dictionary:
	return {"m": mantissa, "e": exponent}

func clone() -> BigNum:
	return BigNum.new(mantissa, exponent)

func is_zero() -> bool:
	return mantissa == 0.0

func _normalize() -> void:
	if mantissa == 0.0 or is_nan(mantissa):
		mantissa = 0.0
		exponent = 0
		return
	var sign_value := -1.0 if mantissa < 0.0 else 1.0
	mantissa = abs(mantissa)
	while mantissa >= 10.0:
		mantissa /= 10.0
		exponent += 1
	while mantissa < 1.0:
		mantissa *= 10.0
		exponent -= 1
	mantissa *= sign_value

func multiplied_scalar(value: float) -> BigNum:
	var out := clone()
	out.mantissa *= value
	out._normalize()
	return out

func multiplied(other: BigNum) -> BigNum:
	return BigNum.new(mantissa * other.mantissa, exponent + other.exponent)

func added(other: BigNum) -> BigNum:
	if is_zero():
		return other.clone()
	if other.is_zero():
		return clone()
	var diff := exponent - other.exponent
	if diff > 16:
		return clone()
	if diff < -16:
		return other.clone()
	if diff >= 0:
		return BigNum.new(mantissa + other.mantissa * pow(10.0, -diff), exponent)
	return BigNum.new(mantissa * pow(10.0, diff) + other.mantissa, other.exponent)

func subtracted(other: BigNum) -> BigNum:
	if other.is_zero():
		return clone()
	if compare_to(other) <= 0:
		return BigNum.new()
	var diff := exponent - other.exponent
	if diff > 16:
		return clone()
	return BigNum.new(mantissa - other.mantissa * pow(10.0, -diff), exponent)

func compare_to(other: BigNum) -> int:
	if mantissa == other.mantissa and exponent == other.exponent:
		return 0
	if mantissa >= 0.0 and other.mantissa < 0.0:
		return 1
	if mantissa < 0.0 and other.mantissa >= 0.0:
		return -1
	if exponent != other.exponent:
		return 1 if exponent > other.exponent else -1
	return 1 if mantissa > other.mantissa else -1

func ratio_to(other: BigNum) -> float:
	if other.is_zero():
		return 1.0
	var diff := exponent - other.exponent
	if diff > 8:
		return 1.0
	if diff < -8:
		return 0.0
	return clamp((mantissa / other.mantissa) * pow(10.0, diff), 0.0, 1.0)

func short() -> String:
	if is_zero():
		return "0"
	if exponent < 6 and exponent > -3:
		var v := mantissa * pow(10.0, exponent)
		if abs(v) >= 1000.0:
			return "%.2fK" % (v / 1000.0)
		if abs(v) >= 100.0:
			return "%.0f" % v
		if abs(v) >= 10.0:
			return "%.1f" % v
		return "%.2f" % v
	var suffixes := {6:"M", 9:"B", 12:"T", 15:"Qa", 18:"Qi"}
	var group_e := int(floor(float(exponent) / 3.0)) * 3
	if suffixes.has(group_e):
		var scaled := mantissa * pow(10.0, exponent - group_e)
		return "%.2f%s" % [scaled, suffixes[group_e]]
	return "%.3fe%d" % [mantissa, exponent]
