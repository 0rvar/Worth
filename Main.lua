local addon, ns = ...
local unpack, pairs, ipairs, table, math = unpack, pairs, ipairs, table, math
local _G = _G

local GetMoney = GetMoney
local GetItemInfo = GetItemInfo
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemID = GetContainerItemID
local NUM_BAG_SLOTS, NUM_BANKBAGSLOTS = NUM_BAG_SLOTS, NUM_BANKBAGSLOTS
local GetNumEquipmentSets = GetNumEquipmentSets
local GetEquipmentSetInfo = GetEquipmentSetInfo
local GetEquipmentSetLocations = GetEquipmentSetLocations
local EquipmentManager_UnpackLocation = EquipmentManager_UnpackLocation

local C = ns.C

local PLAYER = UnitName("player")
local FACTION = UnitFactionGroup("player")
local CLASS = UnitClass("player")
local REALM = GetRealmName()
local DB = {}
local SessionStart = {}

local function CalculateTotalMoney()
  if not DB or not DB[FACTION] or not DB[FACTION][REALM] then
    return 0
  end
  local total = 0
  for _,player in pairs(DB[FACTION][REALM]) do
    total = total + player.money
  end
  return total
end

local function CalculateTotalItemValue()
  if not DB or not DB[FACTION] or not DB[FACTION][REALM] then
    return 0
  end
  local total = 0
  for _,player in pairs(DB[FACTION][REALM]) do
    for _,item in ipairs(player.bagItems) do
      local unit_worth, _ =
        ns.GetItemValue(item.id, item.soulbound, player.disenchant_capability)
      total = total + unit_worth * item.count
    end
    for _,item in ipairs(player.bankItems) do
      local unit_worth, _ =
        ns.GetItemValue(item.id, item.soulbound, player.disenchant_capability)
      total = total + unit_worth * item.count
    end
  end
  return total
end

local function CalculateWorth()
  return CalculateTotalMoney() + CalculateTotalItemValue()
end




local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local icon = {
  iconfile="Interface\\icons\\achievement_challengemode_gold",
  coords={0.1,0.9,0.1,0.9}
}
local dataobj = ldb:NewDataObject("Water", {
  type          = "data source",
  text          = "",
  icon          = icon.iconfile, -- default or custom icon
  staticIcon    = icon.iconfile, -- default icon only
  iconCoords    = icon.coords,
})

local LibQTip = LibStub('LibQTip-1.0')
function dataobj:OnEnter()
  local tooltip = LibQTip:Acquire(addon.."TT", 3, "LEFT", "RIGHT", "RIGHT")
  self.tooltip = tooltip
  buildTooltip(tooltip)
  tooltip:SmartAnchorTo(self)
  tooltip:Show()
end
function dataobj:OnLeave()
  -- Release the tooltip
  LibQTip:Release(self.tooltip)
  self.tooltip = nil
end
function buildTooltip(tooltip)
  local totalItemValue = CalculateTotalItemValue()
  local totalMoney = CalculateTotalMoney()
  local items = {}
  local top = {}
  local byCharacter = {}
  local byProspect = {}

  -- Aggregate items, sum by character, sum by value prospect
  for name,player in pairs(DB[FACTION][REALM]) do
    byCharacter[name] = {
      money = player.money,
      itemValue = 0,
      class = player.class
    }
    local function add(item)
      local unit_worth, prospect = ns.GetItemValue(item.id, item.soulbound, player.disenchant_capability)
      local x = unit_worth * item.count
      byCharacter[name].itemValue = byCharacter[name].itemValue + x
      byProspect[prospect] = (byProspect[prospect] or 0) + x

      items[item.id] = items[item.id] or {
        unit_worth = unit_worth,
        count = 0,
        prospect = prospect
      }
      items[item.id].count = items[item.id].count + item.count
    end
    for _,item in ipairs(player.bagItems) do
      add(item)
    end
    for _,item in ipairs(player.bankItems) do
      add(item)
    end
  end

  -- Build item list sorted by value
  for id,item in pairs(items) do
    local val = item.count * item.unit_worth
    local _, link, _ = GetItemInfo(id)
    table.insert(top, {link = link, count = item.count, value = val})
  end
  local function compareByValue(a,b)
    return a.value > b.value
  end
  table.sort(top, compareByValue)

  -- Build tooltip
  tooltip:AddHeader(
    C('dkyellow', 'Per character'),
    C('dkyellow', 'Gold'),
    C('dkyellow', 'Items'))
  tooltip:AddSeparator()
  for name,p in pairs(byCharacter) do
    tooltip:AddLine(C(p.class, name),
      ns.GetShortCoinString(p.money),
      ns.GetShortCoinString(p.itemValue))
  end
  tooltip:AddSeparator()
  tooltip:AddLine("Total",
    ns.GetShortCoinString(totalMoney),
    ns.GetShortCoinString(totalItemValue))
  tooltip:AddLine("Session",
    ns.GetDiffCoinString(totalMoney-SessionStart.totalMoney),
    ns.GetDiffCoinString(totalItemValue-SessionStart.totalItemValue))
  tooltip:AddLine()

  tooltip:AddHeader(
    C('dkyellow', 'Breakdown'),
    nil,
    C('dkyellow', 'Value'))
  tooltip:AddSeparator()
  for p,value in pairs(byProspect) do
    tooltip:AddLine(p, nil, ns.GetShortCoinString(value))
  end
  tooltip:AddLine()

  tooltip:AddHeader(
    C('dkyellow', 'Top items'),
    C('dkyellow', 'Count'),
    C('dkyellow', 'Value'))
  tooltip:AddSeparator()
  for i,item in ipairs(top) do
    tooltip:AddLine(item.link, item.count, ns.GetShortCoinString(item.value))
    if i > 20 then
      return
    end
  end
