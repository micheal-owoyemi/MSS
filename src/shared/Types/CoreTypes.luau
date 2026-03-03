--!strict

local CoreTypes = {}

export type UserId = number
export type Timestamp = number
export type Currency = number

export type Dictionary<T> = {[string]: T}

return CoreTypes
