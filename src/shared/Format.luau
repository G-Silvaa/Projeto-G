--!strict

-- Formatação de números para exibir (servidor e cliente).

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 950 -> "950", 1500 -> "1.5K", 2340000 -> "2.3M", 4100000000 -> "4.1B".
function Format.number(value: number): string
	if value ~= value then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local absolute = math.abs(value)
	if absolute < 1000 then
		return sign .. tostring(math.floor(absolute))
	end

	local tier = 1
	while absolute >= 1000 and tier < #SUFFIXES do
		absolute /= 1000
		tier += 1
	end
	-- Uma casa decimal, sem ".0" sobrando (e sem arredondar 999.95 para "1000.0").
	local rounded = math.floor(absolute * 10) / 10
	local text = if rounded % 1 == 0 then string.format("%d", rounded) else string.format("%.1f", rounded)
	return sign .. text .. SUFFIXES[tier]
end

return Format
