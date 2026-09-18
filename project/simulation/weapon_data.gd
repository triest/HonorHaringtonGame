extends RefCounted
## WeaponData
##
## Data-driven weapon definition (ТЗ §8 Ship Database, §17 Weapons,
## §48 Data-Driven Design: "Do not hardcode ship characteristics into
## combat code."). One WeaponData resource describes a weapon TYPE;
## many mounts on many ships can share the same WeaponData.
##
## CANON note: energy weapon ranges/damage values in Honorverse are not
## given as clean simulation-ready numbers in the books (they're relative/
## narrative: "extreme range", "closing to energy range"). Concrete meters/
## damage numbers here are ASSUMPTION placeholders for gameplay, documented
## in ASSUMPTIONS.md, NOT presented as CANON.
class_name WeaponData

enum WeaponClass { ENERGY_LASER, ENERGY_GRASER }

var id: String = ""
var display_name: String = ""
var weapon_class: int = WeaponClass.ENERGY_LASER

## ASSUMPTION placeholders (see ASSUMPTIONS.md) — meant to be overridden by
## real ship/weapon data files once the data-driven ship database exists.
var max_range_m: float = 1_000_000.0  # 1000 km, placeholder
var damage_per_hit: float = 100.0      # abstract damage unit, placeholder
var recharge_time_s: float = 4.0       # "charging cycles" per CLOUD.md §2.2
