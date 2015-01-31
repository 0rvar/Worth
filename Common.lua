local addon, ns = ...
local _G = _G

local unpack, pairs, ipairs, table, math = unpack, pairs, ipairs, table, math
local next, string = next, string
local IsSpellKnown = IsSpellKnown
local C_Garrison = C_Garrison
local GetItemInfo = GetItemInfo
local GetCoinTextureString = GetCoinTextureString
local UIParent = UIParent
local ITEM_SOULBOUND = ITEM_SOULBOUND

local Debug = nil
if tekDebug then
  local dbf = tekDebug:GetFrame(addon)
  Debug = function(...)
    dbf:AddMessage(string.join(", ", ...))
  end
end
ns.Debug = Debug

ns.C = LibStub('LibColors-1.0').color

ns.GetShortCoinString = function(value)
  if value > 100*100 then
    return GetCoinTextureString(math.floor(value/100/100)*100*100)
  elseif value > 100 then
    return GetCoinTextureString(math.floor(value/100)*100)
  else
    return GetCoinTextureString(value)
  end
end

ns.GetDiffCoinString = function(value)
  local base = ns.GetShortCoinString(math.abs(value))
  if value < 0 then
    return ns.C("red", "-"..base)
  elseif value > 0 then
    return ns.C("green", "+"..base)
  else
    return "±0"
  end
end

ns.GetItemValue = function(id, isSoulbound, de_capability)
  local equivItems = ns.EquivItems(id)
  if equivItems then
    local sum = 0
    for _,item in ipairs(equivItems) do
      sum = sum + ns.GetItemValue(item.id)*item.count
    end
    return sum, "Invested"
  end

  local _, link, _, _, _, _, _,
        _, _, _, vendor_price = GetItemInfo(id)
  local value = vendor_price or 0

  if isSoulbound and ns.CanDisenchant(de_capability) then
    local disenchantValue = ns.GetDisenchantValue(link, de_capability)
    if disenchantValue > value then
      return disenchantValue, "Disenchant"
    elseif disenchantValue ~= 0 then
    end
  elseif _G.AucAdvanced then
    local market, seen = _G.AucAdvanced.API.GetMarketValue(link)
    if market and seen > 0 then
      return market, "AH"
    end
  end

  return value, "Vendor"
end

-- For soulbound items
local price_equivalence = {
  -- 50x Primal Sprit -> 1x Savage Blood
  [120945] = {{ id = 118472, count = 1.0/50.0 }},
  -- 10x Truesteel Ingot <- 20x True Iron Ore, 10x Blackrock Ore
  [108257] = {{ id = 109119, count = 2 }, { id = 109118, count = 1 }},
  -- 10x Taladite Crystal <- 10x True Iron Ore, 20x Blackrock Ore
  [170832] = {{ id = 109119, count = 1 }, { id = 109118, count = 2 }},
  -- 10x War Paints <- 10x Cerulean Pigment
  [112377] = {{ id = 114931, count = 1 }},
  -- 10x Hexweave Cloth <- 20x Sumtuous Fur, 10x Gorgond Flytrap
  [170832] = {{ id = 111557, count = 2 }, { id = 109126, count = 1 }},
  -- 10x Gearspring Parts <- 10x True Iron Ore, 10x Blackrock Ore
  [111366] = {{ id = 109119, count = 1 }, { id = 109118, count = 1 }},
  -- 10x Burnished Leather <- 20x Raw Beast Hide, 10x Gorgond Flytrap
  [110611] = {{ id = 110609, count = 2}, { id = 109126, count = 1}}
}
ns.EquivItems = function(id)
  return price_equivalence[id]
end


ns.GetDisenchantValue = function(link, capability)
  if not _G.Enchantrix then
    return 0
  end
  local data = _G.Enchantrix.Storage.GetItemDisenchants(link)
  if not data then
    return 0
  end

  local lines

  local total = data.total
  local totalFive = 0
  local totalHSP, totalMed, totalMkt, totalFive = 0,0,0,0
  local totalNumber, totalQuantity
  local allFixed = true

  if (total and total[1] > 0) then
    totalNumber, totalQuantity = unpack(total)
    for result, resData in pairs(data) do
      if (result ~= "total") then
        if (not lines) then lines = {} end

        local resNumber, resQuantity = unpack(resData)
        local style, extra = _G.Enchantrix.Util.GetPricingModel()
        local hsp, med, mkt, five, fix = _G.Enchantrix.Util.GetReagentPrice(result, extra)
        local resProb, resCount = resNumber/totalNumber, resQuantity/resNumber
        local resYield = resProb * resCount;  -- == resQuantity / totalNumber;
        local resHSP, resMed, resMkt, resFive, resFix = (hsp or 0)*resYield, (med or 0)*resYield, (mkt or 0)*resYield, (five or 0)*resYield, (fix or 0)*resYield
        if (fix) then
          resHSP, resMed, resMkt, resFive = resFix,resFix,resFix,resFix
        else
          allFixed = false
        end
        totalHSP = totalHSP + resHSP
        totalMed = totalMed + resMed
        totalMkt = totalMkt + resMkt
        totalFive = totalFive + resFive
      end
    end
  end
  return totalFive * ns.GetDisenchantFactor(capability)
end

ns.GetDisenchantFactor = function(capability)
  if capability == "FULL" then
    return 1
  elseif capability == "GARRISON" then
    return 0.3 -- Seems to be about right for DEing epics at level 3
  end
  return 0
end

local DISENCHANTING = 13262
ns.GetDECapability = function()
  if IsSpellKnown(DISENCHANTING) then
    return "FULL"
  end
  for _, building in next, C_Garrison.GetBuildings() do
    local buildingID = building.buildingID
    if buildingID == 93 or buildingID == 125 or buildingID == 126 then
      return "GARRISON"
    end
  end
  return "NONE"
end

ns.CanDisenchant = function(capability)
  return capability == "FULL" or capability == "GARRISON"
end




local ItemTooltip = CreateFrame("GameTooltip", "temptt")
do
  local fontstrings = {}
  for i = 1, 6 do
    local L,R = ItemTooltip:CreateFontString(), ItemTooltip:CreateFontString()
    L:SetFontObject(GameFontNormal)
    R:SetFontObject(GameFontNormal)
    ItemTooltip:AddFontStrings(L,R)
    table.insert(fontstrings,L)
  end
  ItemTooltip.strings = fontstrings
  --ItemTooltip:SetOwner(UIParent,"ANCHOR_NONE")
  --ItemTooltip:SetHyperlink('item:')
end
ns.IsSlotSoulbound = function(bag, slot)
  ItemTooltip:SetOwner(UIParent,"ANCHOR_NONE")
  ItemTooltip:SetBagItem(bag, slot)

  for i,v in ipairs(ItemTooltip.strings) do
    if v:GetText() == ITEM_SOULBOUND then
      return true
    end
  end
  return false
end
