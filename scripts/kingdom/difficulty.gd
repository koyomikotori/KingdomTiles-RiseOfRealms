class_name Difficulty
extends RefCounted
## The difficulty picked for a new game (GDD §15, M14h). It sizes every enemy unit (clan armies,
## invasions, soldiers lent to them, bandits) against a standard squad of the player, and on
## Legendary gives clan officers more stars. Legendary opens after winning on Normal or Hard.

enum Level { EASY, NORMAL, HARD, LEGENDARY }

const NAMES: Array[String] = ["Dễ", "Bình thường", "Khó", "Huyền thoại"]
## Soldiers in each enemy unit (and in each clan's army) against the standard squad size.
const ENEMY_SCALE: Array[float] = [0.75, 1.0, 1.5, 2.0]
const DESCRIPTIONS: Array[String] = [
	"Quân địch mỗi đơn vị chỉ bằng 75% đơn vị tiêu chuẩn của bạn.",
	"Quân địch mỗi đơn vị bằng 100% đơn vị tiêu chuẩn của bạn.",
	"Quân địch mỗi đơn vị bằng 150% đơn vị tiêu chuẩn của bạn.",
	"Quân địch mỗi đơn vị bằng 200%; tướng và mưu sĩ gia tộc yếu và vừa +1 sao.",
]
## Legendary: extra stars for the officers of weak / medium clans (strong ones already have 5–6).
const LEGENDARY_EXTRA_STARS: Dictionary[int, int] = {Wars.Tier.WEAK: 1, Wars.Tier.MEDIUM: 1}


static func enemy_scale(level: int) -> float:
	return ENEMY_SCALE[clampi(level, 0, ENEMY_SCALE.size() - 1)]


static func extra_stars(level: int, tier: int) -> int:
	return LEGENDARY_EXTRA_STARS.get(tier, 0) if level == Level.LEGENDARY else 0


## Winning on this level opens Legendary for later games.
static func unlocks_legendary(level: int) -> bool:
	return level >= Level.NORMAL
