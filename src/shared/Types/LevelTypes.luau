--!strict

local LevelTypes = {}

export type UnlockGrants = {
	--TBD
}

export type UnlockPayload = {
	level: number,
	title: string,
	description: string,
	grants: UnlockGrants,
}

export type XPProgressSnapshot = {
	level: number,
	xp: number,
	xpForNext: number,
	progress01: number,
}

export type XPChangeResult = {
	oldLevel: number,
	newLevel: number,
	oldXP: number,
	newXP: number,
	leveledUp: boolean,
	levelsGained: number,
}

export type LevelUpPayload = {
	oldLevel: number,
	newLevel: number,
	levelsGained: number,
	unlocks: {UnlockPayload},
	source: string?,
	meta: {[string]: any}?,
}

return LevelTypes
