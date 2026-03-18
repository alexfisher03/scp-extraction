--!strict

local RaidResult = {}

RaidResult.Status = {
	EXTRACTED = "EXTRACTED",
	KIA = "KIA",
	MIA = "MIA",
}

function RaidResult.isValidStatus(status: any): boolean
	return status == RaidResult.Status.EXTRACTED
		or status == RaidResult.Status.KIA
		or status == RaidResult.Status.MIA
end

return RaidResult