end

local updateFrame = CreateFrame("Frame")
local function refresh(self, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    updateFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    updateFrame:RegisterEvent("PLAYER_MONEY")
    updateFrame:RegisterEvent("BANKFRAME_OPENED")
  end
  local money = GetMoney()
  local bagItems = {}
  local bankItems = {}

  local blacklist = {}
  for i = 1, GetNumEquipmentSets() do
    local name = GetEquipmentSetInfo(i);
    local infoArray = GetEquipmentSetLocations(name);
    for _,value in pairs(infoArray) do
      if value > 1 then
        local player, bank, bags, voidStorage, slot, bag = EquipmentManager_UnpackLocation(value)
        if bags then
          blacklist[bag] = blacklist[bag] or {}
          blacklist[bag][slot] = true
        end
      end
    end
  end

  for bagID=-1,NUM_BAG_SLOTS+NUM_BANKBAGSLOTS do
    local targetTable = bagItems
    if bagID < 0 or bagID > NUM_BAG_SLOTS then
      targetTable = bankItems
    end
    for slot = 1,GetContainerNumSlots(bagID) do
      local _, itemCount, _, _, _, _, _ = GetContainerItemInfo(bagID, slot)
      if itemCount ~= nil and itemCount > 0 and (blacklist[bagID] == nil or blacklist[bagID][slot] == nil) then
        local itemId = GetContainerItemID(bagID, slot)
        local name,_ = GetItemInfo(itemId)
        if name == nil then
          -- Item is not cached, redo this some other time
          if ns.Debug then ns.Debug("Item not cached, skipping") end
          return
        end
        local soulbound = ns.IsSlotSoulbound(bagID, slot)
        table.insert(targetTable, {id = itemId, count = itemCount, soulbound = soulbound})
      end
    end
  end

  -- AceDB would be great, eh?
  DB[FACTION] = DB[FACTION] or {}
  DB[FACTION][REALM] = DB[FACTION][REALM] or {}
  DB[FACTION][REALM][PLAYER] = DB[FACTION][REALM][PLAYER] or {}

  DB[FACTION][REALM][PLAYER].class = CLASS
  DB[FACTION][REALM][PLAYER].disenchant_capability = ns.GetDECapability()
  DB[FACTION][REALM][PLAYER].money = money
  DB[FACTION][REALM][PLAYER].bagItems = bagItems
  if #bankItems > 0 or not DB[FACTION][REALM][PLAYER].bankItems then
    DB[FACTION][REALM][PLAYER].bankItems = bankItems
  end

  if ns.Debug then ns.Debug("Refresh: "..event, "Worth "..CalculateWorth()) end

  -- Record worth at login - not reliable on first login (why?)
  if SessionStart.totalMoney == nil then
    SessionStart = {
      totalMoney = CalculateTotalMoney(),
      totalItemValue = CalculateTotalItemValue()
    }
  end
  dataobj.text = ns.GetShortCoinString(CalculateWorth())
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addon then
    _G[addon.."DB"] = _G[addon.."DB"] or {}
    DB = _G[addon.."DB"]
    updateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    updateFrame:SetScript("OnEvent", refresh)
    LibStub('LibDBIcon-1.0'):Register(addon, dataobj, DB.dbicon)
  end
end)
